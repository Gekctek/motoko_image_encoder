import Buffer "mo:base/Buffer";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Iter "mo:base/Iter";
import DeflateEncoder "mo:deflate/Deflate/Encoder";
import DeflateDecoder "mo:deflate/Deflate/Decoder";
import NatX "mo:xtended-numbers/NatX";
import BitBuffer "mo:bitbuffer/BitBuffer";

module {
    public type EncodeOptions = {
        colorType : {
            #grayscale : { alpha : Bool };
            #rgb : { alpha : Bool };
            #palette;
        };
        bitDepth : { #b1; #b2; #b4; #b8; #b16 };
        interlace : Bool;
        compressionLevel : Nat8; // 0 to 9
        filterType : ?{ #sub; #up; #average; #paeth };
    };

    public func encodePNG(pixels : [[Nat8]], options : EncodeOptions) : [Nat8] {
        assert (validateOptions(options));

        let width = pixels[0].size();
        let height = pixels.size();

        let buffer = Buffer.Buffer<Nat8>(0);
        writeHeader(buffer);
        writeIhdrChunk(buffer, width, height, options);
        writeIdatChunk(buffer, pixels, options);
        writeIendChunk(buffer);

        Buffer.toArray(buffer);
    };

    private func writeHeader(buffer : Buffer.Buffer<Nat8>) {
        buffer.add(137);
        buffer.add(80);
        buffer.add(78);
        buffer.add(71);
        buffer.add(13);
        buffer.add(10);
        buffer.add(26);
        buffer.add(10);
    };

    private func writeIhdrChunk(
        buffer : Buffer.Buffer<Nat8>,
        width : Nat,
        height : Nat,
        options : EncodeOptions,
    ) {

        NatX.encodeNat32(buffer, 13, #msb); // Length

        buffer.add(73); // 'I'
        buffer.add(72); // 'H'
        buffer.add(68); // 'D'
        buffer.add(82); // 'R'

        NatX.encodeNat32(buffer, Nat32.fromNat(width), #msb);
        NatX.encodeNat32(buffer, Nat32.fromNat(height), #msb);

        buffer.add(bitDepthToNat8(options.bitDepth));
        buffer.add(colorTypeToNat8(options.colorType));
        buffer.add(0); // Compression method
        buffer.add(0); // Filter method
        buffer.add(if (options.interlace) 1 else 0);

        let crc = crc32(Buffer.subBuffer(buffer, 0, 4));
        NatX.encodeNat32(buffer, crc, #msb);

        buffer.append(buffer);
    };

    private func writeIdatChunk(
        buffer : Buffer.Buffer<Nat8>,
        pixels : [[Nat8]],
        options : EncodeOptions,
    ) {
        let rawData = Buffer.Buffer<Nat8>(0);
        for (row in pixels.vals()) {
            rawData.add(filterTypeToNat8(options.filterType));
            applyFilter(row, options.filterType, rawData);
        };

        let deflateOptions : DeflateEncoder.DeflateOptions = {
            block_size = 0x8000;
            dynamic_huffman = true;
            lzss = null;
        };
        let bitBuffer = BitBuffer.BitBuffer(0);
        let encoder = DeflateEncoder.Encoder(bitBuffer, deflateOptions);

        encoder.encode(Buffer.toArray(rawData));

        let compressedData = Buffer.fromIter<Nat8>(bitBuffer.bytes());

        NatX.encodeNat32(buffer, Nat32.fromNat(compressedData.size()), #msb);

        buffer.add(73); // 'I'
        buffer.add(68); // 'D'
        buffer.add(65); // 'A'
        buffer.add(84); // 'T'

        buffer.append(compressedData);

        let crc = crc32(Buffer.subBuffer(buffer, buffer.size() - compressedData.size(), buffer.size()));
        NatX.encodeNat32(buffer, crc, #msb);
    };

    private func writeIendChunk(buffer : Buffer.Buffer<Nat8>) {
        buffer.add(0);
        buffer.add(0);
        buffer.add(0);
        buffer.add(0); // Length
        buffer.add(73); // 'I'
        buffer.add(69); // 'E'
        buffer.add(78); // 'N'
        buffer.add(68); // 'D'
        buffer.add(174);
        buffer.add(66);
        buffer.add(96);
        buffer.add(130); // CRC
    };

    private func crc32(data : Buffer.Buffer<Nat8>) : Nat32 {
        var crc : Nat32 = 0xFFFFFFFF;
        for (byte in data.vals()) {
            crc ^= Nat32.fromNat(Nat8.toNat(byte));
            for (_ in Iter.range(0, 7)) {
                if (crc & 1 == 1) {
                    crc := (crc >> 1) ^ 0xEDB88320;
                } else {
                    crc >>= 1;
                };
            };
        };
        crc ^ 0xFFFFFFFF;
    };

    private func validateOptions(options : EncodeOptions) : Bool {
        if (options.compressionLevel > 9) {
            return false;
        };
        true;
    };

    private func bitDepthToNat8(bitDepth : { #b1; #b2; #b4; #b8; #b16 }) : Nat8 {
        switch (bitDepth) {
            case (#b1) 1;
            case (#b2) 2;
            case (#b4) 4;
            case (#b8) 8;
            case (#b16) 16;
        };
    };

    private func colorTypeToNat8(colorType : { #grayscale : { alpha : Bool }; #rgb : { alpha : Bool }; #palette }) : Nat8 {
        switch (colorType) {
            case (#grayscale({ alpha })) if (alpha) 4 else 0;
            case (#rgb({ alpha })) if (alpha) 6 else 2;
            case (#palette) 3;
        };
    };

    private func filterTypeToNat8(filterType : ?{ #sub; #up; #average; #paeth }) : Nat8 {
        switch (filterType) {
            case (null) 0;
            case (? #sub) 1;
            case (? #up) 2;
            case (? #average) 3;
            case (? #paeth) 4;
        };
    };

    private func applyFilter(
        row : [Nat8],
        filterType : ?{ #sub; #up; #average; #paeth },
        output : Buffer.Buffer<Nat8>,
    ) {
        // Implement filter algorithms here
        // For simplicity, this example just copies the row without filtering
        for (pixel in row.vals()) {
            output.add(pixel);
        };
    };
};

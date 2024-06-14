import Foundation

public struct PBMImageWriter<Bits: Sequence<UInt8>> {

    // In case of plane output returned value will be data of String in .ascii encoding
    // (.utf8, obviously, works as well).
    // In case of raw (binary) output, Data returned shouldn't be used for constructing String
    // as encoding cannot be defined.
    public static func write(images: [(cols: Int, rows: Int, pixels: Bits)], forcePlane: Bool) throws -> Data {
        guard let tmpUrl = createTemporaryFile() else {
            throw WriteError.ioError
        }
        try write(images: images, pathname: tmpUrl.path, forcePlane: forcePlane)
        let data = try Data(contentsOf: tmpUrl)
        try FileManager.default.removeItem(at: tmpUrl)
        return data
    }

    public static func write(images: [(cols: Int, rows: Int, pixels: Bits)], pathname: String, forcePlane: Bool) throws {
        guard let file: UnsafeMutablePointer<FILE> = fopen(pathname, "w") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        try write(images: images, file: file, forcePlane: forcePlane)
        guard fclose(file) != EOF else {
            throw WriteError.ioError
        }
    }

    static func write(images: [(cols: Int, rows: Int, pixels: Bits)], file: UnsafeMutablePointer<FILE>, forcePlane: Bool) throws {
        let imagesCount = images.count
        for (i, image) in images.enumerated() {
            try _pbm_writepbm(
                file,
                bits: image.pixels.map { Bit(rawValue: Int($0))! },
                cols: Int32(image.cols), rows: Int32(image.rows),
                forcePlain: forcePlane
            )
            if i < imagesCount - 1 { // TODO: only do this in plane text mode?
                guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
                    throw WriteError.ioError
                }
            }
        }
    }

}

func _pbm_writepbm(_ file: UnsafeMutablePointer<FILE>, bits: [Bit], cols: Int32, rows: Int32, forcePlain: Bool) throws {
    try _pbm_writepbminit(file, cols: cols, rows: rows, forcePlain: forcePlain)
    if forcePlain {
        try _writePbmBitsPlain(file, bits: bits, cols: cols, rows: rows)
    } else {
        try _writePbmBitsRaw(file, bits: bits, cols: cols, rows: rows)
    }
}

func _pbm_writepbminit(_ file: UnsafeMutablePointer<FILE>, cols: Int32, rows: Int32, forcePlain: Bool) throws {
    /* For Caller's convenience, we include validating computability of the
       image dimensions, since Caller may be using them in arithmetic after
       our return.
    */
    try _pbm_validateComputableSize(cols: cols, rows: rows)
    let magic = String(format: "%c%c\n%d %d\n", PBM_MAGIC1, forcePlain ? PBM_MAGIC2 : RPBM_MAGIC2, cols, rows)
    guard magic.withCString({ fputs($0, file) }) != EOF else {
        throw WriteError.ioError
    }
}

func _writePbmBitsPlain(_ file: UnsafeMutablePointer<FILE>, bits: [Bit], cols: Int32, rows: Int32) throws {
    precondition(bits.count == cols * rows)
    for row in 0..<rows {
        var charCount = 0
        for col in 0..<cols {
            let bit = bits[Int(row * cols + col)]
            guard putc(Int32(Character(bit == .zero ? "0" : "1").asciiValue!), file) != EOF else {
                throw WriteError.ioError
            }
            charCount += 1
            if charCount >= 70 && col < cols - 1 {
                guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
                    throw WriteError.ioError
                }
                charCount = 0
            }
        }
        guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
            throw WriteError.ioError
        }
    }
}

func _writePbmBitsRaw(_ file: UnsafeMutablePointer<FILE>, bits: [Bit], cols: Int32, rows: Int32) throws {
    precondition(bits.count == cols * rows)
    for row in 0..<rows {
        let startIndex = Int(row * cols)
        let rowSlice = bits[startIndex ..< startIndex + Int(cols)]
        try _writePbmRowRaw(file, bits: Array(rowSlice))
    }
    guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
        throw WriteError.ioError
    }
}

func _writePbmRowRaw(_ file: UnsafeMutablePointer<FILE>, bits: [Bit]) throws {
    try _writePackedRawRow(file, packedBits: bits.packed())
}

// TODO: try using sequence instead of array
func _writePackedRawRow(_ file: UnsafeMutablePointer<FILE>, packedBits: [UInt8]) throws {
    let packedByteCt = packedBits.count
    let writtenByteCt = fwrite(packedBits, 1, packedByteCt, file)
    if writtenByteCt < packedByteCt {
        print("I/O error writing packed row to raw PBM file. (Attempted fwrite() of \(packedByteCt) packed bytes; only \(writtenByteCt) got written)")
        throw WriteError.ioError
    }
}

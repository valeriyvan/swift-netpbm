import Foundation

public enum PgmWriteError: Error {
    case ioError
    case wrongMaxVal
}

public struct PGMImageWriter/*<Grays: Sequence<Gray>>*/ {
    // In case of plane output returned value will be data of String in .ascii encoding
    // (.utf8, obviously, works as well).
    // In case of raw (binary) output, Data returned shouldn't be used for constructing String
    // as encoding cannot be defined.
    public static func write(images: [(cols: Int, rows: Int, maxValue: Gray, pixels: [Gray])], forcePlane: Bool) throws -> Data {
        assert(images.allSatisfy { image in image.pixels.allSatisfy { $0 <= image.maxValue } })
        guard let tmpUrl = createTemporaryFile() else {
            throw PgmWriteError.ioError
        }
        try write(images: images, pathname: tmpUrl.path, forcePlane: forcePlane)
        let data = try Data(contentsOf: tmpUrl)
        try FileManager.default.removeItem(at: tmpUrl)
        return data
    }

    public static func write(images: [(cols: Int, rows: Int, maxValue: Gray, pixels: [Gray])], pathname: String, forcePlane: Bool) throws {
        guard let file: UnsafeMutablePointer<FILE> = fopen(pathname, "w") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        try write(images: images, file: file, forcePlane: forcePlane)
        guard fclose(file) != EOF else {
            throw PgmWriteError.ioError
        }
    }

    static func write(images: [(cols: Int, rows: Int, maxValue: Gray, pixels: [Gray])], file: UnsafeMutablePointer<FILE>, forcePlane: Bool) throws {
        let imagesCount = images.count
        for (i, image) in images.enumerated() {
            try _pgm_writepgm(
                file,
                grays: image.pixels,
                cols: Int32(image.cols), rows: Int32(image.rows),
                maxVal: image.maxValue,
                forceplain: forcePlane
            )
            if i < imagesCount - 1 { // TODO: only do this in plane text mode?
                guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
                    throw PgmWriteError.ioError
                }
            }
        }
    }

}

func _pgm_writepgm(_ file: UnsafeMutablePointer<FILE>, grays: [Gray], cols: Int32, rows: Int32, maxVal: Gray, forceplain: Bool) throws {

    try _pgm_writepgminit(file, grays: grays, cols: cols, rows: rows, maxVal: maxVal, forceplain: forceplain)

    for row in 0..<rows {
        try _pgm_writepgmrow(
            file,
            grayrow: Array(grays[Int(row * cols) ..< Int((row + 1) * cols)]),
            cols: cols,
            maxVal: maxVal,
            forceplain: forceplain
        )
    }
}

func _pgm_writepgminit(_ file: UnsafeMutablePointer<FILE>, grays: [Gray], cols: Int32, rows: Int32, maxVal: Gray, forceplain: Bool) throws {
    /* For Caller's convenience, we include validating computability of the
       image parameters, since Caller may be using them in arithmetic after
       our return.
    */
    try _pgm_validateComputableSize(cols: cols, rows: rows)
    try _pgm_validateComputableMaxval(maxVal: maxVal)

    if maxVal > PGM_OVERALLMAXVAL && !forceplain {
        print("too-large maxval passed to ppm_writepgminit(): \(maxVal). Maximum allowed by the PGM format is \(PGM_OVERALLMAXVAL).")
        throw PgmWriteError.wrongMaxVal
    }

    let magic = String(format: "%c%c\n%d %d\n%d\n", PGM_MAGIC1, forceplain || maxVal >= 1<<16 ? PGM_MAGIC2 : RPGM_MAGIC2, cols, rows, maxVal)

    guard magic.withCString({ fputs($0, file) }) != EOF else {
        throw PgmWriteError.ioError
    }
}

// TODO: modify to work with array slices for grayrow
func _pgm_writepgmrow(_ file: UnsafeMutablePointer<FILE>, grayrow: [Gray], cols: Int32, maxVal: Gray, forceplain: Bool) throws {

    if forceplain || maxVal >= 1<<16 {
        try _writepgmrowplain(file, grayrow: grayrow, cols: cols, maxVal: maxVal)
    } else {
        try _writepgmrowraw(file, grayrow: grayrow, cols: cols, maxVal: maxVal)
    }
}

func _writepgmrowplain(_ file: UnsafeMutablePointer<FILE>, grayrow: [Gray], cols: Int32, maxVal: Gray) throws {
    var row = ""
    var lineCount = 0
    for col in 0..<Int(cols) {
        let element = grayrow[col]
        let strElement = String(element)
        let strElementCount = strElement.count
        if lineCount == 0 {
            row += strElement
            lineCount += strElementCount
        } else if lineCount + 1 + strElement.count < 70 {
            row += " " + strElement
            lineCount += 1 + strElementCount
        } else {
            row += "\n" + strElement
            lineCount = strElementCount
        }
    }
    if lineCount > 0 { // TODO: this check looks redundant
        row += "\n"
    }
    try row.withCString {
        guard fputs($0, file) != EOF else {
            throw PgmParseError.ioError
        }
    }
}

func _writepgmrowraw(_ file: UnsafeMutablePointer<FILE>, grayrow: [Gray], cols: Int32, maxVal: Gray) throws {
    let bytesPerSample = maxVal < 256 ? 1 : 2 // TODO: !!!
    let bytesPerRow = Int(cols) * bytesPerSample

    let rowBuffer = malloc(bytesPerRow)
    if rowBuffer == nil {
        print("Unable to allocate memory for row buffer for \(cols) columns")
        throw PgmParseError.insufficientMemory
    }

    if maxVal < 256 {
        _format1bpsRow(grayrow: grayrow, cols: cols, rowBuffer: rowBuffer!)
    } else {
        _format2bpsRow(grayrow: grayrow, cols: cols, rowBuffer: rowBuffer!)
    }

    let rc = fwrite(rowBuffer, 1, bytesPerRow, file)

    if (rc < 0) {
        print("Error writing row. fwrite() errno=\(errno) (\(String(cString: strerror(errno))))")
        throw PgmWriteError.ioError
    } else {
        let bytesWritten = rc
        if bytesWritten != bytesPerRow {
            print("Error writing row. Short write of \(bytesWritten) bytes instead of \(bytesPerRow)")
        }
    }
    free(rowBuffer)
}

// TODO: Check implementation
func _format1bpsRow(grayrow: [Gray], cols: Int32, rowBuffer: UnsafeMutableRawPointer) {
    /* single byte samples. */
    var bufferCursor = 0
    for col in 0..<Int(cols) {
        rowBuffer.assumingMemoryBound(to: UInt8.self).advanced(by: bufferCursor).pointee = UInt8(grayrow[col])
        bufferCursor += 1
    }
}

// TODO: Check implementation
func _format2bpsRow(grayrow: [Gray], cols: Int32, rowBuffer: UnsafeMutableRawPointer) {
    /* two byte samples. */
    var bufferCursor = 0
    for col in 0..<Int(cols) {
        rowBuffer.assumingMemoryBound(to: Gray.self).advanced(by: bufferCursor).pointee = grayrow[col]
        bufferCursor += 1
    }
}

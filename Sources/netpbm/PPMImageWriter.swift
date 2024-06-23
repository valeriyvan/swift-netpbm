import Foundation

public struct PPMImageWriter {

    // In case of plane output returned value will be data of String in .ascii encoding
    // (.utf8, obviously, works as well).
    // In case of raw (binary) output, Data returned shouldn't be used for constructing String
    // as encoding cannot be defined.
    public static func write(images: [(cols: Int, rows: Int, maxValue: Pixval, pixels: [Pixel])], forcePlane: Bool) throws -> Data {
        assert(images.allSatisfy { image in image.pixels.allSatisfy { $0.r <= image.maxValue && $0.g <= image.maxValue && $0.b <= image.maxValue } })
        guard let tmpUrl = createTemporaryFile() else {
            throw WriteError.ioError
        }
        try write(images: images, pathname: tmpUrl.path, forcePlane: forcePlane)
        let data = try Data(contentsOf: tmpUrl)
        try FileManager.default.removeItem(at: tmpUrl)
        return data
    }

    public static func write(images: [(cols: Int, rows: Int, maxValue: Pixval, pixels: [Pixel])], pathname: String, forcePlane: Bool) throws {
        guard let file: UnsafeMutablePointer<FILE> = fopen(pathname, "w") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        try write(images: images, file: file, forcePlane: forcePlane)
        guard fclose(file) != EOF else {
            throw WriteError.ioError
        }
    }

    static func write(images: [(cols: Int, rows: Int, maxValue: Pixval, pixels: [Pixel])], file: UnsafeMutablePointer<FILE>, forcePlane: Bool) throws {
        let imagesCount = images.count
        for (i, image) in images.enumerated() {
            try _ppm_writeppm(
                file,
                pixels: image.pixels,
                cols: Int32(image.cols), rows: Int32(image.rows),
                maxVal: image.maxValue,
                forceplain: forcePlane
            )
            if i < imagesCount - 1 { // TODO: only do this in plane text mode?
                guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
                    throw WriteError.ioError
                }
            }
        }
    }

}

func _ppm_writeppm(_ file: UnsafeMutablePointer<FILE>, pixels: [Pixel], cols: Int32, rows: Int32, maxVal: Pixval, forceplain: Bool) throws {
    try _ppm_writeppminit(file, cols: cols, rows: rows, maxVal: maxVal, forceplain: forceplain)
    for row in 0..<Int(rows) {
        try _ppm_writeppmrow(file, pixelrow: pixels[row * Int(cols) ..< (row + 1) * Int(cols)], maxVal: maxVal, forceplain: forceplain)
    }
}

func _ppm_writeppmrow(_ file: UnsafeMutablePointer<FILE>, pixelrow: ArraySlice<Pixel>, maxVal: Pixval, forceplain: Bool) throws {
    if forceplain || maxVal >= 1<<16 {
        try _ppm_writeppmrowplain(file, pixelrow: pixelrow, maxVal: maxVal)
    } else {
        try _ppm_writeppmrowraw(file, pixelrow: pixelrow, maxVal: maxVal)
    }
}

func _ppm_writeppminit(_ file: UnsafeMutablePointer<FILE>, cols: Int32, rows: Int32, maxVal: Pixval, forceplain: Bool) throws {
    let plainFormat = forceplain
    /* For Caller's convenience, we include validating computability of the
       image parameters, since Caller may be using them in arithmetic after
       our return.
    */
    try _ppm_validateComputableSize(cols: cols, rows: rows)
    try _pgm_validateComputableMaxval(maxVal: maxVal)
    if maxVal > PPM_OVERALLMAXVAL && !plainFormat {
        print("Too-large maxval passed to ppm_writeppminit(): \(maxVal). Maximum allowed by the PPM format is \(PPM_OVERALLMAXVAL).")
        throw WriteError.wrongMaxVal
    }
    let magic = String(format: "%c%c\n%d %d\n%d\n", PPM_MAGIC1, plainFormat || maxVal >= 1<<16 ? PPM_MAGIC2 : RPPM_MAGIC2, cols, rows, maxVal)
    guard magic.withCString({ fputs($0, file) }) != EOF else {
        throw WriteError.ioError
    }
}


func _ppm_writeppmrowraw(_ file: UnsafeMutablePointer<FILE>, pixelrow: ArraySlice<Pixel>, maxVal: Pixval) throws {
    let buffer: UnsafeRawBufferPointer = maxVal < 256 ?
    _format1bpsRow(pixelrow: pixelrow) : _format2bpsRow(pixelrow: pixelrow)
    defer { buffer.deallocate() }
    guard fwrite(buffer.baseAddress!, 1, buffer.count, file) == buffer.count else {
        print("Error writing row. fwrite() errno=\(errno) (\(String(cString: strerror(errno)))")
        throw WriteError.ioError
    }
}

func _ppm_writeppmrowplain(_ file: UnsafeMutablePointer<FILE>, pixelrow: ArraySlice<Pixel>, maxVal: Pixval) throws {
    var row = ""
    var lineCount = 0 // To avoid loop going quadratic
    for pixel in pixelrow {
        let strPixel = "\(pixel.r) \(pixel.g) \(pixel.b)"
        let strPixelCount = strPixel.count
        if lineCount == 0 {
            row += strPixel
            lineCount += strPixelCount
        } else if lineCount + 1 + strPixel.count < 70 {
            row += " " + strPixel
            lineCount += 1 + strPixelCount
        } else {
            row += "\n" + strPixel
            lineCount = strPixelCount
        }
    }
    if lineCount > 0 { // TODO: this check looks redundant
        row += "\n"
    }
    try row.withCString {
        guard fputs($0, file) != EOF else {
            throw WriteError.ioError
        }
    }
}

func _format1bpsRow(pixelrow: ArraySlice<Pixel>) -> UnsafeRawBufferPointer {
    /* single byte samples. */
    let byteCount = pixelrow.count * 3
    let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<UInt8>.alignment)
    // TODO: it looks like trivial loop for buffer copying will be much more effective
    pixelrow
        .flatMap { [UInt8($0.r), UInt8($0.g), UInt8($0.b)] }
        .withUnsafeBytes {
            rawPointer.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
    return UnsafeRawBufferPointer(start: rawPointer, count: byteCount)
}

func _format2bpsRow(pixelrow: ArraySlice<Pixel>) -> UnsafeRawBufferPointer {
    /* two byte samples. */
    let byteCount = pixelrow.count * 3 * 2
    let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<UInt8>.alignment)
    // TODO: it looks like trivial loop for buffer copying will be much more effective
    pixelrow
        .flatMap {
            [
                UInt8($0.r >> 8 & 0xff),
                UInt8($0.r & 0xff),
                UInt8($0.g >> 8 & 0xff),
                UInt8($0.g & 0xff),
                UInt8($0.b >> 8 & 0xff),
                UInt8($0.b & 0xff)
            ]
        }
        .withUnsafeBytes {
            rawPointer.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
    return UnsafeRawBufferPointer(start: rawPointer, count: byteCount)
}

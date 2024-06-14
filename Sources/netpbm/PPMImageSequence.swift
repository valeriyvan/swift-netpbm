import Foundation
import Algorithms // chunks

public struct PPMImageSequence: ImageAsyncSequence {
    public typealias Element = PPMImagePixelSequence
    public typealias AsyncIterator = PPMImageAsyncIterator

    public var file: UnsafeMutablePointer<FILE> { fileWrapper.file }
    public var fileWrapper: FileWrapper

    public init(fileWrapper: FileWrapper) throws {
        self.fileWrapper = fileWrapper
    }

    public func makeAsyncIterator() -> PPMImageAsyncIterator {
        return PPMImageAsyncIterator(file: file)
    }
}

public struct PPMImageAsyncIterator: ImageAsyncIteratorProtocol {
    public typealias Element = PPMImagePixelSequence

    public var file: UnsafeMutablePointer<FILE>

    public init(file: UnsafeMutablePointer<FILE>) {
        self.file = file
    }

    public mutating func next() async throws -> PPMImagePixelSequence? {
        let eof = try _pm_nextimage(file)
        guard !eof else { return nil }
        return try PPMImagePixelSequence(file: file)
    }
}

public struct PPMImagePixelSequence: ImageElementAsyncSequence {
    public typealias Element = Pixel
    public typealias AsyncIterator = PPMImagePixelAsyncIterator

    public var width: Int { Int(cols) }
    public var height: Int { Int(rows) }
    public var file: UnsafeMutablePointer<FILE>
    public var cols: Int32
    public var rows: Int32
    public let maxValue: Pixval
    public var format: Int32

    public init(file: UnsafeMutablePointer<FILE>) throws {
        self.file = file
        (cols, rows, maxValue, format) = try _ppm_readppminit(file) // TODO: test with broken header
    }

    public func makeAsyncIterator() -> PPMImagePixelAsyncIterator {
        return PPMImagePixelAsyncIterator(file: file, cols: cols, rows: rows, maxVal: maxValue, format: format)
    }
}

public struct PPMImagePixelAsyncIterator: ImageElementAsyncIteratorProtocol {
    public typealias Element = Pixel

    public var row: [Pixel] = []
    public var currentRow: Int = -1
    public var currentElementIndex: Int = 0
    public var cols: Int32
    public var rows: Int32
    public let maxVal: Pixval
    public var format: Int32
    public var file: UnsafeMutablePointer<FILE>

    init(file: UnsafeMutablePointer<FILE>, cols: Int32, rows: Int32, maxVal: Pixval, format: Int32) {
        self.file = file
        self.cols = cols
        self.rows = rows
        self.maxVal = maxVal
        self.format = format
    }

    public mutating func readRow() throws -> [Pixel] {
        try _ppm_readppmrow(file, cols: cols, maxVal: maxVal, format: format)
    }
}

public enum PpmParseError: Error {
    case wrongFormat // header is wrong
    case ioError
//    case internalInconsistency
    case insufficientMemory
    case unexpectedEndOfFile
//    case junkWhereBitsShouldBe
//    case junkWhereUnsignedIntegerShouldBe
//    case tooBigNumber
    case imageTooLarge
    case badPixelValue
}

let PPM_OVERALLMAXVAL = PGM_OVERALLMAXVAL
let PPM_MAXMAXVAL = PGM_MAXMAXVAL

public typealias Pixval = Gray

public struct Pixel: Equatable {
    var r: Pixval
    var g: Pixval
    var b: Pixval
}

func _ppm_readppminit(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32, maxVal: Pixval, format: Int32) {
    /* Check magic number. */
    let realFormat = try _pm_readmagicnumber(file)
    var cols: Int32 = 0, rows: Int32 = 0
    var maxVal: Pixval = 0
    var format: Int32
    switch PAM_FORMAT_TYPE(realFormat) {
    case PPM_TYPE:
        format = realFormat
        (cols, rows, maxVal) = try _ppm_readppminitrest(file)
    case PGM_TYPE:
        format = realFormat
        (cols, rows, maxVal) = try _pgm_readpgminitrest(file)
    case PBM_TYPE:
        format = realFormat
        /* See comment in pgm_readpgminit() about this maxval */
        maxVal = PPM_MAXMAXVAL
        (cols, rows) = try _pbm_readpbminitrest(file)
    case PAM_TYPE:
        (cols, rows, maxVal, format) = try _pnm_readpaminitrestaspnm(file)
    default:
        print("bad magic number \(String(format: "0x%x", realFormat)) - not a PPM, PGM, PBM, or PAM file")
        throw PpmParseError.wrongFormat
    }
    try _ppm_validateComputableSize(cols: cols, rows: rows)

    try _pgm_validateComputableMaxval(maxVal: maxVal)

    return (cols: cols, rows: rows, maxVal: maxVal, format: format)
}

func _ppm_readppminitrest(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32, maxVal: Pixval) {
    return try _pgm_readpgminitrest(file)
}

func _ppm_validateComputableSize(cols: Int32, rows: Int32) throws {
/*----------------------------------------------------------------------------
   Validate that the dimensions of the image are such that it can be
   processed in typical ways on this machine without worrying about
   overflows.  Note that in C, arithmetic is always modulus
   arithmetic, so if your values are too big, the result is not what
   you expect.  That failed expectation can be disastrous if you use
   it to allocate memory.

   It is very normal to allocate space for a pixel row, so we make sure
   the size of a pixel row, in bytes, can be represented by an 'int'.

   A common operation is adding 1 or 2 to the highest row or
   column number in the image, so we make sure that's possible.
-----------------------------------------------------------------------------*/
    if cols > Int32.max / (Int32(MemoryLayout<Pixval>.size) * 3) || cols > Int32.max - 2 {
        print("image width (\(cols) too large to be processed")
        throw PpmParseError.imageTooLarge
    }
    if rows > Int32.max - 2 {
        print("image height (\(rows) too large to be processed")
        throw PpmParseError.imageTooLarge
    }
}

func _ppm_readppmrow(_ file: UnsafeMutablePointer<FILE>, cols: Int32, maxVal: Pixval, format: Int32) throws -> [Pixel] {
    switch (format) {
    case PPM_FORMAT:
        return try _readPpmRow(file, cols: cols, maxVal: maxVal, format: format)
    /* For PAM, we require a depth of 3, which means the raster format
       is identical to Raw PPM!  How convenient.
    */
    case PAM_FORMAT:
        fallthrough
    case RPPM_FORMAT:
        return try _readRppmRow(file, cols: cols, maxVal: maxVal, format: format)
    case PGM_FORMAT:
        fallthrough
    case RPGM_FORMAT:
        fatalError("Not implemented")
        // return try _readPgmRow(file, cols: cols, maxVal: maxVal, format: format)
    case PBM_FORMAT:
        fallthrough
    case RPBM_FORMAT:
        fatalError("Not implemented")
        // return try _readPbmRow(file, cols: cols, maxVal: maxVal, format: format)
    default:
        print("Invalid format code")
        throw PpmParseError.wrongFormat
    }
}

func _readPpmRow(_ file: UnsafeMutablePointer<FILE>, cols: Int32, maxVal: Pixval, format: Int32) throws -> [Pixel] {
    var row: [Pixel] = []
    row.reserveCapacity(Int(cols))
    for _ in 0..<Int(cols) {
        let r: Pixval = try _pm_getuint(file)
        let g: Pixval = try _pm_getuint(file)
        let b: Pixval = try _pm_getuint(file)
        if r > maxVal {
            print("Red sample value \(r) is greater than maxval (\(maxVal)")
            throw PpmParseError.wrongFormat // ???
        }
        if g > maxVal {
            print("Green sample value \(g) is greater than maxval (\(maxVal)")
            throw PpmParseError.wrongFormat // ???
        }
        if b > maxVal {
            print("Blue sample value \(b) is greater than maxval (\(maxVal)")
            throw PpmParseError.wrongFormat // ???
        }
        row.append(Pixel(r: r, g: g, b: b))
    }
    return row
}

func _readRppmRow(_ file: UnsafeMutablePointer<FILE>, cols: Int32, maxVal: Pixval, format: Int32) throws -> [Pixel] {
    let bytesPerSample = maxVal < 256 ? 1 : 2
    let bytesPerRow = Int(cols) * 3 * bytesPerSample

    let rowBuffer = malloc(bytesPerRow)
    guard let rowBuffer else {
        print("Unable to allocate memory for row buffer for \(cols) columns")
        throw PpmParseError.insufficientMemory
    }
    defer { free(rowBuffer) }

    let rc = fread(rowBuffer, 1, bytesPerRow, file)
    guard feof(file) != EOF else {
        print("Unexpected EOF reading row of PPM image.")
        throw PpmParseError.unexpectedEndOfFile
    }
    guard ferror(file) == 0 else {
        print("Error reading row.  fread() errno=\(errno) (\(String(cString: strerror(errno)))")
        throw PpmParseError.ioError
    }

    let bytesRead = rc
    guard bytesRead == bytesPerRow else {
        print("Error reading row.  Short read of \(bytesRead) bytes instead of \(bytesPerRow)")
        throw PpmParseError.ioError
    }
    let row = try _interpRasterRowRaw(rowBuffer: rowBuffer, cols: cols, bytesPerSample: bytesPerSample)
    try _validateRppmRow(row: row, cols: cols, maxVal: maxVal)
    return row
}

func _interpRasterRowRaw (rowBuffer: UnsafeMutableRawPointer, cols: Int32, bytesPerSample: Int) throws -> [Pixel] {
    if bytesPerSample == 1 {
        return UnsafeBufferPointer<UInt8>(
                start: rowBuffer.bindMemory(to: UInt8.self, capacity: 1),
                count: Int(cols) * 3
            )
            .chunks(ofCount: 3)
            .map {
                Pixel(
                    r: Pixval($0[$0.startIndex]), 
                    g: Pixval($0[$0.startIndex.advanced(by: 1)]),
                    b: Pixval($0[$0.startIndex.advanced(by: 2)])
                )
            }
    } else  {
        /* two byte samples */
        return UnsafeBufferPointer<UInt16>(
                start: rowBuffer.bindMemory(to: UInt16.self, capacity: 1),
                count: Int(cols) * 3
            )
            .chunks(ofCount: 3)
            .map {
                Pixel(
                    r: Pixval($0[0]),
                    g: Pixval($0[1]),
                    b: Pixval($0[2]))
            }
    }
}

func _validateRppmRow(row: [Pixel], cols: Int32, maxVal: Pixval) throws {
/*----------------------------------------------------------------------------
  Check for sample values above maxval in input.

  Note: a program that wants to deal with invalid sample values itself can
  simply make sure it uses a sufficiently high maxval on the read function
  call, so this validation never fails.
-----------------------------------------------------------------------------*/
    if maxVal == 255 || maxVal == 65535 {
        /* There's no way a sample can be invalid, so we don't need to look at
           the samples individually.
        */
        return
    } else {
        for pixel in row {
            if pixel.r > maxVal {
                print("Red sample value \(pixel.r) is greater than maxval (\(maxVal))")
                throw PpmParseError.badPixelValue
            }
            else if pixel.g > maxVal {
                print("Green sample value \(pixel.g) is greater than maxval (\(maxVal))")
                throw PpmParseError.badPixelValue
            }
            else if pixel.b > maxVal {
                print("Blue sample value \(pixel.b) is greater than maxval (\(maxVal))")
                throw PpmParseError.badPixelValue
            }
        }
    }
}

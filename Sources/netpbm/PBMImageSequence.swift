import Foundation

// Note about using UnsafeMutablePointer<FILE> instead of FileHandle.
//
// Would be nice to rewrite using FileHandle instead of UnsafeMutablePointer<FILE>.
// UnsafeMutablePointer<FILE> is plane C old API.
// FileHandle is from Objective-C era, but Swift friendly, could close file when FileHandle
// is deallocated, has API for async reading/writing.
// But FileHandle has API fragmented between different macOS versions for simple things
// like reading data from file.
// UnsafeMutablePointer<FILE> is settled API available everywhere.
// So it's questionable if FileHandle usage here is beneficial.

public struct PBMImageSequence: AsyncSequence {

    public typealias Element = PBMImageBitSequence
    public typealias AsyncIterator = Iterator

    public struct Iterator: AsyncIteratorProtocol {
        public let file: UnsafeMutablePointer<FILE>

        public init(file: UnsafeMutablePointer<FILE>) {
            self.file = file
        }

        public mutating func next() async throws -> PBMImageBitSequence? {
            let eof = try _pm_nextimage(file)
            guard !eof else { return nil }
            return try PBMImageBitSequence(file: file)
        }
    }

    public var file: UnsafeMutablePointer<FILE> { fileWrapper.file }

    let fileWrapper: FileWrapper

    public init(data: Data) throws {
        let (file, buffer) = try data.withUnsafeBytes {
            // Make a copy of $0 otherwise file operations will read deallocated memory
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: $0.count, alignment: MemoryLayout<UInt8>.alignment)
            buffer.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
            guard let file: UnsafeMutablePointer<FILE> = fmemopen(buffer, $0.count, "r") else {
                throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
            }
            return (file, buffer)
        }
        self.fileWrapper = FileWrapper(file: file, buffer: buffer)
    }

    public init(pathname: String) throws {
        guard let file: UnsafeMutablePointer<FILE> = fopen(pathname, "r") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        self.fileWrapper = FileWrapper(file: file)
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(file: file)
    }
}

public struct PBMImageBitSequence: AsyncSequence {
    public typealias Element = Bit
    public typealias AsyncIterator = Iterator

    public struct Iterator: AsyncIteratorProtocol {
        var currentRow = -1
        var rowBits: [Bit] = []
        var currentBitIndex = 0
        let cols: Int32
        let rows: Int32
        let format: Int32
        let file: UnsafeMutablePointer<FILE>

        init(file: UnsafeMutablePointer<FILE>, cols: Int32, rows: Int32, format: Int32) {
            self.file = file
            self.cols = cols
            self.rows = rows
            self.format = format
        }

        public mutating func next() async throws -> Bit? {
            if currentRow == -1 {
                rowBits = try _pbm_readpbmrow(file, cols: cols, format: format)
                currentRow = 0
                currentBitIndex = 0
                defer { currentBitIndex += 1 }
                return rowBits[currentBitIndex]
            } else if currentBitIndex < rowBits.count {
                defer { currentBitIndex += 1 }
                return rowBits[currentBitIndex]
            } else if currentRow < rows-1 {
                rowBits = try _pbm_readpbmrow(file, cols: cols, format: format)
                currentRow += 1
                currentBitIndex = 0
                defer { currentBitIndex += 1 }
                return rowBits[currentBitIndex]
            }
            return nil
        }
    }

    public var width: Int { Int(cols) }
    public var height: Int { Int(rows) }

    private let file: UnsafeMutablePointer<FILE>
    private let cols: Int32
    private let rows: Int32
    private let format: Int32

    public init(file: UnsafeMutablePointer<FILE>) throws {
        self.file = file
        (cols, rows, format) = try _pbm_readpbminit(file) // TODO: test with broken header
    }

    public func makeAsyncIterator() -> Iterator {
        return Iterator(file: file, cols: cols, rows: rows, format: format)
    }
}

public enum PbmParseError: Error {
    case wrongFormat // header is wrong
    case ioError
    case internalInconsistency
    case insufficientMemory
    case unexpectedEndOfFile
    case junkWhereBitsShouldBe
    case junkWhereUnsignedIntegerShouldBe
    case tooBigNumber
    case imageTooLarge
}

// Initialize PBM reading, checking the format
func _pbm_readpbminit(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32, format: Int32) {
    let realFormat = try _pm_readmagicnumber(file)

    var cols: Int32 = 0, rows: Int32 = 0
    switch (PAM_FORMAT_TYPE(realFormat)) {
    case PBM_TYPE:
        (cols, rows) = try _pbm_readpbminitrest(file)
    case PGM_TYPE:
        print("""
            The input file is a PGM, not a PBM.  You may want to \
            convert it to PBM with 'pamditherbw | pamtopnm' or \
            'pamthreshold | pamtopnm'
            """
        )
        throw PbmParseError.wrongFormat
    case PPM_TYPE:
            print("""
                The input file is a PPM, not a PBM.  You may want to \
                convert it to PBM with 'ppmtopgm', 'pamditherbw', and \
                'pamtopnm'
                """
            )
            throw PbmParseError.wrongFormat
    case PAM_TYPE:
            print("""
                The input file is a PAM, not a PBM.  \
                If it is a black and white image, you can convert it \
                to PBM with 'pamtopnm'
                """
            )
            throw PbmParseError.wrongFormat
    default:
        print("bad magic number \(String(format: "0x%x", realFormat)) - not a PPM, PGM, PBM, or PAM file")
        throw PbmParseError.wrongFormat
    }
    try _pbm_validateComputableSize(cols: cols, rows: rows)
    return (cols: cols, rows: rows, format: realFormat)
}

// Read the rest of the initialization data (width and height)
func _pbm_readpbminitrest(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32) {
    /* Read size. */
    let cols: UInt32 = try _pm_getuint(file)
    let rows: UInt32 = try _pm_getuint(file)

    /* *colsP and *rowsP really should be unsigned int, but they come
       from the time before unsigned ints (or at least from a person
       trained in that tradition), so they are int.  Caller could simply
       consider negative numbers to mean values > INT_MAX and much
       code would just automatically work.  But some code would fail
       miserably.  So we consider values that won't fit in an int to
       be unprocessable.
    */
    if cols > UInt32.max / 2 { // INT_MAX

        print("Number of columns in header is too large (\(cols)). The maximum allowed by the format is \(UInt32.max / 2).")
        throw PbmParseError.wrongFormat
    }
    if rows > UInt32.max / 2 { // INT_MAX
        print("Number of rows in header is too large (\(rows)). The maximum allowed by the format is \(UInt32.max / 2).")
        throw PbmParseError.wrongFormat
    }
    return (cols: Int32(cols), rows: Int32(rows))
}

// Read the magic number indicating file format
func _pm_readmagicnumber(_ file: UnsafeMutablePointer<FILE>) throws -> Int32 {
    let firstChar = getc(file)
    guard firstChar != EOF else {
        print("""
            Error reading first byte of what is expected to be \
            a Netpbm magic number.
            Most often, this means your input file is empty.
            """
        )
        throw PbmParseError.wrongFormat
    }
    let secondChar = getc(file)
    guard secondChar != EOF else {
        print("""
            Error reading second byte of what is expected to be \
            a Netpbm magic number (the first byte was successfully \
            read as 0x%02x).
            """
        )
        throw PbmParseError.wrongFormat
    }
    return firstChar * 256 + secondChar
}

// Get an unsigned integer from the file
func _pm_getuint(_ file: UnsafeMutablePointer<FILE>) throws -> UInt32 {
/*----------------------------------------------------------------------------
   Read an unsigned integer in ASCII decimal from the file stream
   represented by 'ifP' and return its value.

   If there is nothing at the current position in the file stream that
   can be interpreted as an unsigned integer, issue an error message
   to stderr and abort the program.

   If the number at the current position in the file stream is too
   great to be represented by an 'int' (Yes, I said 'int', not
   'unsigned int'), issue an error message to stderr and abort the
   program.
-----------------------------------------------------------------------------*/
    var ch: Int32 = 0

    repeat {
        ch = _pm_getc(file)
    } while ch == Character(" ").asciiValue! || ch == Character("\t").asciiValue! || ch == Character("\n").asciiValue! || ch == Character("\r").asciiValue!

    if ch < Character("0").asciiValue! || ch > Character("9").asciiValue! {
        print("junk in file where an unsigned integer should be")
        throw PbmParseError.junkWhereUnsignedIntegerShouldBe // TODO: caller should throw exact error
    }

    var i: Int32 = 0
    repeat {
        let digitVal = ch - Int32(Character("0").asciiValue!)

        if i > Int32.max / 10 {
            print("ASCII decimal integer in file is too large to be processed.")
            throw PbmParseError.tooBigNumber // TODO: caller should throw exact error
        }

        i *= 10

        if i > Int32.max - digitVal {
            print("ASCII decimal integer in file is too large to be processed.")
            throw PbmParseError.tooBigNumber // TODO: caller should throw exact error
        }

        i += digitVal

        ch = _pm_getc(file)
    } while ch >= Character("0").asciiValue! && ch <= Character("9").asciiValue!

    return UInt32(i)
}

func _pbm_validateComputableSize(cols: Int32, rows: Int32) throws {
/*----------------------------------------------------------------------------
   Validate that the dimensions of the image are such that it can be
   processed in typical ways on this machine without worrying about
   overflows.  Note that in C, arithmetic is always modulus
   arithmetic, so if your values are too big, the result is not what
   you expect.  That failed expectation can be disastrous if you use
   it to allocate memory.

   See comments at 'validateComputableSize' in libpam.c for details on
   the purpose of these validations.
-----------------------------------------------------------------------------*/
    if cols > Int32.max - 10 {
        print("image width \(cols) too large to be processed")
        throw PbmParseError.imageTooLarge
    }
    if rows > Int32.max - 10 {
        print("image height \(rows) too large to be processed", rows)
        throw PbmParseError.imageTooLarge
    }
}

// Move to the next image in the file stream
// TODO: reverse return value
func _pm_nextimage(_ file: UnsafeMutablePointer<FILE>) throws -> Bool {
/*----------------------------------------------------------------------------
   Position the file 'file' to the next image in the stream, assuming it is
   now positioned just after the current image.  I.e. read off any white
   space at the end of the current image's raster.  Note that the raw formats
   don't permit such white space, but this routine tolerates it anyway,
   because the plain formats do permit white space after the raster.

   Iff there is no next image, return *eofP == TRUE.

   Note that in practice, we will not normally see white space here in
   a plain PPM or plain PGM stream because the routine to read a
   sample from the image reads one character of white space after the
   sample in order to know where the sample ends.  There is not
   normally more than one character of white space (a newline) after
   the last sample in the raster.  But plain PBM is another story.  No white
   space is required between samples of a plain PBM image.  But the raster
   normally ends with a newline nonetheless.  Since the sample reading code
   will not have read that newline, it is there for us to read now.
-----------------------------------------------------------------------------*/
    var eof = false
    var nonWhitespaceFound = false

    while !eof && !nonWhitespaceFound {
        let c = getc(file)
        if c == EOF {
            if feof(file) != 0 {
                eof = true
            } else {
                print("File error on getc() to position to image.")
                throw PbmParseError.ioError
            }
        } else {
            if isspace(c) == 0 {
                nonWhitespaceFound = true

                /* Have to put the non-whitespace character back in
                   the stream -- it's part of the next image.
                */
                let rc = ungetc(c, file)
                if rc == EOF {
                    print("File error doing ungetc() to position to image.")
                    throw PbmParseError.ioError
                }
            }
        }
    }
    return eof
}

func _pbm_readpbmrow(_ file: UnsafeMutablePointer<FILE>, cols: Int32, format: Int32) throws -> [Bit] {
    var bitRow: [Bit] = []
    var bitshift = 0
    switch format {
    case PBM_FORMAT:
        for _ in 0..<cols {
            bitRow.append(try _getbit(file))
        }
    case RPBM_FORMAT:
        var item: CUnsignedChar = 0
        bitshift = -1  /* item's value is meaningless here */
        for _ in 0..<cols {
            if bitshift == -1 {
                let byte = _getrawbyte(file)
                guard byte != EOF else {
                    if feof(file) != 0 {
                        throw PbmParseError.unexpectedEndOfFile
                    } else if ferror(file) != 0 {
                        throw PbmParseError.ioError
                    } else {
                        throw PbmParseError.internalInconsistency
                    }
                }
                item = CUnsignedChar(byte)
                bitshift = 7
            }
            bitRow.append((item >> bitshift) & 1 != 0 ? .one : .zero)
            bitshift -= 1
        }
    default:
        throw PbmParseError.internalInconsistency
    }
    return bitRow
}

func _getrawbyte(_ file: UnsafeMutablePointer<FILE>) -> Int32 {
    getc(file)
}

// Read a single bit from the file
func _getbit(_ file: UnsafeMutablePointer<FILE>) throws -> Bit {
    var ch: Int32 = 0

    repeat {
        ch = _pm_getc(file)
        guard ch != EOF else {
            throw PbmParseError.unexpectedEndOfFile
        }
    } while ch == Character(" ").asciiValue! || ch == Character("\t").asciiValue! || ch == Character("\n").asciiValue! || ch == Character("\r").asciiValue!

    switch ch {
    case Int32(Character("0").asciiValue!): return .zero
    case Int32(Character("1").asciiValue!): return .one
    default: throw PbmParseError.junkWhereBitsShouldBe
    }
}

// Get the next character from the file, skipping comments
func _pm_getc(_ file: UnsafeMutablePointer<FILE>) -> Int32 {
    var char = getc(file)
    guard char != EOF else { return char }
    if char == Character("#").asciiValue! {
        repeat {
            char = getc(file)
            guard char != EOF else { return char }
        } while char != Character("\n").asciiValue! && char != Character("\r").asciiValue!
    }
    return char
}

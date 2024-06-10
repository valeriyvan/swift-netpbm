import Foundation

public struct PBM {

    enum PbmParseError: Error {
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

    // All functions returning pixels follow C ordering for pixels, row by row

    // Parse the first image from the file
    public static func firstImage(filename: String) throws -> (cols: Int, rows: Int, pixels: [UInt8]) {
        guard let file: UnsafeMutablePointer<FILE> = fopen(filename, "r") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        let image = try PBM.image(file: file)
        guard fclose(file) != EOF else {
            throw PBM.PbmParseError.ioError
        }
        return image
    }

    // Parse the first image from a string
    public static func firstImage(string: String) throws -> (cols: Int, rows: Int, pixels: [UInt8]) {
        try string.withCString {
            guard let file: UnsafeMutablePointer<FILE> = fmemopen(UnsafeMutableRawPointer(mutating: $0), strlen($0), "r") else {
                throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
            }
            let image = try PBM.image(file: file)
            guard fclose(file) != EOF else {
                throw PBM.PbmParseError.ioError
            }
            return image
        }
    }

    // Parse all images from the file
    public static func images(filename: String) throws -> [(cols: Int, rows: Int, pixels: [UInt8])] {
        guard let file: UnsafeMutablePointer<FILE> = fopen(filename, "r") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        let images = try PBM.images(file: file)
        guard fclose(file) != EOF else {
            throw PBM.PbmParseError.ioError
        }
        return images
    }

    // Parse all images from a string
    public static func images(string: String) throws -> [(cols: Int, rows: Int, pixels: [UInt8])] {
        try string.withCString {
            guard let file: UnsafeMutablePointer<FILE> = fmemopen(UnsafeMutableRawPointer(mutating: $0), strlen($0), "r") else {
                throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
            }
            let images = try PBM.images(file: file)
            guard fclose(file) != EOF else {
                throw PBM.PbmParseError.ioError
            }
            return images
        }
    }

    // Helper function to parse all images from a file pointer
    private static func images(file: UnsafeMutablePointer<FILE>) throws -> [(cols: Int, rows: Int, pixels: [UInt8])] {
        var images: [(cols: Int, rows: Int, pixels: [UInt8])] = []
        while true {
            let eof = try _pm_nextimage(file)
            guard !eof else { break }
            let image = try PBM.image(file: file)
            images.append(image)
        }
        return images
    }

    // Parse a single image from a file pointer
    private static func image(file: UnsafeMutablePointer<FILE>) throws -> (cols: Int, rows: Int, pixels: [UInt8]) {
        let (cols, rows, format) = try _pbm_readpbminit(file) // TODO: test with broken header
        // TODO: test format is as expected
        let capacity = Int(rows * cols)
        let pixels: [UInt8] = try .init(unsafeUninitializedCapacity: capacity) { buffer, initializedCount in
            for row in 0..<Int(rows) {
                let bits = try _pbm_readpbmrow(file, cols: cols, format: format)
                for col in 0..<Int(cols) { // TODO: do it without loop
                    buffer[row * Int(cols) + Int(col)] = UInt8(bits[col].rawValue)
                }
            }
            initializedCount = capacity
        }
        return (cols: Int(cols), rows: Int(rows), pixels: pixels)
    }

    // Move to the next image in the file stream
    // TODO: reverse return value
    fileprivate static func _pm_nextimage(_ file: UnsafeMutablePointer<FILE>) throws -> Bool {
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
                    throw PBM.PbmParseError.ioError
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
                        throw PBM.PbmParseError.ioError
                    }
                }
            }
        }
        return eof
    }

    // Get the next character from the file, skipping comments
    private static func _pm_getc(_ file: UnsafeMutablePointer<FILE>) -> Int32 {
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

    // Read a single bit from the file
    private static func _getbit(_ file: UnsafeMutablePointer<FILE>) throws -> Bit {
        var ch: Int32 = 0

        repeat {
            ch = PBM._pm_getc(file)
            guard ch != EOF else {
                throw PBM.PbmParseError.unexpectedEndOfFile
            }
        } while ch == Character(" ").asciiValue! || ch == Character("\t").asciiValue! || ch == Character("\n").asciiValue! || ch == Character("\r").asciiValue!

        switch ch {
        case Int32(Character("0").asciiValue!): return .zero
        case Int32(Character("1").asciiValue!): return .one
        default: throw PBM.PbmParseError.junkWhereBitsShouldBe
        }
    }

    // Read a row of bits from the file
    fileprivate static func _pbm_readpbmrow(_ file: UnsafeMutablePointer<FILE>, cols: Int32, format: Int32) throws -> [Bit] {
        var bitRow: [Bit] = []
        var bitshift = 0
        switch format {
        case PBM_FORMAT:
            for _ in 0..<cols {
                bitRow.append(try _getbit(file))
            }
        case RPBM_FORMAT:
            var item: CUnsignedChar = 0
            bitshift = -1 /* item's value is meaningless here */
            for _ in 0..<cols {
                if bitshift == -1 {
                    let byte = _getrawbyte(file)
                    guard byte != EOF else {
                        if feof(file) != 0 {
                            throw PBM.PbmParseError.unexpectedEndOfFile
                        } else if ferror(file) != 0 {
                            throw PBM.PbmParseError.ioError
                        } else {
                            throw PBM.PbmParseError.internalInconsistency
                        }
                    }
                    item = CUnsignedChar(_getrawbyte(file)) // TODO: overflow???
                    bitshift = 7
                }
                bitRow.append((item >> bitshift) & 1 == 1 ? .one : .zero)
                bitshift -= 1
              }
        default:
            throw PBM.PbmParseError.internalInconsistency
        }
        return bitRow
    }

    // Initialize PBM reading, checking the format
    fileprivate static func _pbm_readpbminit(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32, format: Int32) {
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
            throw PBM.PbmParseError.wrongFormat
        case PPM_TYPE:
                print("""
                    The input file is a PPM, not a PBM.  You may want to \
                    convert it to PBM with 'ppmtopgm', 'pamditherbw', and \
                    'pamtopnm'
                    """
                )
                throw PBM.PbmParseError.wrongFormat
        case PAM_TYPE:
                print("""
                    The input file is a PAM, not a PBM.  \
                    If it is a black and white image, you can convert it \
                    to PBM with 'pamtopnm'
                    """
                )
                throw PBM.PbmParseError.wrongFormat
        default:
            print("bad magic number \(String(format: "0x%x", realFormat)) - not a PPM, PGM, PBM, or PAM file")
            throw PBM.PbmParseError.wrongFormat
        }
        try _pbm_validateComputableSize(cols: cols, rows: rows)
        return (cols: cols, rows: rows, format: realFormat)
    }

    // TODO: get rid of temporary file
    public static func write(images: [(cols: Int, rows: Int, pixels: [UInt8])], forcePlane: Bool) throws -> String {
        guard let tmpUrl = createTemporaryFile() else {
            throw PBM.PbmParseError.ioError
        }
        try write(images: images, filename: tmpUrl.path, forcePlane: true)
        let string = try String(contentsOf: tmpUrl)
        try FileManager.default.removeItem(at: tmpUrl)
        return string
    }

    public static func write(images: [(cols: Int, rows: Int, pixels: [UInt8])], filename: String, forcePlane: Bool) throws {
        guard let file: UnsafeMutablePointer<FILE> = fopen(filename, "w") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        try PBM.write(images: images, file: file, forcePlane: forcePlane)
        guard fclose(file) != EOF else {
            throw PBM.PbmParseError.ioError
        }
    }

    private static func write(images: [(cols: Int, rows: Int, pixels: [UInt8])], file: UnsafeMutablePointer<FILE>, forcePlane: Bool) throws {
        let imagesCount = images.count
        for (i, image) in images.enumerated() {
            try _pbm_writepbm(
                file,
                bits: image.pixels.map { Bit(rawValue: Int($0))! },
                cols: Int32(image.cols), rows: Int32(image.rows),
                forcePlain: forcePlane
            )
            if i < imagesCount - 1 {
                guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
                    throw PBM.PbmParseError.ioError
                }
            }
        }
    }

    private static func _pbm_writepbm(_ file: UnsafeMutablePointer<FILE>, bits: [Bit], cols: Int32, rows: Int32, forcePlain: Bool) throws {
        try _pbm_writepbminit(file, cols: cols, rows: rows, forcePlain: forcePlain)
        if forcePlain {
            try _writePbmBitsPlain(file, bits: bits, cols: cols, rows: rows)
        } else {
            fatalError("Not implemented")
        }
    }

    private static func _pbm_writepbminit(_ file: UnsafeMutablePointer<FILE>, cols: Int32, rows: Int32, forcePlain: Bool) throws {
        /* For Caller's convenience, we include validating computability of the
           image dimensions, since Caller may be using them in arithmetic after
           our return.
        */
        try _pbm_validateComputableSize(cols: cols, rows: rows)
        let magic = String(format: "%c%c\n%d %d\n", PBM_MAGIC1, forcePlain ? PBM_MAGIC2 : RPBM_MAGIC2, cols, rows)
        guard magic.withCString({ fputs($0, file) }) != EOF else {
            throw PBM.PbmParseError.ioError
        }
    }

    private static func _writePbmBitsPlain(_ file: UnsafeMutablePointer<FILE>, bits: [Bit], cols: Int32, rows: Int32) throws {
        precondition(bits.count == cols * rows)
        for row in 0..<rows {
            var charCount = 0
            for col in 0..<cols {
                let bit = bits[Int(row * cols + col)]
                guard putc(Int32(Character(bit == .zero ? "0" : "1").asciiValue!), file) != EOF else {
                    throw PBM.PbmParseError.ioError
                }
                charCount += 1
                if charCount >= 70 && col < cols - 1 {
                    guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
                        throw PBM.PbmParseError.ioError
                    }
                    charCount = 0
                }
            }
            guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
                throw PBM.PbmParseError.ioError
            }
        }
    }

    // Read the rest of the initialization data (width and height)
    private static func _pbm_readpbminitrest(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32) {
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
            throw PBM.PbmParseError.wrongFormat
        }
        if rows > UInt32.max / 2 { // INT_MAX
            print("Number of rows in header is too large (\(rows)). The maximum allowed by the format is \(UInt32.max / 2).")
            throw PBM.PbmParseError.wrongFormat
        }
        return (cols: Int32(cols), rows: Int32(rows))
    }

    // Get an unsigned integer from the file
    private static func _pm_getuint(_ file: UnsafeMutablePointer<FILE>) throws -> UInt32 {
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
            ch = PBM._pm_getc(file)
        } while ch == Character(" ").asciiValue! || ch == Character("\t").asciiValue! || ch == Character("\n").asciiValue! || ch == Character("\r").asciiValue!

        if ch < Character("0").asciiValue! || ch > Character("9").asciiValue! {
            print("junk in file where an unsigned integer should be")
            throw PBM.PbmParseError.junkWhereUnsignedIntegerShouldBe // TODO: caller should throw exact error
        }

        var i: Int32 = 0
        repeat {
            let digitVal = ch - Int32(Character("0").asciiValue!)

            if i > Int32.max / 10 {
                print("ASCII decimal integer in file is too large to be processed.")
                throw PBM.PbmParseError.tooBigNumber // TODO: caller should throw exact error
            }

            i *= 10

            if i > Int32.max - digitVal {
                print("ASCII decimal integer in file is too large to be processed.")
                throw PBM.PbmParseError.tooBigNumber // TODO: caller should throw exact error
            }

            i += digitVal

            ch = PBM._pm_getc(file)
        } while ch >= Character("0").asciiValue! && ch <= Character("9").asciiValue!

        return UInt32(i)
    }

    private static func _pbm_validateComputableSize(cols: Int32, rows: Int32) throws {
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
            throw PBM.PbmParseError.imageTooLarge
        }
        if rows > Int32.max - 10 {
            print("image height \(rows) too large to be processed", rows)
            throw PBM.PbmParseError.imageTooLarge
        }
    }

    // Read the magic number indicating file format
    private static func _pm_readmagicnumber(_ file: UnsafeMutablePointer<FILE>) throws -> Int32 {
        let firstChar = getc(file)
        guard firstChar != EOF else {
            print("""
                Error reading first byte of what is expected to be \
                a Netpbm magic number.
                Most often, this means your input file is empty.
                """
            )
            throw PBM.PbmParseError.wrongFormat
        }
        let secondChar = getc(file)
        guard secondChar != EOF else {
            print("""
                Error reading second byte of what is expected to be \
                a Netpbm magic number (the first byte was successfully \
                read as 0x%02x).
                """
            )
            throw PBM.PbmParseError.wrongFormat
        }
        return firstChar * 256 + secondChar
    }

    private static func _getrawbyte(_ file: UnsafeMutablePointer<FILE>) -> Int32 {
        getc(file)
    }

    // Leaves file open ready to read next image from the same file
    //private static func image(file: UnsafeMutablePointer<FILE>) throws -> (rows: Int, cols: Int, pixels: [UInt8]) {
    //    var cols: Int32 = 0
    //    var rows: Int32 = 0
    //    guard let bits: UnsafeMutablePointer<UnsafeMutablePointer<bit>?> = pbm_readpbm(file, &cols, &rows) else {
    //        throw PbmParseError.ioError
    //    }
    //    let capacity = Int(rows * cols)
    //    let pixels: [UInt8] = try .init(unsafeUninitializedCapacity: capacity) { buffer, initializedCount in
    //        for row in 0..<Int(rows) {
    //            for col in 0..<Int(cols) {
    //                guard let aRow = bits[row] else {
    //                    throw PbmParseError.internalInconsistency
    //                }
    //                buffer[row * Int(cols) + Int(col)] = aRow[col]
    //            }
    //        }
    //        initializedCount = capacity
    //    }
    //    _pbm_freearray(bits, rows)
    //    return (rows: Int(rows), cols: Int(cols), pixels: pixels)
    //}

}

//private func _pbm_freearray(_ bits: UnsafeMutablePointer<UnsafeMutablePointer<bit>?>, _ rows: Int32) {
//    pm_freearray(UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>(bitPattern: UInt(bitPattern: bits)), rows)
//}

func createTemporaryFile() -> URL? {
    let fileManager = FileManager.default
    let tempDirectoryURL = fileManager.temporaryDirectory
    let tempFileURL = tempDirectoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")

    if fileManager.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil) {
        return tempFileURL
    } else {
        return nil
    }
}

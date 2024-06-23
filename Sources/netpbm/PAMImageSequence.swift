import Foundation

public struct PAMImageSequence: ImageAsyncSequence {
    public typealias Element = PAMImageElementSequence
    public typealias AsyncIterator = PAMImageAsyncIterator

    public var file: UnsafeMutablePointer<FILE> { fileWrapper.file }
    public var fileWrapper: FileWrapper

    public init(fileWrapper: FileWrapper) throws {
        self.fileWrapper = fileWrapper
    }

    public func makeAsyncIterator() -> PAMImageAsyncIterator {
        return PAMImageAsyncIterator(file: file)
    }
}

public struct PAMImageAsyncIterator: ImageAsyncIteratorProtocol {
    public typealias Element = PAMImageElementSequence

    public var file: UnsafeMutablePointer<FILE>

    public init(file: UnsafeMutablePointer<FILE>) {
        self.file = file
    }

    public mutating func next() async throws -> PAMImageElementSequence? {
        let eof = try _pm_nextimage(file)
        guard !eof else { return nil }
        return try PAMImageElementSequence(file: file)
    }
}

public struct PAMImageElementSequence: ImageElementAsyncSequence {
    public typealias Element = [Sample]
    public typealias AsyncIterator = PAMImageElementAsyncIterator

    public var pam: Pam

    public var width: Int { Int(pam.width) }
    public var height: Int { Int(pam.height) }
    public var file: UnsafeMutablePointer<FILE> { pam.file }
    public var cols: Int32 { pam.width }
    public var rows: Int32 { pam.height }
    public var format: Int32 { pam.format }

    public init(file: UnsafeMutablePointer<FILE>) throws {
        self.pam = try _pnm_readpaminit(file)
    }

    public func makeAsyncIterator() -> PAMImageElementAsyncIterator {
        PAMImageElementAsyncIterator(pam: pam)
    }
}

public struct PAMImageElementAsyncIterator: ImageElementAsyncIteratorProtocol {
    public typealias Element = [Sample]

    public var row: [[Sample]] = []
    public var pam: Pam
    public var currentRow: Int = -1
    public var currentElementIndex: Int = 0
    public var cols: Int32 { pam.width }
    public var rows: Int32 { pam.height }
    public var format: Int32 { pam.format }
    public var file: UnsafeMutablePointer<FILE> { pam.file }

    init(pam: Pam) {
        self.pam = pam
    }

    public mutating func readRow() throws -> [[Sample]] {
        try _pnm_readpamrow(pam: pam)
    }
}

func _pnm_readpaminit(_ file: UnsafeMutablePointer<FILE>) throws -> Pam {
    var pam = Pam()
    pam.size = UInt32(MemoryLayout<Pam>.size)
    pam.file = file
    pam.len = min(pam.size, UInt32(MemoryLayout<Pam>.size))

    //if (size >= PAM_STRUCT_SIZE(allocation_depth))
    //    pamP->allocation_depth = 0;

    /* Get magic number. */
    pam.format = try _pm_readmagicnumber(file)

    switch PAM_FORMAT_TYPE(pam.format) {
    case PAM_TYPE:
        try _readpaminitrest(pam: &pam)
    case PPM_TYPE:
        var maxval: Pixval
        (pam.width, pam.height, maxval) = try _ppm_readppminitrest(pam.file)
        pam.maxVal = Sample(maxval)
        pam.depth = 3
        pam.tuple_type = PAM_PPM_TUPLETYPE
        pam.comment = ""
    case PGM_TYPE:
        var maxval: Gray
        (pam.width, pam.height, maxval) = try _pgm_readpgminitrest(pam.file)
        pam.maxVal = Sample(maxval)
        pam.depth = 1
        pam.tuple_type = PAM_PGM_TUPLETYPE
        pam.comment = ""
    case PBM_TYPE:
        (pam.width, pam.height) = try _pbm_readpbminitrest(pam.file)
        pam.maxVal = Sample(1)
        pam.depth = 1
        pam.tuple_type = PAM_PBM_TUPLETYPE
        pam.comment = ""
    default:
        print("bad magic number \(String(format: "0x%x", pam.format)) - not a PAM, PPM, PGM, or PBM file")
        throw ParseError.wrongFormat
    }

    pam.bytes_per_sample = _pnm_bytespersample(maxval: pam.maxVal)
    pam.plainformat = false
        /* See below for complex explanation of why this is FALSE. */

    try _setSeekableAndRasterPos(&pam)

    try _interpretTupleType(&pam)

    try _validateComputableSize(&pam)

    try _validateComputableMaxval(pam)

    return pam
}

func _pnm_bytespersample(maxval: Sample) -> UInt32 {
/*----------------------------------------------------------------------------
   Return the number of bytes per sample in the PAM raster of a PAM image
   with maxval 'maxval'.  It's defined to be the minimum number of bytes
   needed for that maxval, i.e. 1 for maxval < 256, 2 otherwise.
-----------------------------------------------------------------------------*/

    /* The PAM format requires maxval to be greater than zero and less than
       1<<16, but since that is a largely arbitrary restriction, we don't want
       to rely on it.
    */

    var a: Sample = 0
    for i in 0...UInt32(MemoryLayout.size(ofValue: maxval)) {
        guard a != 0 else { return i }
        a >>= 8
    }
    return 0  /* silence compiler warning */
}

func _setSeekableAndRasterPos(_ pam: inout Pam) throws {
    pam.is_seekable = _pm_is_seekable(pam.file)
    if pam.is_seekable {
        pam.raster_pos = try _pm_tell2(pam.file)
    }
}

func _pm_is_seekable(_ file: UnsafeMutablePointer<FILE>) -> Bool {
    return _isSeekable(file)
}

func _isSeekable(_ file: UnsafeMutablePointer<FILE>) -> Bool {
/*----------------------------------------------------------------------------
   The file is seekable -- we can set its read/write position to anything we
   want.

   If we can't tell if it is seekable, we return false.
-----------------------------------------------------------------------------*/

    /* I would use fseek() to determine if the file is seekable and
       be a little more general than checking the type of file, but I
       don't have reliable information on how to do that.  I have seen
       streams be partially seekable -- you can, for example seek to
       0 if the file is positioned at 0 but you can't actually back up
       to 0.  I have seen documentation that says the errno for an
       unseekable stream is EBADF and in practice seen ESPIPE.

       On the other hand, regular files are always seekable and even if
       some other file is, it doesn't hurt much to assume it isn't.
    */
    var statbuf = stat()
    return fstat(fileno(file), &statbuf) == 0 && (statbuf.st_mode & S_IFMT) == S_IFREG
}

func _pm_tell2(_ file: UnsafeMutablePointer<FILE>) throws -> _pm_filepos {
/*----------------------------------------------------------------------------
   Return the current file position as *filePosP, which is a buffer
   'fileposSize' bytes long.  Abort the program if error, including if
   *fileP isn't a file that has a position.
-----------------------------------------------------------------------------*/
    /* Note: FTELLO() is either ftello() or ftell(), depending on the
       capabilities of the underlying C library.  It is defined in
       pm_config.h.  ftello(), in turn, may be either ftell() or
       ftello64(), as implemented by the C library.
    */
    let filepos = FTELLO(file)
    guard filepos >= 0 else {
        print("ftello() to get current file position failed. Errno = \(String(cString: strerror(errno))) (errno)")
        throw ParseError.ioError
    }
    return filepos
}

typealias _pm_filepos = Int64

func FTELLO(_ file: UnsafeMutablePointer<FILE>) -> _pm_filepos {
    ftello(file)
}

func _interpretTupleType(_ pam: inout Pam) throws {
    /*----------------------------------------------------------------------------
     Fill in redundant convenience fields in *pamP with information the
     pamP->tuple_type value implies:

     visual
     colorDepth
     haveOpacity
     opacityPlane

     Validate the tuple type against the depth and maxval as well.
     -----------------------------------------------------------------------------*/
    var visual: Bool = false
    var colorDepth: UInt32 = 0
    var haveOpacity: Bool = false
    var opacityPlane: UInt32 = 0

    assert(pam.depth > 0)

    switch PAM_FORMAT_TYPE(pam.format) {
        case PAM_TYPE:
            switch pam.tuple_type.uppercased() {
                case "BLACKANDWHITE":
                    visual = true
                    colorDepth = 1
                    haveOpacity = false
                    guard pam.maxVal == 1 else {
                        print("maxval \(pam.maxVal) is not consistent with tuple type BLACKANDWHITE (should be 1)")
                        throw ParseError.wrongFormat
                    }
                case "GRAYSCALE":
                    visual = true
                    colorDepth = 1
                    haveOpacity = false
                case "GRAYSCALE_ALPHA":
                    visual = true
                    colorDepth = 1
                    haveOpacity = true
                    opacityPlane = PAM_GRAY_TRN_PLANE
                    try _validateMinDepth(pam, minDepth: 2)
                case "RGB":
                    visual = true
                    colorDepth = 3
                    haveOpacity = false
                    try _validateMinDepth(pam, minDepth: 3)
                case "RGB_ALPHA":
                    visual = true
                    colorDepth = 3
                    haveOpacity = true
                    opacityPlane = PAM_TRN_PLANE
                    try _validateMinDepth(pam, minDepth: 4)
                default:
                    visual = false
            }
        case PPM_TYPE:
            visual = true
            colorDepth = 3
            haveOpacity = false
            assert(pam.depth == 3) // TODO: !!!
        case PGM_TYPE:
            visual = true
            colorDepth = 1
            haveOpacity = false
        case PBM_TYPE:
            visual = true
            colorDepth = 1
            haveOpacity = false
        default:
            assert(false) // TODO: !!!
    }
    pam.visual = visual
    pam.color_depth = colorDepth
    pam.have_opacity = haveOpacity
    pam.opacity_plane = opacityPlane
}

func _validateComputableSize(_ pam: inout Pam) throws {
/*----------------------------------------------------------------------------
   Validate that the dimensions of the image are such that it can be
   processed in typical ways on this machine without worrying about
   overflows.  Note that in C, arithmetic is always modulus arithmetic,
   so if your values are too big, the result is not what you expect.
   That failed expectation can be disastrous if you use it to allocate
   memory.

   It is very normal to allocate space for a tuplerow, so we make sure
   the size of a tuple row, in bytes, can be represented by an 'int'.

   Another common operation is adding 1 or 2 to the highest row, column,
   or plane number in the image, so we make sure that's possible.  And in
   bitmap images, rounding up to multiple of 8 is common, so we provide for
   that too.

   Note that it's still the programmer's responsibility to ensure that his
   code, using values known to have been validated here, cannot overflow.
-----------------------------------------------------------------------------*/
    guard pam.width > 0 else {
        print("Width is zero. Image must be at least one pixel wide.")
        throw ParseError.wrongFormat
    }
    guard pam.height > 0 else {
        print("Height is zero. Image must be at least one pixel high.")
        throw ParseError.wrongFormat
    }
    let depth = try _allocationDepth(pam: pam)
    guard depth <= Int32.max / Int32(MemoryLayout<Sample>.size) else {
        print("Image depth \(depth) too large to be processed")
        throw ParseError.wrongFormat
    }
    guard Int32(depth) * Int32(MemoryLayout<Sample>.size) <= Int32.max / pam.width else {
        print("Image width and depth (\(pam.width), \(depth)) too large to be processed.")
        throw ParseError.wrongFormat
    }
// TODO: !!!
//    guard pam.width * depth * Int32(MemoryLayout<Sample>.size) <=
//        Int32.max - depth * Int32(MemoryLayout<Tuple>.size) else {
//        print("Image width and depth (\(pam.width), \(depth)) too large to be processed.")
//        throw ParseError.wrongFormat
//    }
    guard depth <= Int32.max - 2 else {
        print("Image depth (\(depth)) too large to be processed.")
        throw ParseError.wrongFormat
    }
    guard pam.width <= Int32.max - 10 else {
        print("Image width (\(pam.width)) too large to be processed.")
        throw ParseError.wrongFormat
    }
    guard pam.height <= Int32.max - 10 else {
        print("image height (\(pam.height) too large to be processed.")
        throw ParseError.wrongFormat
    }
}

func _validateComputableMaxval(_ pam: Pam) throws {
/*----------------------------------------------------------------------------
  This is similar to validateComputableSize, but for the maxval.
-----------------------------------------------------------------------------*/
    try _pgm_validateComputableMaxval(maxVal: Gray(pam.maxVal));
}

func _validateMinDepth(_ pam: Pam, minDepth: UInt32) throws {
    guard pam.depth >= minDepth else {
        print("Depth \(pam.depth) is insufficient for tuple type '\(pam.tuple_type)'. Minimum depth is \(minDepth).")
        throw ParseError.wrongFormat
    }
}

func _allocationDepth(pam: Pam) throws -> UInt32 {
    guard pam.allocation_depth != 0 else {
        return pam.depth
    }
    guard pam.depth <= pam.allocation_depth else {
        print("'allocationDepth' (\(pam.allocation_depth) is smaller than 'depth' (\(pam.depth)")
        throw ParseError.wrongFormat
    }
    return pam.allocation_depth
}

func _pnm_readpamrow(pam: Pam) throws -> [[Sample]] {
/*----------------------------------------------------------------------------
   Read a row from the Netpbm image file into tuplerow[], at the
   current file position.  If 'tuplerow' is NULL, advance the file
   pointer to the next row, but don't return the contents of the
   current one.

   We assume the file is positioned to the beginning of a row of the
   image's raster.
-----------------------------------------------------------------------------*/
    /* For speed, we don't check any of the inputs for consistency
       here (unless it's necessary to avoid crashing).  Any consistency
       checking should have been done by a prior call to
       pnm_readpaminit().
    */

    /* Need a special case for raw PBM because it has multiple tuples (8)
       packed into one byte.
    */
    switch (pam.format) {
    case PAM_FORMAT, RPPM_FORMAT, RPGM_FORMAT:
        return try _readRawNonPbmRow(pam: pam)
    case PPM_FORMAT, PGM_FORMAT:
        return try _readPlainNonPbmRow(pam: pam)
    case RPBM_FORMAT, PBM_FORMAT:
        return try _readPbmRow(pam: pam)
    default:
        print("Invalid 'format' member in PAM structure: \(pam.format)")
        throw ParseError.wrongFormat
    }
}

func _readRawNonPbmRow(pam: Pam) throws -> [[Sample]] {

    let rowImageSize = Int(pam.width) * Int(pam.bytes_per_sample) * Int(pam.depth)

    let inbuf = _pnm_allocrowimage(pam: pam)
    defer { inbuf.deallocate() }

    let bytesRead = fread(inbuf.baseAddress!, 1, rowImageSize, pam.file)

    guard bytesRead == rowImageSize else {
        if feof(pam.file) != 0 {
            print("End of file encountered when trying to read a row from input file.")
            throw ParseError.unexpectedEndOfFile
        } else {
            print("Error reading a row from input file. fread() fails with errno=\(errno) (\(String(cString: strerror(errno)))")
            throw ParseError.unexpectedEndOfFile
        }
    }
    let tuplerow: [[Sample]] =
    switch pam.bytes_per_sample {
    case 1: _parse1BpsRow(pam: pam, inbuf: inbuf)
    case 2: _parse2BpsRow(pam: pam, inbuf: inbuf)
    case 3: _parse3BpsRow(pam: pam, inbuf: inbuf)
    case 4: _parse4BpsRow(pam: pam, inbuf: inbuf)
    default:
        print("Invalid bytes per sample passed to pnm_formatpamrow(): \(pam.bytes_per_sample)")
        throw ParseError.internalInconsistency
    }
    try _validatePamRow(pam: pam, tuplerow: tuplerow)

    return tuplerow
}

func _pnm_allocrowimage(pam: Pam) -> UnsafeMutableRawBufferPointer {
    let rowsize = _rowimagesize(pam: pam)
    let overrunSpaceNeeded = 8
        /* This is the number of extra bytes of space libnetpbm needs to have
           at the end of the buffer so it can use fast, lazy algorithms.
        */
    let size = rowsize + overrunSpaceNeeded
    return UnsafeMutableRawBufferPointer.allocate(byteCount: size, alignment: MemoryLayout<CChar>.alignment)
}

func _rowimagesize(pam: Pam) -> Int {
    /* If repeatedly calculating this turns out to be a significant
       performance problem, we could keep this in struct pam like
       bytes_per_sample.
    */
    PAM_FORMAT_TYPE(pam.format) == PBM_TYPE ? _pbm_packed_bytes(Int(pam.width)) : Int(pam.width) * Int(pam.bytes_per_sample) * Int(pam.depth)
}

func _pbm_packed_bytes(_ cols: Int) -> Int {
    (cols + 7) / 8
}

func _parse1BpsRow(pam: Pam, inbuf: UnsafeMutableRawBufferPointer) -> [[Sample]] {
    var row: [[Sample]] = []
    var bufferCursor = 0  /* initial value */
    for _ in 0..<pam.width {
        var pixel: [Sample] = []
        for _ in 0..<pam.depth {
            pixel.append(Sample(inbuf[bufferCursor]))
            bufferCursor += 1
        }
        row.append(pixel)
    }
    return row
}

// TODO: test this carefully
func _parse2BpsRow(pam: Pam, inbuf: UnsafeMutableRawBufferPointer) -> [[Sample]] {
    var row: [[Sample]] = []
    var bufferCursor = 0  /* initial value */
    for _ in 0..<pam.width {
        var pixel: [Sample] = []
        for _ in 0..<pam.depth {
            pixel.append(_bytes2ToSample(buf: inbuf[bufferCursor ..< bufferCursor + 2]))
            bufferCursor += 2
        }
        row.append(pixel)
    }
    return row
}

func _parse3BpsRow(pam: Pam, inbuf: UnsafeMutableRawBufferPointer) -> [[Sample]] {
    var row: [[Sample]] = []
    var bufferCursor = 0  /* initial value */
    for _ in 0..<pam.width {
        var pixel: [Sample] = []
        for _ in 0..<pam.depth {
            pixel.append(_bytes3ToSample(buf: inbuf[bufferCursor ..< bufferCursor + 3]))
            bufferCursor += 3
        }
        row.append(pixel)
    }
    return row
}

func _parse4BpsRow(pam: Pam, inbuf: UnsafeMutableRawBufferPointer) -> [[Sample]] {
    var row: [[Sample]] = []
    var bufferCursor = 0  /* initial value */
    for _ in 0..<pam.width {
        var pixel: [Sample] = []
        for _ in 0..<pam.depth {
            pixel.append(_bytes3ToSample(buf: inbuf[bufferCursor ..< bufferCursor + 4]))
            bufferCursor += 4
        }
        row.append(pixel)
    }
    return row
}

func _bytes2ToSample(buf: Slice<UnsafeMutableRawBufferPointer>) -> Sample {
    Sample(buf[buf.startIndex] << 8) | Sample(buf[buf.startIndex + 1])
}

func _bytes3ToSample(buf: Slice<UnsafeMutableRawBufferPointer>) -> Sample {
    Sample(buf[buf.startIndex] << 16) | Sample(buf[buf.startIndex + 1] << 8) | Sample(buf[buf.startIndex + 2])
}

func _bytes4ToSample(buf: Slice<UnsafeMutableRawBufferPointer>) -> Sample {
    Sample(buf[buf.startIndex] << 24) | Sample(buf[buf.startIndex + 1] << 16) | Sample(buf[buf.startIndex + 2] << 8) | Sample(buf[buf.startIndex + 3])
}

func _validatePamRow(pam: Pam, tuplerow: [[Sample]]) throws {
    /*----------------------------------------------------------------------------
     Check for sample values above maxval in input.

     Note: a program that wants to deal with invalid sample values itself can
     simply make sure it sets pamP->maxval sufficiently high, so this validation
     never fails.
     -----------------------------------------------------------------------------*/
    /* To save time, skip the test for if the maxval is a saturated value
     (255, 65535) or format is PBM.

     This is an expensive test, but is skipped in most cases: in practice
     maxvals other than 255 or 65535 are uncommon.  Thus we do this in a
     separate pass through the row rather than while reading in the row.
     */

    if pam.maxVal == (1 << pam.bytes_per_sample * 8) - 1 ||
        PAM_FORMAT_TYPE(pam.format) == PBM_FORMAT {
        /* There's no way a sample can be invalid, so we don't need to
         look at the samples individually.
         */
    } else {
        for col in 0..<Int(pam.width) {
            for plane in 0..<Int(pam.depth) {
                let sample = tuplerow[col][plane]
                if sample > pam.maxVal {
                    print("Plane \(plane) sample value \(sample) exceeds the image maxval of \(pam.maxVal)")
                    throw ParseError.badPixelValue
                }
            }
        }
    }
    return
}

func _readPlainNonPbmRow(pam: Pam) throws -> [[Sample]] {
    var tuplerow: [[Sample]] = []
    for _ in 0..<Int(pam.width) {
        var pixel: [Sample] = []
        for plane in 0..<Int(pam.depth) {
            let sample = Sample(try _pm_getuint(pam.file))
            guard sample <= pam.maxVal else {
                print("Plane \(plane) sample value \(sample) exceeds the image maxval of \(pam.maxVal)")
                throw ParseError.badPixelValue
            }
            pixel.append(sample)
        }
        tuplerow.append(pixel)
    }
    return tuplerow
}

func _readPbmRow(pam: Pam) throws -> [[Sample]] {
    guard pam.depth == 1 else {
        print("Invalid pam structure passed to readPbmRow(). It says PBM format, but 'depth' member is not 1.")
        throw ParseError.internalInconsistency
    }
    let bitrow = try _pbm_readpbmrow_packed(pam.file, cols: pam.width, format: pam.format)
    var tuplerow: [[Sample]] = []
    for col in 0..<Int(pam.width) {
        let byte: UInt8 = bitrow[col / 8]
        let shift: Int = 7 - col % 8
        let bit: UInt8 = (byte >> shift) & 1
        let sample = Sample(bit == PBM_BLACK ? PAM_PBM_BLACK : PAM_PBM_WHITE)
        tuplerow.append([sample])
    }
    bitrow.deallocate()
    return tuplerow
}

func _pbm_readpbmrow_packed(_ file: UnsafeMutablePointer<FILE>, cols: Int32, format: Int32) throws -> UnsafeMutableRawBufferPointer {
    switch(format) {
    case PBM_FORMAT:
        let byteCount = _pbm_packed_bytes(Int(cols))
        let packedBits = UnsafeMutableRawBufferPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<UInt8>.alignment)
        packedBits.initializeMemory(as: UInt8.self, repeating: 0)
        for col in 0..<Int(cols) {
            let bit = try _getbit(file)
            let shift = (7 - col % 8)
            let mask = UInt8(bit.rawValue) << shift
            packedBits[col / 8] |= mask
        }
        print(NSData(bytes: packedBits.baseAddress!, length: byteCount))
        return packedBits
    case RPBM_FORMAT:
        let byteCount = _pbm_packed_bytes(Int(cols))
        let packedBits = UnsafeMutableRawBufferPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<UInt8>.alignment)
        let bytesReadCt = fread(packedBits.baseAddress!, 1, byteCount, file)
        guard bytesReadCt == byteCount else {
            if feof(file) != 0 {
                if bytesReadCt == 0 {
                    print("Attempt to read a raw PBM image row, but no more rows left in file.")
                } else {
                    print("EOF in the middle of a raw PBM row.")
                }
                throw ParseError.unexpectedEndOfFile
            } else {
                print("I/O error reading raw PBM row.")
                throw ParseError.ioError
            }
        }
        return packedBits
    default:
        print("Internal error in pbm_readpbmrow_packed.")
        throw ParseError.internalInconsistency
    }
}

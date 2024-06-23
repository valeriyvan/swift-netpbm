import Foundation

// TODO: test how original netpbm utilities will digest different formats in one file as well as mix of plane/binary
public struct PAMImageWriter {

    // TODO: [[[Sample]]] parameter takes a lot of memory and differs from other *ImageWriter's.
    // At least one dimensiality should be flatten.
    
    // In case of plane output returned value will be data of String in .ascii encoding
    // (.utf8, obviously, works as well).
    // In case of raw (binary) output, Data returned shouldn't be used for constructing String
    // as encoding cannot be defined.
    public static func write(images: [(pam: Pam, pixels: [[[Sample]]])]) throws -> Data {
        // TODO: assert(images.allSatisfy { image in image.pixels.allSatisfy { $0.r <= image.maxValue && $0.g <= image.maxValue && $0.b <= image.maxValue } })
        guard let tmpUrl = createTemporaryFile() else {
            throw WriteError.ioError
        }
        try write(images: images, pathname: tmpUrl.path)
        let data = try Data(contentsOf: tmpUrl)
        try FileManager.default.removeItem(at: tmpUrl)
        return data
    }

    public static func write(images: [(pam: Pam, pixels: [[[Sample]]])], pathname: String) throws {
        guard let file: UnsafeMutablePointer<FILE> = fopen(pathname, "w") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        try write(images: images, file: file)
        guard fclose(file) != EOF else {
            throw WriteError.ioError
        }
    }

    static func write(images: [(pam: Pam, pixels: [[[Sample]]])], file: UnsafeMutablePointer<FILE>) throws {
        let imagesCount = images.count
        for (i, image) in images.enumerated() {
            var pam = image.pam
            pam.file = file
            try _pnm_writepam(pam: &pam, tuplearray: image.pixels)
            if i < imagesCount - 1 { // TODO: only do this in plane text mode?
                guard putc(Int32(Character("\n").asciiValue!), file) != EOF else {
                    throw WriteError.ioError
                }
            }
        }
    }

}

func _pnm_writepam(pam: inout Pam, tuplearray: [[[Sample]]]) throws {
    assert(pam.height == tuplearray.count)
    try _pnm_writepaminit(pam: &pam)
    for row in 0..<Int(pam.height) {
        try _pnm_writepamrow(pam: pam, tuplerow: tuplearray[row])
    }
}

func _pnm_writepaminit(pam: inout Pam) throws {
    guard pam.size >= pam.len else {
        print("pam object passed to pnm_writepaminit() is smaller " +
              "(\(pam.size) bytes, according to its 'size' element) " +
              "than the amount of data in it " +
              "(\(pam.len) bytes, according to its 'len' element)."
        )
        throw WriteError.badFormat
    }

//    if (pamP->size < PAM_STRUCT_SIZE(bytes_per_sample))
//        pm_error("pam object passed to pnm_writepaminit() is too small.  "
//                 "It must be large "
//                 "enough to hold at least up through the "
//                 "'bytes_per_sample' member, but according "
//                 "to its 'size' member, it is only %u bytes long.",
//                 pamP->size);

//    if (pamP->len < PAM_STRUCT_SIZE(maxval))
//        pm_error("pam object must contain members at least through 'maxval', "
//                 "but according to the 'len' member, it is only %u bytes "
//                 "long.", pamP->len);

    guard pam.maxVal <= PAM_OVERALL_MAXVAL else {
        print("maxval (\(pam.maxVal) passed to pnm_writepaminit() is greater than \(PAM_OVERALL_MAXVAL)")
        throw WriteError.badFormat
    }

//    if (pamP->len < PAM_STRUCT_SIZE(tuple_type)) {
//        tupleType = "";
//        if (pamP->size >= PAM_STRUCT_SIZE(tuple_type))
//            pamP->tuple_type[0] = '\0';
//    } else

    let tupleType = pam.tuple_type

    pam.bytes_per_sample = _pnm_bytespersample(maxval: pam.maxVal)

//    if (pamP->size >= PAM_STRUCT_SIZE(comment_p) &&
//        pamP->len < PAM_STRUCT_SIZE(comment_p))
    pam.comment = ""

//    if (pamP->size >= PAM_STRUCT_SIZE(allocation_depth) &&
//        pamP->len < PAM_STRUCT_SIZE(allocation_depth))
    pam.allocation_depth = 0

    try _interpretTupleType(&pam)

    switch PAM_FORMAT_TYPE(pam.format) {
    case PAM_TYPE:
            try _validateComputableSize(&pam)
            try _validateComputableMaxval(pam)
        /* See explanation below of why we ignore 'pm_plain_output' here. */
        guard "P7\n".withCString({ fputs($0, pam.file) }) != EOF else {
            throw WriteError.ioError
        }
        try _writeComments(pam: pam)
        var str = """
        WIDTH \(pam.width)
        HEIGHT \(pam.height)
        DEPTH \(pam.depth)
        MAXVAL \(pam.maxVal)
        """
        if !_pm_stripeq(tupleType, "") {
            str += "TUPLTYPE \(pam.tuple_type)\n"
        }
        str += "ENDHDR\n"
        guard str.withCString({ fputs($0, pam.file) }) != EOF else {
            throw WriteError.ioError
        }
    case PPM_TYPE:
        /* The depth must be exact, because pnm_writepamrow() is controlled
           by it, without regard to format.
        */
        guard pam.depth == 3 else {
            print("pnm_writepaminit() got PPM format, but depth = \(pam.depth) instead of 3, as required for PPM.")
            throw WriteError.badFormat
        }
        guard pam.maxVal <= PPM_OVERALLMAXVAL else {
            print("pnm_writepaminit() got PPM format, but maxval = \(pam.maxVal), which exceeds the maximum allowed for PPM: \(PPM_OVERALLMAXVAL)")
            throw WriteError.badFormat
        }
        try _ppm_writeppminit(pam.file, cols: pam.width, rows: pam.height, maxVal: Pixval(pam.maxVal), forceplain: pam.plainformat)
    case PGM_TYPE:
        guard pam.depth == 1 else {
            print("pnm_writepaminit() got PGM format, but depth = \(pam.depth) instead of 1, as required for PGM.")
            throw WriteError.badFormat
        }
        guard pam.maxVal <= PGM_OVERALLMAXVAL else {
            print("pnm_writepaminit() got PGM format, but maxval = \(pam.maxVal), which exceeds the maximum allowed for PGM: \(PGM_OVERALLMAXVAL)")
            throw WriteError.badFormat
        }
        try _pgm_writepgminit(pam.file, cols: pam.width, rows: pam.height, maxVal: Gray(pam.maxVal), forceplain: pam.plainformat)
    case PBM_TYPE:
        guard pam.depth == 1 else {
            print("pnm_writepaminit() got PBM format, but depth = \(pam.depth) instead of 1, as required for PBM.")
            throw WriteError.badFormat
        }
        guard pam.maxVal == 1 else {
            print("pnm_writepaminit() got PBM format, but maxval = \(pam.maxVal) instead of 1, as required for PBM.", pam.maxVal)
            throw WriteError.badFormat
        }
        try _pbm_writepbminit(pam.file, cols: pam.width, rows: pam.height, forcePlain: pam.plainformat)

    default:
        print("Invalid format passed to pnm_writepaminit(): \(pam.format)")
        throw WriteError.badFormat
    }

    try _setSeekableAndRasterPos(&pam)

    //pam.len = min(pamP->size, PAM_STRUCT_SIZE(raster_pos))
}

func _pnm_writepamrow(pam: Pam, tuplerow: [[Sample]]) throws {
    /* For speed, we don't check any of the inputs for consistency
       here (unless it's necessary to avoid crashing).  Any consistency
       checking should have been done by a prior call to
       pnm_writepaminit().
    */

    guard pam.format != PAM_FORMAT && pam.plainformat else {
        try _writePamRawRow(pam: pam, tuplerow: tuplerow, count: 1)
        return
    }
    switch PAM_FORMAT_TYPE(pam.format) {
    case PBM_TYPE:
        try _writePamPlainPbmRow(pam: pam, tuplerow: tuplerow)
    case PGM_TYPE, PPM_TYPE:
            try _writePamPlainRow(pam: pam, tuplerow: tuplerow)
    case PAM_TYPE:
        assert(false) // ???
    default:
        print("Invalid 'format' value \(pam.format) in pam structure")
        throw WriteError.badFormat
    }
}

func _writePamPlainPbmRow(pam: Pam, tuplerow: [[Sample]]) throws {
    let samplesPerLine = 70
    for col in 0..<Int(pam.width) {
        let format = (col + 1) % samplesPerLine == 0 || col == pam.width - 1 ? "%1u\n" : "%1u"
        let line = String(format: format, tuplerow[col][0] == PAM_PBM_BLACK ? PBM_BLACK : PBM_WHITE)
        guard line.withCString({ fputs($0, pam.file) }) != EOF else {
            throw WriteError.ioError
        }
    }
}

func _writePamPlainRow(pam: Pam, tuplerow: [[Sample]]) throws {
    let samplesPerLine = _samplesPerPlainLine(maxVal: pam.maxVal, depth: pam.depth, lineLength: 79)
    var samplesInCurrentLine = 0
        /* number of samples written from start of line  */

    for col in 0..<Int(pam.width) {
        for plane in 0..<Int(pam.depth) {
            let value = String(format: "%lu ", tuplerow[col][plane])
            guard value.withCString({ fputs($0, pam.file) }) != EOF else {
                throw WriteError.ioError
            }
            samplesInCurrentLine += 1
            if samplesInCurrentLine >= samplesPerLine {
                guard "\n".withCString({ fputs($0, pam.file) }) != EOF else {
                    throw WriteError.ioError
                }
                samplesInCurrentLine = 0
            }
        }
    }
    guard "\n".withCString({ fputs($0, pam.file) }) != EOF else {
        throw WriteError.ioError
    }
}

func _samplesPerPlainLine(maxVal: Sample, depth: UInt32, lineLength: Int) -> Int {
/*----------------------------------------------------------------------------
   Return the minimum number of samples that should go in a line
   'lineLength' characters long in a plain format non-PBM PNM image
   with depth 'depth' and maxval 'maxval'.

   Note that this number is just for aesthetics; the Netpbm formats allow
   any number of samples per line.
-----------------------------------------------------------------------------*/
    let digitsForMaxval = Int(log(Double(maxVal) + 0.1 ) / log(10.0))
        /* Number of digits maxval has in decimal */
        /* +0.1 is an adjustment to overcome precision problems */
    let fit = lineLength / (digitsForMaxval + 1)
        /* Number of maxval-sized samples that fit in a line */
    let retval = (fit > depth) ? (fit - (fit % Int(depth))) : fit
        /* 'fit', rounded down to a multiple of depth, if possible */
    return retval
}

func _writePamRawRow(pam: Pam, tuplerow: [[Sample]], count: Int) throws {
/*----------------------------------------------------------------------------
   Write multiple ('count') copies of the same row ('tuplerow') to the file,
   in raw (not plain) format.
-----------------------------------------------------------------------------*/
    let outbuf = _pnm_allocrowimage(pam: pam)
    defer { outbuf.deallocate() }

    let rowImageSize = try _pnm_formatpamrow(pam: pam, tuplerow: tuplerow, outbuf: outbuf)

    for _ in 0..<count {
        let bytesWritten = fwrite(outbuf.baseAddress!, 1, rowImageSize, pam.file)
        guard bytesWritten == rowImageSize else {
            print("fwrite() failed to write an image row to the file. errno=\(errno) (\(String(cString: strerror(errno)))")
            throw WriteError.ioError
        }
    }
}

func _pnm_formatpamrow(pam: Pam, tuplerow: [[Sample]], outbuf: UnsafeMutableRawBufferPointer) throws -> Int {
/*----------------------------------------------------------------------------
  Same as 'pnm_formatpamtuples', except formats an entire row.
-----------------------------------------------------------------------------*/
    try _pnm_formatpamtuples(pam: pam, tuplerow: tuplerow, outbuf: outbuf, nTuple: Int(pam.width))
}

func _pnm_formatpamtuples(pam: Pam, tuplerow: [[Sample]], outbuf: UnsafeMutableRawBufferPointer, nTuple: Int) throws -> Int {
/*----------------------------------------------------------------------------   Create the image of 'nTuple' consecutive tuples of a row in the raster of a
   raw (not plain) format Netpbm image, as described by *pamP and tuplerow[].
   Put the image at *outbuf.

   'outbuf' must be the address of space allocated with pnm_allocrowimage().

   We return as *rowSizeP the number of bytes in the image.
-----------------------------------------------------------------------------*/
    guard nTuple <= pam.width else {
        print("pnm_formatpamtuples called to write more tuples (\(nTuple) than the width of a row (\(pam.width)")
        throw WriteError.internalInconsistency
    }

    guard PAM_FORMAT_TYPE(pam.format) != PBM_TYPE else {
        return try _formatPbm(pam: pam, tuplerow: tuplerow, outbuf: outbuf, nTuple: nTuple)
    }
    switch pam.bytes_per_sample {
    case 1: return try _format1Bps(pam: pam, tuplerow: tuplerow, outbuf: outbuf, nTuple: nTuple)
    case 2: return try _format2Bps(pam: pam, tuplerow: tuplerow, outbuf: outbuf, nTuple: nTuple)
    case 3: return try _format3Bps(pam: pam, tuplerow: tuplerow, outbuf: outbuf, nTuple: nTuple)
    case 4: return try _format4Bps(pam: pam, tuplerow: tuplerow, outbuf: outbuf, nTuple: nTuple)
    default:
        print("Invalid bytes per sample passed to pnm_formatpamrow(): \(pam.bytes_per_sample)")
        throw WriteError.internalInconsistency
    }
}

func _formatPbm(pam: Pam, tuplerow: [[Sample]], outbuf: UnsafeMutableRawBufferPointer, nTuple: Int) throws -> Int {
/*----------------------------------------------------------------------------
   Create the image of 'nTuple' consecutive tuples of a row in the raster of a
   raw format PBM image.

   Put the image at *outbuf; put the number of bytes of it at *rowSizeP.
-----------------------------------------------------------------------------*/
    assert(nTuple <= pam.width)
    var accum: UInt8 = 0
    for col in 0..<nTuple {
        accum |= (tuplerow[col][0] == PAM_PBM_BLACK ? UInt8(PBM_BLACK) : UInt8(PBM_WHITE)) << (7 - col % 8)
        if col%8 == 7 {
            outbuf[col/8] = accum
            accum = 0
        }
    }
    guard nTuple % 8 == 0 else {
        let lastByteIndex = nTuple / 8
        outbuf[lastByteIndex] = accum
        return lastByteIndex + 1
    }
    return nTuple / 8
}

func _format1Bps(pam: Pam, tuplerow: [[Sample]], outbuf: UnsafeMutableRawBufferPointer, nTuple: Int) throws -> Int {
    /*----------------------------------------------------------------------------
       Create the image of 'nTuple' consecutive tuples of a row in the raster of a
       raw format Netpbm image that has one byte per sample (ergo not PBM).

       Put the image at *outbuf; put the number of bytes of it at *rowSizeP.
    -----------------------------------------------------------------------------*/
    var bufferCursor = 0
    for col in 0..<nTuple {
        for plane in 0..<Int(pam.depth) {
            outbuf[bufferCursor] = UInt8(tuplerow[col][plane])
            bufferCursor += 1
        }
    }
    return nTuple * 1 * Int(pam.depth)
}

func _format2Bps(pam: Pam, tuplerow: [[Sample]], outbuf: UnsafeMutableRawBufferPointer, nTuple: Int) throws -> Int {
    /*----------------------------------------------------------------------------
      Analogous to format1BpsRow().
    -----------------------------------------------------------------------------*/
    assert(nTuple <= pam.width)
    var bufferCursor = 0
    for col in 0..<nTuple {
        for plane in 0..<Int(pam.depth) {
            _sampleToBytes2(buf: &outbuf[bufferCursor ..< bufferCursor + 2], sampleVal: tuplerow[col][plane])
            bufferCursor += 2
        }
    }
    return nTuple * 2 * Int(pam.depth)
}

func _format3Bps(pam: Pam, tuplerow: [[Sample]], outbuf: UnsafeMutableRawBufferPointer, nTuple: Int) throws -> Int {
    /*----------------------------------------------------------------------------
      Analogous to format1BpsRow().
    -----------------------------------------------------------------------------*/
    assert(nTuple <= pam.width)
    var bufferCursor = 0
    for col in 0..<nTuple {
        for plane in 0..<Int(pam.depth) {
            _sampleToBytes3(buf: &outbuf[bufferCursor ..< bufferCursor + 3], sampleVal: tuplerow[col][plane])
            bufferCursor += 3
        }
    }
    return nTuple * 3 * Int(pam.depth)
}

func _format4Bps(pam: Pam, tuplerow: [[Sample]], outbuf: UnsafeMutableRawBufferPointer, nTuple: Int) throws -> Int {
/*----------------------------------------------------------------------------
  Analogous to format1BpsRow().
-----------------------------------------------------------------------------*/
    assert(nTuple <= pam.width)
    var bufferCursor = 0
    for col in 0..<nTuple {
        for plane in 0..<Int(pam.depth) {
            _sampleToBytes4(buf: &outbuf[bufferCursor ..< bufferCursor + 4], sampleVal: tuplerow[col][plane])
            bufferCursor += 4
        }
    }
    return nTuple * 4 * Int(pam.depth)
}

/* Though it is possible to simplify the sampleToBytesN() and
   formatNBpsRow() functions into a single routine that handles all
   sample widths, we value efficiency higher here.  Earlier versions
   of Netpbm (before 10.25) did that, with a loop, and performance
   suffered visibly.
*/

func _sampleToBytes2(buf: inout Slice<UnsafeMutableRawBufferPointer>, sampleVal: Sample) {
    buf[0] = (UInt8(sampleVal) >> 8) & 0xff
    buf[1] = (UInt8(sampleVal) >> 0) & 0xff
}

func _sampleToBytes3(buf: inout Slice<UnsafeMutableRawBufferPointer>, sampleVal: Sample) {
    buf[0] = (UInt8(sampleVal) >> 16) & 0xff
    buf[1] = (UInt8(sampleVal) >> 8) & 0xff
    buf[2] = (UInt8(sampleVal) >> 0) & 0xff
}

func _sampleToBytes4(buf: inout Slice<UnsafeMutableRawBufferPointer>, sampleVal: Sample) {
    buf[0] = (UInt8(sampleVal) >> 24) & 0xff
    buf[1] = (UInt8(sampleVal) >> 16) & 0xff
    buf[2] = (UInt8(sampleVal) >> 8) & 0xff
    buf[3] = (UInt8(sampleVal) >> 0) & 0xff
}

func _pm_stripeq(_ comparand: String, _ comparator: String) -> Bool {
/*----------------------------------------------------------------------------
  Compare two strings, ignoring leading and trailing white space.

  Return 1 (true) if the strings are identical; 0 (false) otherwise.
-----------------------------------------------------------------------------*/
    comparand.trimmingCharacters(in: .whitespacesAndNewlines) == comparator.trimmingCharacters(in: .whitespacesAndNewlines)
}

func _writeComments(pam: Pam) throws {
    /*----------------------------------------------------------------------------
     Write comments for a PAM header, insofar as *pamP specifies comments.
     -----------------------------------------------------------------------------*/
    let comment = pam.comment
    guard !comment.isEmpty else { return }
    guard let asciiComment = comment.cString(using: .ascii) else {
        print("Skipping comment as it cannot be represented in ascii encoding") // TODO: test if original netpbm utilities can digest utf8 comments
        return
    }
    var startOfLine = true
    for cchar in asciiComment {
        if startOfLine {
            guard fputc(Int32(Character("#").asciiValue!), pam.file) != EOF else {
                throw WriteError.ioError
            }
        }
        guard fputc(Int32(cchar), pam.file) != EOF else {
            throw WriteError.ioError
        }
        startOfLine = cchar == Character("\n").asciiValue!
    }
    if !startOfLine {
        guard fputc(Int32(Character("\n").asciiValue!), pam.file) != EOF else {
            throw WriteError.ioError
        }
    }
}

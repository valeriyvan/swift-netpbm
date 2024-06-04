import Foundation

public struct PGMImageSequence: AsyncSequence {

    public typealias Element = PGMImageGraySequence
    public typealias AsyncIterator = Iterator

    public struct Iterator: AsyncIteratorProtocol {
        public let file: UnsafeMutablePointer<FILE>

        public init(file: UnsafeMutablePointer<FILE>) {
            self.file = file
        }

        public mutating func next() async throws -> PGMImageGraySequence? {
            let eof = try _pm_nextimage(file)
            guard !eof else { return nil }
            return try PGMImageGraySequence(file: file)
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

public struct PGMImageGraySequence: AsyncSequence {
    public typealias Element = Gray
    public typealias AsyncIterator = Iterator

    public struct Iterator: AsyncIteratorProtocol {
        var currentRow = -1
        var row: [Gray] = []
        var currentElementIndex = 0
        let cols: Int32
        let rows: Int32
        let maxVal: Gray
        let format: Int32
        let file: UnsafeMutablePointer<FILE>

        init(file: UnsafeMutablePointer<FILE>, cols: Int32, rows: Int32, maxVal: Gray, format: Int32) {
            self.file = file
            self.cols = cols
            self.rows = rows
            self.maxVal = maxVal
            self.format = format
        }

        public mutating func next() async throws -> Gray? {
            if currentRow == -1 {
                row = try _pgm_readpgmrow(file, cols: cols, maxVal: maxVal, format: format)
                currentRow = 0
                currentElementIndex = 0
                defer { currentElementIndex += 1 }
                return row[currentElementIndex]
            } else if currentElementIndex < row.count {
                defer { currentElementIndex += 1 }
                return row[currentElementIndex]
            } else if currentRow < rows-1 {
                row = try _pgm_readpgmrow(file, cols: cols, maxVal: maxVal, format: format)
                currentRow += 1
                currentElementIndex = 0
                defer { currentElementIndex += 1 }
                return row[currentElementIndex]
            }
            return nil
        }
    }

    public var width: Int { Int(cols) }
    public var height: Int { Int(rows) }
    public var maxValue: Gray { maxVal }
    
    private let file: UnsafeMutablePointer<FILE>
    private let cols: Int32
    private let rows: Int32
    private let maxVal: Gray
    private let format: Int32

    public init(file: UnsafeMutablePointer<FILE>) throws {
        self.file = file
        (cols, rows, maxVal, format) = try _pgm_readpgminit(file)
    }

    public func makeAsyncIterator() -> Iterator {
        return Iterator(file: file, cols: cols, rows: rows, maxVal: maxVal, format: format)
    }
}


/* Since April 2000, we are capable of reading and generating raw
   (binary) PGM files with maxvals up to 65535.  However, before that
   the maximum (as usually implemented) was 255, and people still want
   to generate files with a maxval of no more than 255 in most cases
   (because then old Netpbm programs can process them, and they're
   only half as big).

   So we keep PGM_MAXMAXVAL = 255, even though it's kind of a misnomer.

   Note that one could always write a file with maxval > PGM_MAXMAXVAL and
   it would just go into plain (text) format instead of raw (binary) format.
   Along with the expansion to 16 bit raw files, we took away that ability.
   Unless you specify 'forceplain' on the pgm_writepgminit() call, it will
   fail if you specify a maxval > PGM_OVERALLMAXVAL.  I made this design
   decision because I don't think anyone really wants to get a plain format
   file with samples larger than 65535 in it.  However, it should be possible
   just to increase PGM_OVERALLMAXVAL and get that old function back for
   maxvals that won't fit in 16 bits.  I think the only thing really
   constraining PGM_OVERALLMAXVAL is the size of the 'gray' data structure,
   which is generally 32 bits.
*/

let PGM_OVERALLMAXVAL: UInt32 = 65535
let PGM_MAXMAXVAL: UInt32 = 255

public enum PgmParseError: Error {
    case wrongFormat // header is wrong
    case ioError
    case internalInconsistency
    case insufficientMemory
//    case unexpectedEndOfFile
//    case junkWhereBitsShouldBe
//    case junkWhereUnsignedIntegerShouldBe
//    case tooBigNumber
//    case imageTooLarge
}

/* The following definition has nothing to do with the format of a PGM file */
public typealias Gray = UInt32

func _pgm_readpgminit(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32, maxVal: Gray, format: Int32) {
    /* Check magic number. */
    let realFormat: Int32 = try _pm_readmagicnumber(file)
    var cols: Int32 = 0, rows: Int32 = 0
    var maxVal: Gray = 0
    var format: Int32
    switch (PAM_FORMAT_TYPE(realFormat)) {
        case PBM_TYPE:
            format = realFormat
            (cols, rows) = try _pbm_readpbminitrest(file)
            /* Mathematically, it makes the most sense for the maxval of a PBM
             file seen as a PGM to be 1.  But we tried this for a while and
             found that it causes unexpected results and frequent need for a
             Pnmdepth stage to convert the maxval to 255.  You see, when you
             transform a PGM file in a way that causes interpolated gray shades,
             there's no in-between value to use when maxval is 1.  It's really
             hard even to discover that your lack of Pnmdepth is your problem.
             So we pick 255, which is the most common PGM maxval, and the highest
             resolution you can get without increasing the size of the PGM
             image.

             So this means some programs that are capable of exploiting the
             bi-level nature of a PBM file must be PNM programs instead of PGM
             programs.
             */
            maxVal = PGM_MAXMAXVAL
        case PGM_TYPE:
            format = realFormat
            (cols, rows, maxVal) = try _pgm_readpgminitrest(file)
        case PPM_TYPE:
            print("Input file is a PPM, which this program cannot process. You may want to convert it to PGM with 'ppmtopgm'.")
            throw PgmParseError.wrongFormat
        case PAM_TYPE:
            (cols, rows, maxVal, format) = try _pnm_readpaminitrestaspnm(file)
            if PAM_FORMAT_TYPE(format) != PGM_TYPE {
                print("Format of PAM input is not consistent with PGM")
                throw PgmParseError.wrongFormat
            }
        default:
            print("bad magic number \(String(format: "0x%x", realFormat)) - not a PPM, PGM, PBM, or PAM file")
            throw PgmParseError.wrongFormat
    }
    try _pgm_validateComputableSize(cols: cols, rows: rows)

    try _pgm_validateComputableMaxval(maxVal: maxVal)

    return (cols: cols, rows: rows, maxVal: maxVal, format: format)
}

func _pgm_readpgminitrest(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32, maxVal: Gray) {
    /* Read size. */
    let (cols, rows) = try _pbm_readpbminitrest(file)
    /* Read maxval. */
    let maxVal = try _pm_getuint(file)
    if maxVal > PGM_OVERALLMAXVAL {
        print("maxVal of input image \(maxVal) is too large. The maximum allowed by the format is \(PGM_OVERALLMAXVAL)")
        throw PgmParseError.wrongFormat
    }
    if maxVal == 0 {
        print("maxVal of input image is zero.")
        throw PgmParseError.wrongFormat
    }
    return (cols: cols, rows: rows, maxVal: maxVal)
}

func _pnm_readpaminitrestaspnm(_ file: UnsafeMutablePointer<FILE>) throws -> (cols: Int32, rows: Int32, maxVal: Gray, format: Int32) {
    fatalError("Not implemented")
/*----------------------------------------------------------------------------
   Read the rest of the PAM header (after the first line) and return
   information as if it were PPM or PGM.

   Die if it isn't a PAM of the sort we can treat as PPM or PGM.
-----------------------------------------------------------------------------*/
/*
    var pam: Pam = Pam()

    pam.size   = UInt32(MemoryLayout<Pam>.size) // sizeof(struct pam)
    pam.file   = file
    pam.len    = PAM_STRUCT_SIZE(tuple_type)
    pam.format = PAM_FORMAT

    try _readpaminitrest(pam: &pam)

    /* A PAM raster of depth 1 is identical to a PGM raster.  A PAM
       raster of depth 3 is identical to PPM raster.  So
       ppm_readppmrow() will be able to read the PAM raster as long as
       the format it thinks it is (PGM or PPM) corresponds to the PAM
       depth.  Similar for pgm_readpgmrow().
    */
    let format: Int32 =
    switch (pam.depth) {
    case 3:
        RPPM_FORMAT
    case 1:
        RPGM_FORMAT
    default:
        print("Cannot treat PAM image as PPM or PGM, because its depth \(pam.depth) is not 1 or 3.")
        throw PgmParseError.wrongFormat
    }
    return (cols: pam.width, rows: pam.height, maxVal: Gray(pam.maxVal), format: format)
*/
}

func _pgm_validateComputableSize(cols: Int32, rows: Int32) throws {
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
    if cols > Int32.max / Int32(MemoryLayout<Gray>.size) || cols > Int32.max - 2 {
        print("image width \(cols) too large to be processed")
        throw PbmParseError.imageTooLarge
    }
    if rows > Int32.max - 2 {
        print("image height \(rows) too large to be processed")
        throw PbmParseError.imageTooLarge
    }
}

func _pgm_validateComputableMaxval(maxVal: Gray) throws {
/*----------------------------------------------------------------------------
  This is similar to validateComputableSize, but for the maxval.
-----------------------------------------------------------------------------*/
    /* Code sometimes allocates an array indexed by sample values and
       represents the size of that array as an INT.  (UNSIGNED INT would be
       more proper, but there's no need to be that permissive).

       Code also sometimes iterates through sample values and quits when the
       value is greater than the maxval.

       Code often divides by the maxval, but we don't have to check for maxval
       == 0 as a computability problem because that is not a valid maxval.

       Note that in the PNM Plain formats, there is no upper limit for a
       maxval, though the 'gray' type does constrain what has been passed to
       us.
    */

    if maxVal > Int32.max - 1 {
        print("Maxval \(maxVal) is too large to be processed")
        throw PbmParseError.imageTooLarge
    }
}

func _readpaminitrest(pam: inout Pam) throws {
    fatalError("Not implemented")
/*----------------------------------------------------------------------------
   Read the rest of the PAM header (after the first line -- the magic
   number line).  Fill in all the information in *pamP.
-----------------------------------------------------------------------------*/
/*    struct headerSeen headerSeen;
    char * comments;

    headerSeen.width  = FALSE;
    headerSeen.height = FALSE;
    headerSeen.depth  = FALSE;
    headerSeen.maxval = FALSE;
    headerSeen.endhdr = FALSE;

    pamP->tuple_type[0] = '\0';

    comments = strdup("");

    {
        int c;
        /* Read off rest of 1st line -- probably just the newline after the
           magic number
        */
        while ((c = getc(pamP->file)) != -1 && c != '\n');
    }

    while (!headerSeen.endhdr) {
        char buffer[256];
        char * rc;
        rc = fgets(buffer, sizeof(buffer), pamP->file);
        if (rc == NULL)
            pm_error("EOF or error reading file while trying to read the "
                     "PAM header");
        else {
            buffer[256-1-1] = '\n';  /* In case fgets() truncated */
            if (buffer[0] == '#')
                appendComment(&comments, buffer);
            else if (pm_stripeq(buffer, ""));
                /* Ignore it; it's a blank line */
            else
                processHeaderLine(buffer, pamP, &headerSeen);
        }
    }

    disposeOfComments(pamP, comments);

    if (!headerSeen.height)
        pm_error("No HEIGHT header line in PAM header");
    if (!headerSeen.width)
        pm_error("No WIDTH header line in PAM header");
    if (!headerSeen.depth)
        pm_error("No DEPTH header line in PAM header");
    if (!headerSeen.maxval)
        pm_error("No MAXVAL header line in PAM header");

    if (pamP->height == 0)
        pm_error("HEIGHT value is zero in PAM header");
    if (pamP->width == 0)
        pm_error("WIDTH value is zero in PAM header");
    if (pamP->depth == 0)
        pm_error("DEPTH value is zero in PAM header");
    if (pamP->maxval == 0)
        pm_error("MAXVAL value is zero in PAM header");
    if (pamP->maxval > PAM_OVERALL_MAXVAL)
        pm_error("MAXVAL value (%lu) in PAM header is greater than %lu",
                 pamP->maxval, PAM_OVERALL_MAXVAL);
*/
}

func _pgm_readpgmrow(_ file: UnsafeMutablePointer<FILE>, cols: Int32, maxVal: Gray, format: Int32) throws -> [Gray] {
    switch (format) {
    case PGM_FORMAT:
        var grayrow: [Gray] = []
        for _ in 0..<cols {
            let val =  try _pm_getuint(file)
            guard val <= maxVal else {
                print("value out of bounds (\(val) > \(maxVal)")
                throw PgmParseError.wrongFormat // ???
            }
            grayrow.append(val)
        }
        return grayrow
    case RPGM_FORMAT:
        return try _readRpgmRow(file, cols: cols, maxVal: maxVal, format: format)
    case PBM_FORMAT:
        fallthrough
    case RPBM_FORMAT:
        fatalError("Not implemented")
        // return _readPbmRow(file, cols: cols, maxVal: maxVal, format: format) // ??? should be
    default:
        print("can't happen")
        throw PgmParseError.internalInconsistency
    }
}

func _readRpgmRow(_ file: UnsafeMutablePointer<FILE>, cols: Int32, maxVal: Gray, format: Int32) throws -> [Gray] {
    let bytesPerSample = maxVal < 256 ? 1 : 2 // TODO: !!!
    let bytesPerRow = Int(cols) * bytesPerSample

    var grayrow: [Gray] = []
    let rowBuffer = malloc(bytesPerRow)
    if rowBuffer == nil {
        print("Unable to allocate memory for row buffer for \(cols) columns")
        throw PgmParseError.insufficientMemory
    } else {
        let rc = fread(rowBuffer, 1, bytesPerRow, file)
        if rc == 0 {
            print("Error reading row.  fread() errno=\(errno) (\(String(cString: strerror(errno)))")
            throw PgmParseError.ioError
        } else if rc != bytesPerRow {
            print("Error reading row.  Short read of \(rc) bytes instead of \(bytesPerRow).")
        } else {
            for col in 0..<Int(cols) {
                grayrow.append(rowBuffer!.assumingMemoryBound(to: Gray.self).advanced(by: col).pointee)
            }
            try _validateRpgmRow(grayrow: grayrow, cols: cols, maxVal: maxVal)
        }
        free(rowBuffer)
    }
    return grayrow
}

// This function is redundant. Or not?
func _validateRpgmRow(grayrow: [Gray], cols: Int32, maxVal: Gray) throws {
/*----------------------------------------------------------------------------
  Check for sample values above maxval in input.

  Note: a program that wants to deal with invalid sample values itself can
  simply make sure it uses a sufficiently high maxval on the read function
  call, so this validation never fails.
-----------------------------------------------------------------------------*/
    if (maxVal == 255 || maxVal == 65535) {
        /* There's no way a sample can be invalid, so we don't need to look at
           the samples individually.
        */
        return
    } else {
        for col in 0..<Int(cols) {
            if (grayrow[col] > maxVal) {
                print("gray value \(grayrow[col]) is greater than maxval (\(maxVal)")
                throw PgmParseError.wrongFormat
            }
        }
    }
}

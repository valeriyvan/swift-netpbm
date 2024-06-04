import Foundation

typealias pm_filepos = Int

typealias Sample = UInt /* unsigned long */
    /* Regardless of the capacity of "unsigned long", a sample is always
       less than 1 << 16.  This is essential for some code to avoid
       arithmetic overflows.
    */

struct Pam {
    /* This structure describes an open PAM image file.  It consists
       entirely of information that belongs in the header of a PAM image
       and filesystem information.  It does not contain any state
       information about the processing of that image.

       This is not considered to be an opaque object.  The user of Netbpm
       libraries is free to access and set any of these fields whenever
       appropriate.  The structure exists to make coding of function calls
       easy.
    */

    /* 'size' and 'len' are necessary in order to provide forward and
       backward compatibility between library functions and calling programs
       as this structure grows.
       */
    var size: UInt32
        /* The storage size of this entire structure, in bytes */
    var len: UInt32
        /* The length, in bytes, of the information in this structure.
           The information starts in the first byte and is contiguous.
           This cannot be greater than 'size'

           Use PAM_STRUCT_SIZE() to compute or interpret a value for this.
        */
    var file: UnsafeMutablePointer<FILE>
    var format: Int32
        /* The format code of the image.  This is PAM_FORMAT
           unless the PAM image is really a view of a PBM, PGM, or PPM
           image.  Then it's PBM_FORMAT, RPBM_FORMAT, etc.  For output,
           only the format _type_ is significant, e.g. PBM_FORMAT
           and RPBM_FORMAT have identical effect.  This is because on
           output, 'plainformat' determines whether the output is the
           raw or plain format of the type given by 'format'.
           */
    let plainformat: UInt32
        /* Logical: On output, use plain version of the format type
           indicated by 'format'.  Otherwise, use the raw version.
           (i.e., on output, the plainness information in 'format' is
           irrelevant).  Input functions set this to FALSE, for the
           convenience of programs that copy an input pam structure for
           use with output.

           Before Netpbm 10.32, this was rather different.  It simply
           described for convenience the plainness of the format indicated
           by 'format'.

           This is meaningless when 'format' is PAM_FORMAT, as PAM does not
           have plain and raw variations.
        */
    let height: Int32  /* Height of image in rows */
    let width: Int32
        /* Width of image in number of columns (tuples per row) */
    let depth: UInt32
        /* Depth of image (number of samples in each tuple). */
    let maxVal: Sample  /* Maximum defined value for a sample */
    let bytes_per_sample: UInt32
        /* Number of bytes used to represent each sample in the image file.
           Note that this is strictly a function of 'maxval'.  It is in a
           a separate member for computational speed.
        */
    let tuple_type: [CChar] /* [256] */
        /* The tuple type string from the image header.  If the PAM image
           is really a view of a PBM, PGM, or PPM image, the value is
           PAM_PBM_TUPLETYPE, PAM_PGM_TUPLETYPE, or PAM_PPM_TUPLETYPE,
           respectively.
        */
    let allocation_depth: UInt32
        /* The number of samples for which memory is allocated for any
           'tuple' type associated with this PAM structure.  This must
           be at least as great as 'depth'.  Only the first 'depth' of
           the samples of a tuple are meaningful.

           The purpose of this is to make it possible for a program to
           change the type of a tuple to one with more or fewer
           planes.

           0 means the allocation depth is the same as the image depth.
        */
    let comment: String
        /* Pointer to a pointer to a NUL-terminated ASCII string of
           comments.  When reading an image, this contains the
           comments from the image's PAM header; when writing, the
           image gets these as comments, right after the magic number
           line.  The individual comments are delimited by newlines
           and are in the same order as in the PAM header.

           On output, NULL means no comments.

           On input, libnetpbm mallocs storage for the comments and places
           the pointer at *comment_p.  Caller must free it.  NULL means
           libnetpbm does not return comments and does not allocate any
           storage.
        */
    let visual: Bool  /* boolean */
        /* tuple_type is one of the PAM-defined tuple types for visual
           images ("GRAYSCALE", "RGB_ALPHA", etc.).
        */
    let color_depth: UInt32
        /* Number of color planes (i.e. 'depth', but without transparency).
           The color planes are the lowest numbered ones.  Meaningless if
           'visual' is false.
        */
    let have_opacity: Bool   /* boolean */
        /* The tuples have an opacity (transparency, alpha) plane.
           Meaningless if 'visual' is false.
        */
    let opacity_plane: UInt32
        /* The plane number of the opacity plane;  meaningless if
           'haveOpacity' is false or 'visual' is false.
        */
    let is_seekable: Bool  /* boolean */
        /* The file 'file' is seekable -- you can set the position of next
           reading or writing to anything and any time.

           If libnetpbm cannot tell if it is seekable or not, this is false.
        */
    let raster_pos: pm_filepos
        /* The file position of the raster (which is also the end of the
           header).

           Meaningless if 'is_seekable' is false.
        */

    // TODO: REMOVE!!!
    init() {
        size = 0
        len = 0
        file = UnsafeMutablePointer<FILE>.allocate(capacity: 1)
        format = 0
        plainformat = 0
        height = 0
        width = 0
        depth = 0
        maxVal = 0
        bytes_per_sample = 0
        tuple_type = [CChar](repeating: 0, count: 256)
        allocation_depth = 0
        comment = ""
        visual = false
        color_depth = 0
        have_opacity = false
        opacity_plane = 0
        is_seekable = false
        raster_pos = 0
    }
}


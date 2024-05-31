import Foundation

let PAM_MAGIC1: Int32 = Int32(Character("P").asciiValue!)
let PAM_MAGIC2: Int32 = Int32(Character("7").asciiValue!)
let PAM_FORMAT: Int32 = PAM_MAGIC1 * 256 + PAM_MAGIC2
let PAM_TYPE: Int32 = PAM_FORMAT

func PAM_FORMAT_TYPE(_ f: Int32) -> Int32 {
    f == PAM_FORMAT ? PAM_TYPE : PPM_FORMAT_TYPE(f)
}

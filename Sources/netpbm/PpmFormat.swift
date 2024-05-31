import Foundation

let PPM_MAGIC1: Int32 = Int32(Character("P").asciiValue!)
let PPM_MAGIC2: Int32 = Int32(Character("3").asciiValue!)
let RPPM_MAGIC2: Int32 = Int32(Character("6").asciiValue!)
let PPM_FORMAT: Int32 = PPM_MAGIC1 * 256 + PPM_MAGIC2
let RPPM_FORMAT: Int32 = PPM_MAGIC1 * 256 + RPPM_MAGIC2
let PPM_TYPE = PPM_FORMAT

func PPM_FORMAT_TYPE(_ f: Int32) -> Int32 {
    f == PPM_FORMAT || (f) == RPPM_FORMAT ? PPM_TYPE : PGM_FORMAT_TYPE(f)
}

import Foundation

let PBM_MAGIC1: Int32 = Int32(Character("P").asciiValue!)
let PBM_MAGIC2: Int32 = Int32(Character("1").asciiValue!)
let RPBM_MAGIC2: Int32 = Int32(Character("4").asciiValue!)
let PBM_FORMAT: Int32 = PBM_MAGIC1 * 256 + PBM_MAGIC2
let RPBM_FORMAT: Int32 = PBM_MAGIC1 * 256 + RPBM_MAGIC2
let PBM_TYPE: Int32 = PBM_FORMAT

func PBM_FORMAT_TYPE(_ f: Int32) -> Int32 {
    f == PBM_FORMAT || f == RPBM_FORMAT ? PBM_TYPE : -1
}

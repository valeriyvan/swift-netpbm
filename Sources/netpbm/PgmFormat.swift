import Foundation

let PGM_MAGIC1: Int32 = Int32(Character("P").asciiValue!)
let PGM_MAGIC2: Int32 = Int32(Character("2").asciiValue!)
let RPGM_MAGIC2: Int32 = Int32(Character("5").asciiValue!)
let PGM_FORMAT: Int32 = PGM_MAGIC1 * 256 + PGM_MAGIC2
let RPGM_FORMAT: Int32 = PGM_MAGIC1 * 256 + RPGM_MAGIC2
let PGM_TYPE: Int32 = PGM_FORMAT

func PGM_FORMAT_TYPE(_ f: Int32) -> Int32 {
    f == PGM_FORMAT || f == RPGM_FORMAT ? PGM_TYPE : PBM_FORMAT_TYPE(f)
}

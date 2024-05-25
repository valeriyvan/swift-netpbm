import Foundation
import libnetpbm

//  Copyright: Fraser Cadger (2018) <frasercadger@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//  Description: simple variation on pbm_copy, copies a pbm file's metadata
//  and image data, and then flips every bit of the image data; i.e. if a
//  bit is 0 it will be set to 1, and if it is 1 it will be set to 0. The
//  purpose is to build on pbm_copy, by manipulating the image itself.
//  Flipping a bit is one of the simplest ways to modify an image (or any data).
//  The end result will be a noticeably different output image.
//
//  This is Swift version of example from
//  https://github.com/frasercadger/netpbm_examples/blob/master/pbm_bitflip/src/main.c

//  TODO: test on sunrise_at_sea.ppm which fails at reading file

let PBM_MAGIC1: Int = Int(Character("P").asciiValue!)
let PBM_MAGIC2: Int = Int(Character("1").asciiValue!)
let RPBM_MAGIC2: Int = Int(Character("4").asciiValue!)
let PBM_FORMAT: Int = PBM_MAGIC1 * 256 + PBM_MAGIC2
let RPBM_FORMAT: Int = PBM_MAGIC1 * 256 + RPBM_MAGIC2

func bitflipTupplerow(_ pTupleRow: inout UnsafeMutablePointer<tuple?>, _ pIn: pam) {
    for i in 0..<Int(pIn.width) {
        for j in 0..<Int(pIn.depth) {
            let sampleBits: UInt8
            if pIn.format == PBM_FORMAT || pIn.format == RPBM_FORMAT {
                sampleBits = 1
            } else {
                sampleBits = UInt8(pIn.bytes_per_sample * 8)
            }
            for k in 0..<sampleBits {
                pTupleRow[i]![j] ^= 1 << k // TODO: !!!
            }
        }
    }
}

func pbmBitflip(_ pIn: inout pam, _ pOut: inout pam) {
    guard var pTupleRow: UnsafeMutablePointer<tuple?> = pnm_allocpamrow(&pIn) else {
        fatalError("Failed to allocate memory for tuple row")
    }

    for _ in 0..<pIn.height {
        pnm_readpamrow(&pIn, pTupleRow)
        bitflipTupplerow(&pTupleRow, pIn)
        pnm_writepamrow(&pOut, pTupleRow)
    }

    pm_freerow(pTupleRow)
}

// Function to read a PBM image
func read_pbm_image(filename: String, pInput: inout pam) -> Bool {
    // Open image as regular file
    guard let pInputFile = fopen(filename, "r") else {
        return false
    }

    // Read the image header from file and initialise input structure
    // This is essentially the image's metadata
    pnm_readpaminit(pInputFile, &pInput, Int32(MemoryLayout<pam>.stride))

    return true
}

// Function to prepare a PBM copy
func prepare_pbm_copy(pInPbm: inout pam, pOutPbm: inout pam, pFilename: String) -> Bool {
    // Open output file
    guard let pOutputFile = fopen(pFilename, "w") else {
        print("Failed to open output file")
        return false
    }

    // Create output structure, copying in struct values
    // As we are doing a straight copy, the output file will
    // have similar metadata to the input file
    memcpy(&pOutPbm, &pInPbm, MemoryLayout<pam>.stride)

    // Set output struct's file pointer to our output file
    pOutPbm.file = pOutputFile

    // Copy image header to output file
    pnm_writepaminit(&pOutPbm)

    return true
}

let pOutFilename = "bitflipped.pbm"

print("Beginning pbm_bitflip")

guard CommandLine.argc >= 2 else {
    fatalError("Usage: pbm_bitflip input_filename")
}
let pInFilename = CommandLine.arguments[1]
print("Reading pbm image from: \(pInFilename)")

var inPbm = pam()
let readSuccessful = read_pbm_image(filename: pInFilename, pInput: &inPbm)
if !readSuccessful {
    print("Read failed")
} else {
    print("Read successful")
    print("Image height: \(inPbm.height), width: \(inPbm.width), depth: \(inPbm.depth)")

    print("Preparing output file: \(pOutFilename)")
    var outPbm = pam()
    let prepSuccessful = prepare_pbm_copy(pInPbm: &inPbm, pOutPbm: &outPbm, pFilename: pOutFilename)

    if prepSuccessful {
        print("Output preparation successful")
        pbmBitflip(&inPbm, &outPbm)
    } else {
        print("Output preparation failed")
    }
}

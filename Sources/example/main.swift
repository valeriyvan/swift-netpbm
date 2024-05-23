import Foundation
import libnetpbm


/*
   Example program fragment to read a PAM or PNM image
   from stdin, add up the values of every sample in it
   (I don't know why), and write the image unchanged to
   stdout.

   This is Swift version of example from https://netpbm.sourceforge.net/doc/libnetpbm_ug.html#example
 */

// Initialize the NetPBM library
pm_init(CommandLine.arguments[0], 0)

// Define PAM structures
var inpam = pam()

// Read the PAM/PNM image header from stdin
pnm_readpaminit(stdin, &inpam, Int32(MemoryLayout<pam>.stride))

// Prepare the output PAM structure
var outpam = inpam
outpam.file = stdout

// Write the PAM header to stdout
pnm_writepaminit(&outpam)

// Allocate memory for a row of tuples
guard let tuplerow: UnsafeMutablePointer<tuple?> = pnm_allocpamrow(&inpam) else {
    fatalError("Failed to allocate memory for tuple row")
}

var grandTotal: UInt = 0

// Process each row of the image
for _ in 0..<inpam.height {
    // Read a row of the image
    pnm_readpamrow(&inpam, tuplerow)
    // Process each pixel in the row
    for column in 0..<Int(inpam.width) {
        // Process each plane of the pixel
        guard let tuple = tuplerow[column] else { continue }
        for plane in 0..<Int(inpam.depth) {
            grandTotal += tuple[plane]
        }
    }
    // Write the row to the output image
    pnm_writepamrow(&outpam, tuplerow)
}

// Free the allocated memory for the tuple row
// pnm_freepamrow(tuplerow)
pm_freerow(tuplerow) // use pnm_freepamrow as pnm_freepamrow is define and unavailable from Swift

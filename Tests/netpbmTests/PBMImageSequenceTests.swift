import XCTest
@testable import netpbm

final class PBMImageSequenceTests: XCTestCase {

    func testRead() async throws {
        let iSeq = try PBMImageSequence(string:
            """
            P1
            # Image 1: 5x4 checkerboard pattern
            5 4
            0 1 0 1 0
            1 0 1 0 1
            0 1 0 1 0
            1 0 1 0 1

            P1
            # Image 2: 4x4 vertical stripes
            4 4
            0 0 1 1
            0 0 1 1
            0 0 1 1
            0 0 1 1

            """
        )
        
        var images: [(cols: Int, rows: Int, pixels: [UInt8])] = []

        for try await imageBitIterator in iSeq {
            var pixels: [UInt8] = []
            for try await bit in imageBitIterator {
                pixels.append(UInt8(bit.rawValue))
            }
            images.append(
                (cols: imageBitIterator.width, rows: imageBitIterator.height, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 2)

        let first = images[0]
        XCTAssertEqual(first.cols, 5)
        XCTAssertEqual(first.rows, 4)
        XCTAssertEqual(first.pixels.count, 5 * 4)
        XCTAssertEqual(first.pixels, [0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1])
        
        let second = images[1]
        XCTAssertEqual(second.cols, 4)
        XCTAssertEqual(second.rows, 4)
        XCTAssertEqual(second.pixels.count, 4 * 4)
        XCTAssertEqual(second.pixels, [0,0,1,1, 0,0,1,1, 0,0,1,1, 0,0,1,1])
    }

}

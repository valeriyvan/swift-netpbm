import XCTest
@testable import netpbm

final class PBMTests: XCTestCase {

    func testReadWrite() async throws {
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

        for try await imageBitSequence in iSeq {
            let pixels: [UInt8] = try await imageBitSequence.reduce(into: []) { $0.append(UInt8($1.rawValue)) }
            images.append(
                (cols: imageBitSequence.width, rows: imageBitSequence.height, pixels: pixels)
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

        let string = try PBMImageWriter.write(images: images, forcePlane: true)
        XCTAssertEqual(
            string,
            """
            P1
            5 4
            01010
            10101
            01010
            10101

            P1
            4 4
            0011
            0011
            0011
            0011

            """
        )
    }

}

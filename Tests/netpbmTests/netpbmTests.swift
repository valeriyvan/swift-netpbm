import XCTest
@testable import netpbm

// Tests crashes if image is broken e.g. some pixels are missing.
// Instead of returning error libnetpbm just crashes.
// It looks not always checking result of malloc which will lead
// to crash in law memory conditions.

final class netpbmTests: XCTestCase {

    func testReadFirstImageFromString() throws {
        let (rows, cols, pixels) = try PBM.firstImage(string:
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
        XCTAssertEqual(rows, 4)
        XCTAssertEqual(cols, 5)
        XCTAssertEqual(pixels, [0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1])
    }

    func testImagesFromString() throws {
        let images = try PBM.images(string:
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
        XCTAssertEqual(images.count, 2)
        let first = images[0]
        XCTAssertEqual(first.rows, 4)
        XCTAssertEqual(first.cols, 5)
        XCTAssertEqual(first.pixels, [0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1])
        let second = images[1]
        XCTAssertEqual(second.rows, 4)
        XCTAssertEqual(second.cols, 4)
        XCTAssertEqual(second.pixels, [0,0,1,1, 0,0,1,1, 0,0,1,1, 0,0,1,1])
    }

}

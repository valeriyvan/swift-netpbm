import XCTest
@testable import netpbm

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
        XCTAssertEqual(cols, 5)
        XCTAssertEqual(rows, 4)
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
        XCTAssertEqual(first.cols, 5)
        XCTAssertEqual(first.rows, 4)
        XCTAssertEqual(first.pixels, [0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1])
        let second = images[1]
        XCTAssertEqual(second.cols, 4)
        XCTAssertEqual(second.rows, 4)
        XCTAssertEqual(second.pixels, [0,0,1,1, 0,0,1,1, 0,0,1,1, 0,0,1,1])
    }

    func testImagesFromStringMissingBitsThrows() throws {
        XCTAssertThrowsError(
            try PBM.images(string:
                """
                P1
                # Image 1: 5x4 checkerboard pattern
                5 4
                0 1 0 1 0
                1 0 1 0 1
                0 1 0 1 0
                1 0 1 0

                """
                          )

        ) { error in
            XCTAssertEqual(error as? PBM.PbmParseError, PBM.PbmParseError.unexpectedEndOfFile)
        }

        XCTAssertThrowsError(
            try PBM.images(string:
                """
                P1
                # Image 1: 5x4 checkerboard pattern
                5 4
                0 1 0 1 0
                1 0 1 0 1
                0 1 0 1 0
                1 0 1 0

                P1
                # Image 2: 4x4 vertical stripes
                4 4
                0 0 1 1
                0 0 1 1
                0 0 1 1
                0 0 1 1

                """
                          )
        ) { error in
            XCTAssertEqual(error as? PBM.PbmParseError, PBM.PbmParseError.junkWhereBitsShouldBe)
        }
    }

    func testImagesFromStringMissingBitsThrows_() throws {
        XCTAssertThrowsError(
            try PBM.images(string:
                """
                E1
                # Image 1: 5x4 checkerboard pattern
                5 
                0 1 0 1 0
                1 0 1 0 1
                0 1 0 1 0
                1 0 1 0

                """
            )
        ) { error in
            XCTAssertEqual(error as? PBM.PbmParseError, PBM.PbmParseError.wrongFormat)
        }
    }

    func testWriteImagesFromString1() throws {
        let sample = """
            P1
            5 4
            01010
            10101
            01010
            10101

            """
        let images = try PBM.images(string: sample)
        let stringOut = try PBM.write(images: images, forcePlane: true)
        XCTAssertEqual(sample, stringOut)
    }

    func testWriteImagesFromString2() throws {
        let sample = """
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
        let images = try PBM.images(string: sample)
        let stringOut = try PBM.write(images: images, forcePlane: true)
        XCTAssertEqual(sample, stringOut)
    }

    // Test line wrapping at 70
    func testWriteImagesFromString3() throws {
        let stringIn = "P1 100 100 " + String(repeating: "10", count: 100 * 100 / 2)
        let images = try PBM.images(string: stringIn)
        let stringOut = try PBM.write(images: images, forcePlane: true)
        XCTAssertEqual(
            stringOut,
            """
            P1
            100 100

            """
            +
            Array(
                repeating: String(repeating: "10", count: 35) + "\n" + String(repeating: "10", count: 15),
                count: 100
            )
            .joined(separator: "\n")
            +
            "\n"
        )
    }

}

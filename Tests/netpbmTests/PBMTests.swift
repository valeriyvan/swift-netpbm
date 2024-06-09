import XCTest
@testable import netpbm

final class PBMTests: XCTestCase {

    func testReadWrite() async throws {
        let iSeq = try PBMImageSequence(data:
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
            .data(using: .utf8)!
        )

        var images: [(cols: Int, rows: Int, pixels: [UInt8])] = []

        for try await imageBitSequence in iSeq {
            let pixels: [UInt8] = try await imageBitSequence.reduce(into: []) { $0.append(UInt8($1.rawValue))
            }
            images.append(
                (cols: imageBitSequence.width, rows: imageBitSequence.height, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 2)

        var first = images[0]
        XCTAssertEqual(first.cols, 5)
        XCTAssertEqual(first.rows, 4)
        XCTAssertEqual(first.pixels.count, 5 * 4)
        XCTAssertEqual(first.pixels, [0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1])

        var second = images[1]
        XCTAssertEqual(second.cols, 4)
        XCTAssertEqual(second.rows, 4)
        XCTAssertEqual(second.pixels.count, 4 * 4)
        XCTAssertEqual(second.pixels, [0,0,1,1, 0,0,1,1, 0,0,1,1, 0,0,1,1])

        let data = try PBMImageWriter.write(images: images, forcePlane: true)
        XCTAssertEqual(
            data,
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
            .data(using: .utf8)
        )

        let binary = try PBMImageWriter.write(images: images, forcePlane: false)

        // Now test that binary image could be read and it's the same
        let iSeqBinary = try PBMImageSequence(data: binary)

        images = []

        for try await imageBitSequence in iSeqBinary {
            let pixels: [UInt8] = try await imageBitSequence.reduce(into: []) { $0.append(UInt8($1.rawValue)) }
            let image = (cols: imageBitSequence.width, rows: imageBitSequence.height, pixels: pixels)
            images.append(image)
        }

        XCTAssertEqual(images.count, 2)

        first = images[0]
        XCTAssertEqual(first.cols, 5)
        XCTAssertEqual(first.rows, 4)
        XCTAssertEqual(first.pixels.count, 5 * 4)
        XCTAssertEqual(first.pixels, [0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1])

        second = images[1]
        XCTAssertEqual(second.cols, 4)
        XCTAssertEqual(second.rows, 4)
        XCTAssertEqual(second.pixels.count, 4 * 4)
        XCTAssertEqual(second.pixels, [0,0,1,1, 0,0,1,1, 0,0,1,1, 0,0,1,1])

    }

//    func testImagesFromStringMissingBitsThrows() async throws {
//        let imageSequence = try PBMImageSequence(data:
//            """
//            P1
//            # Image 1: 5x4 checkerboard pattern
//            5 4
//            0 1 0 1 0
//            1 0 1 0 1
//            0 1 0 1 0
//            1 0 1 0
//
//            """
//            .data(using: .utf8)!
//        )
//
//        var images: [(cols: Int, rows: Int, pixels: [UInt8])] = []
//
//        for try await imageBitSequence in imageSequence {
//            let pixels: [UInt8] = try await imageBitSequence.reduce(into: []) { $0.append(UInt8($1.rawValue)) }
//            let image = (cols: imageBitSequence.width, rows: imageBitSequence.height, pixels: pixels)
//            images.append(image)
//        }
//
//        XCTAssertEqual(images.count, 2)
//
//        first = images[0]
//        XCTAssertEqual(first.cols, 5)
//        XCTAssertEqual(first.rows, 4)
//        XCTAssertEqual(first.pixels.count, 5 * 4)
//        XCTAssertEqual(first.pixels, [0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1])
//
//        second = images[1]
//        XCTAssertEqual(second.cols, 4)
//        XCTAssertEqual(second.rows, 4)
//        XCTAssertEqual(second.pixels.count, 4 * 4)
//        XCTAssertEqual(second.pixels, [0,0,1,1, 0,0,1,1, 0,0,1,1, 0,0,1,1])
//
//        XCTAssertThrowsError(
//            try PBMImageSequence(data:
//                """
//                P1
//                # Image 1: 5x4 checkerboard pattern
//                5 4
//                0 1 0 1 0
//                1 0 1 0 1
//                0 1 0 1 0
//                1 0 1 0
//
//                """
//                .data(using: .utf8)!
//            )
//            .last
//            .map { try await $0.reduce(into: []) { $0.append(UInt8($1.rawValue)) } }
//        ) { error in
//            XCTAssertEqual(error as? PBM.PbmParseError, PBM.PbmParseError.unexpectedEndOfFile)
//        }

//        XCTAssertThrowsError(
//            try PBM.images(string:
//                """
//                P1
//                # Image 1: 5x4 checkerboard pattern
//                5 4
//                0 1 0 1 0
//                1 0 1 0 1
//                0 1 0 1 0
//                1 0 1 0
//
//                P1
//                # Image 2: 4x4 vertical stripes
//                4 4
//                0 0 1 1
//                0 0 1 1
//                0 0 1 1
//                0 0 1 1
//
//                """
//                          )
//        ) { error in
//            XCTAssertEqual(error as? PBM.PbmParseError, PBM.PbmParseError.junkWhereBitsShouldBe)
//        }
//    }

}

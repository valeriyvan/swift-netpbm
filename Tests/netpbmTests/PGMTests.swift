import XCTest
@testable import netpbm

final class PGMTests: XCTestCase {

    func testReadWrite() async throws {
        let iSeq = try PGMImageSequence(data:
            """
            P2
            # feep.ascii.pgm
            24 7
            15
            0 0  0  0  0  0  0  0  0 0  0  0  0  0  0  0  0 0  0  0  0  0  0  0
            0 3  3  3  3  0  0  7  7 7  7  0  0 11 11 11 11 0  0 15 15 15 15  0
            0 3  0  0  0  0  0  7  0 0  0  0  0 11  0  0  0 0  0 15  0  0 15  0
            0 3  3  3  0  0  0  7  7 7  0  0  0 11 11 11  0 0  0 15 15 15 15  0
            0 3  0  0  0  0  0  7  0 0  0  0  0 11  0  0  0 0  0 15  0  0  0  0
            0 3  0  0  0  0  0  7  7 7  7  0  0 11 11 11 11 0  0 15  0  0  0  0
            0 0  0  0  0  0  0  0  0 0  0  0  0  0  0  0  0 0  0  0  0  0  0  0

            """
            .data(using: .utf8)!
        )

        var images: [(cols: Int, rows: Int, maxValue: Gray, pixels: [Gray])] = []

        for try await imageGraySequence in iSeq {
            let pixels: [Gray] = try await imageGraySequence.reduce(into: [Gray]()) { $0.append($1) }
            images.append(
                (cols: imageGraySequence.width, rows: imageGraySequence.height, maxValue: imageGraySequence.maxValue, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 1)

        let first = images[0]
        XCTAssertEqual(first.cols, 24)
        XCTAssertEqual(first.rows, 7)
        XCTAssertEqual(first.pixels.count, 24 * 7)
        XCTAssertEqual(first.pixels, [
            0, 0,  0,  0,  0,  0,  0,  0,  0, 0,  0,  0,  0,  0,  0,  0,  0, 0,  0,  0,  0,  0,  0,  0,
            0, 3,  3,  3,  3,  0,  0,  7,  7, 7,  7,  0,  0, 11, 11, 11, 11, 0,  0, 15, 15, 15, 15,  0,
            0, 3,  0,  0,  0,  0,  0,  7,  0, 0,  0,  0,  0, 11,  0,  0,  0, 0,  0, 15,  0,  0, 15,  0,
            0, 3,  3,  3,  0,  0,  0,  7,  7, 7,  0,  0,  0, 11, 11, 11,  0, 0,  0, 15, 15, 15, 15,  0,
            0, 3,  0,  0,  0,  0,  0,  7,  0, 0,  0,  0,  0, 11,  0,  0,  0, 0,  0, 15,  0,  0,  0,  0,
            0, 3,  0,  0,  0,  0,  0,  7,  7, 7,  7,  0,  0, 11, 11, 11, 11, 0,  0, 15,  0,  0,  0,  0,
            0, 0,  0,  0,  0,  0,  0,  0,  0, 0,  0,  0,  0,  0,  0,  0,  0, 0,  0,  0,  0,  0,  0,  0
        ])

//        var second = images[1]
//        XCTAssertEqual(second.cols, 4)
//        XCTAssertEqual(second.rows, 4)
//        XCTAssertEqual(second.pixels.count, 4 * 4)
//        XCTAssertEqual(second.pixels, [0,0,1,1, 0,0,1,1, 0,0,1,1, 0,0,1,1])

        let data = try PGMImageWriter.write(images: images, forcePlane: true)
        XCTAssertEqual(
            data,
            """
            P2
            24 7
            15
            0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
            0 3 3 3 3 0 0 7 7 7 7 0 0 11 11 11 11 0 0 15 15 15 15 0
            0 3 0 0 0 0 0 7 0 0 0 0 0 11 0 0 0 0 0 15 0 0 15 0
            0 3 3 3 0 0 0 7 7 7 0 0 0 11 11 11 0 0 0 15 15 15 15 0
            0 3 0 0 0 0 0 7 0 0 0 0 0 11 0 0 0 0 0 15 0 0 0 0
            0 3 0 0 0 0 0 7 7 7 7 0 0 11 11 11 11 0 0 15 0 0 0 0
            0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0

            """
            .data(using: .utf8)
        )

//        let binary = try PGMImageWriter.write(images: images, forcePlane: false)
//
//        // Now test that binary image could be read and it's the same
//        let iSeqBinary = try PGMImageSequence(data: binary)
//
//        images = []
//
//        for try await imageGraySequence in iSeqBinary {
//            let pixels: [Gray] = try await imageGraySequence.reduce(into: [Gray]()) { $0.append($1) }
//            images.append(
//                (cols: imageGraySequence.width, rows: imageGraySequence.height, maxValue: imageGraySequence.maxValue, pixels: pixels)
//            )
//        }
//
//        XCTAssertEqual(images.count, 1)
//
//        first = images[0]
//        XCTAssertEqual(first.cols, 24)
//        XCTAssertEqual(first.rows, 7)
//        XCTAssertEqual(first.pixels.count, 24 * 7)
//        XCTAssertEqual(first.pixels, [
//            0, 0,  0,  0,  0,  0,  0,  0,  0, 0,  0,  0,  0,  0,  0,  0,  0, 0,  0,  0,  0,  0,  0,  0,
//            0, 3,  3,  3,  3,  0,  0,  7,  7, 7,  7,  0,  0, 11, 11, 11, 11, 0,  0, 15, 15, 15, 15,  0,
//            0, 3,  0,  0,  0,  0,  0,  7,  0, 0,  0,  0,  0, 11,  0,  0,  0, 0,  0, 15,  0,  0, 15,  0,
//            0, 3,  3,  3,  0,  0,  0,  7,  7, 7,  0,  0,  0, 11, 11, 11,  0, 0,  0, 15, 15, 15, 15,  0,
//            0, 3,  0,  0,  0,  0,  0,  7,  0, 0,  0,  0,  0, 11,  0,  0,  0, 0,  0, 15,  0,  0,  0,  0,
//            0, 3,  0,  0,  0,  0,  0,  7,  7, 7,  7,  0,  0, 11, 11, 11, 11, 0,  0, 15,  0,  0,  0,  0,
//            0, 0,  0,  0,  0,  0,  0,  0,  0, 0,  0,  0,  0,  0,  0,  0,  0, 0,  0,  0,  0,  0,  0,  0
//        ])
    }

}

import XCTest
@testable import netpbm
import Algorithms // chunks

final class PAMTests: XCTestCase {

    func testReadPBMPlain() async throws {
        let iSeq = try PAMImageSequence(data:
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

        var images: [(cols: Int, rows: Int, pixels: [Sample])] = []

        for try await imageElementSequence in iSeq {
            let pixels: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append(contentsOf: $1)
            }
            images.append(
                (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 2)

        let first = images[0]
        XCTAssertEqual(first.cols, 5)
        XCTAssertEqual(first.rows, 4)
        XCTAssertEqual(first.pixels.count, 5 * 4)
        XCTAssertEqual(first.pixels, [1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0])

        let second = images[1]
        XCTAssertEqual(second.cols, 4)
        XCTAssertEqual(second.rows, 4)
        XCTAssertEqual(second.pixels.count, 4 * 4)
        XCTAssertEqual(second.pixels, [1,1,0,0, 1,1,0,0, 1,1,0,0, 1,1,0,0])
    }

    func testReadWritePBMMixedPlainBinary() async throws {
        let iSeq = try PAMImageSequence(data:
            """
            P4
            # Image 1: 5x4 checkerboard pattern
            5 4

            """
            .data(using: .utf8)!
            +
            Data([0b01010000, 0b10101000, 0b01010000, 0b10101000] as [UInt8])
            +
            """
            P4
            # Image 2: 4x4 vertical stripes
            4 4

            """
            .data(using: .utf8)!
            +
            Data([0b00110000, 0b00110000, 0b00110000, 0b00110000] as [UInt8])
        )

        var images: [(cols: Int, rows: Int, pixels: [Sample])] = []

        for try await imageElementSequence in iSeq {
            let pixels: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append(contentsOf: $1)
            }
            images.append(
                (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 2)

        var first = images[0]
        XCTAssertEqual(first.cols, 5)
        XCTAssertEqual(first.rows, 4)
        XCTAssertEqual(first.pixels.count, 5 * 4)
        XCTAssertEqual(first.pixels, [1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0])

        var second = images[1]
        XCTAssertEqual(second.cols, 4)
        XCTAssertEqual(second.rows, 4)
        XCTAssertEqual(second.pixels.count, 4 * 4)
        XCTAssertEqual(second.pixels, [1,1,0,0, 1,1,0,0, 1,1,0,0, 1,1,0,0])

        let pamImages: [(pam: Pam, pixels: [[[Sample]]])] = images.map { image in
            var pam = Pam()
            pam.width = Int32(image.cols)
            pam.height = Int32(image.rows)
            pam.depth = 1
            pam.maxVal = 1
            pam.format = PBM_FORMAT
            pam.plainformat = true
            return (
                pam: pam,
                pixels: image.pixels.map{ [$0] }.chunks(ofCount: image.cols).map(Array.init)
            )
        }

        let data = try PAMImageWriter.write(images: pamImages)
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

        let pamBinaryImages: [(pam: Pam, pixels: [[[Sample]]])] = pamImages.map { image in
            var pam = image.pam
            pam.format = RPBM_FORMAT
            pam.plainformat = false
            return (
                pam: pam,
                pixels: image.pixels
            )
        }

        let binary = try PAMImageWriter.write(images: pamBinaryImages)

        // Now test that binary image could be read and it's the same
        let iSeqBinary = try PAMImageSequence(data: binary)

        images = []

        for try await imageElementSequence in iSeqBinary {
            let pixels: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append($1.first!) }
            let image = (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            images.append(image)
        }

        XCTAssertEqual(images.count, 2)

        first = images[0]
        XCTAssertEqual(first.cols, 5)
        XCTAssertEqual(first.rows, 4)
        XCTAssertEqual(first.pixels.count, 5 * 4)
        XCTAssertEqual(first.pixels, [1,0,1,0,1, 0,1,0,1,0, 1,0,1,0,1, 0,1,0,1,0])

        second = images[1]
        XCTAssertEqual(second.cols, 4)
        XCTAssertEqual(second.rows, 4)
        XCTAssertEqual(second.pixels.count, 4 * 4)
        XCTAssertEqual(second.pixels, [1,1,0,0, 1,1,0,0, 1,1,0,0, 1,1,0,0])
    }

    func testPGMReadWrite() async throws {
        let iSeq = try PAMImageSequence(data:
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

        var images: [(cols: Int, rows: Int, pixels: [Sample])] = []

        for try await imageElementSequence in iSeq {
            let pixels: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append(contentsOf: $1)
            }
            images.append(
                (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 1)

        var first = images[0]
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

        let pamPGMPlainImages: [(pam: Pam, pixels: [[[Sample]]])] = images.map { image in
            var pam = Pam()
            pam.width = Int32(image.cols)
            pam.height = Int32(image.rows)
            pam.depth = 1
            pam.maxVal = 15
            pam.format = PGM_FORMAT
            pam.plainformat = true
            return (
                pam: pam,
                pixels: image.pixels.map{ [$0] }.chunks(ofCount: image.cols).map(Array.init)
            )
        }

        let data = try PAMImageWriter.write(images: pamPGMPlainImages)

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

        let pamPGMBinaryImages: [(pam: Pam, pixels: [[[Sample]]])] = pamPGMPlainImages.map { image in
            var pam = image.pam
            pam.format = RPGM_FORMAT
            pam.plainformat = false
            return (
                pam: pam,
                pixels: image.pixels
            )
        }

        let binary = try PAMImageWriter.write(images: pamPGMBinaryImages)
        // Now test that binary image could be read and it's the same
        let iSeqBinary = try PAMImageSequence(data: binary)

        images = []

        for try await imageElementSequence in iSeqBinary {
            let pixels: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append(contentsOf: $1)
            }
            images.append(
                (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 1)

        first = images[0]
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
    }
}


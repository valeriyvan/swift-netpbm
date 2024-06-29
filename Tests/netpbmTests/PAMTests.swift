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

    func testPPMReadWrite() async throws {
        let iSeq = try PAMImageSequence(data:
            """
            P3
            2 3
            255
            255 0 0   0 255 0
            0 255 0   0 255 0
            0 0 255   255 255 255

            """
            .data(using: .utf8)!
        )

        var images: [(cols: Int, rows: Int, pixels: [[Sample]])] = []

        for try await imageElementSequence in iSeq {
            let colors: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append(contentsOf: $1)
            }
            let pixels = colors.chunks(ofCount: 3).map(Array.init)
            images.append(
                (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 1)

        var first = images[0]
        XCTAssertEqual(first.cols, 2)
        XCTAssertEqual(first.rows, 3)
        XCTAssertEqual(first.pixels.count, 2 * 3)
        XCTAssertTrue(first.pixels.allSatisfy { $0.count == 3 })
        XCTAssertEqual(
            first.pixels,
            [
                [Sample(255), Sample(0),   Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(0),   Sample(255)],
                [Sample(255), Sample(255), Sample(255)]
            ]
        )

        let pamPPMPlainImages: [(pam: Pam, pixels: [[[Sample]]])] = images.map { image in
            var pam = Pam()
            pam.width = Int32(image.cols)
            pam.height = Int32(image.rows)
            pam.depth = 3
            pam.maxVal = 255
            pam.format = PPM_FORMAT
            pam.plainformat = true
            return (
                pam: pam,
                pixels: image.pixels.chunks(ofCount: image.cols).map(Array.init)
            )
        }

        let data = try PAMImageWriter.write(images: pamPPMPlainImages)
        XCTAssertEqual(
            data,
            """
            P3
            2 3
            255
            255 0 0 0 255 0
            0 255 0 0 255 0
            0 0 255 255 255 255

            """
            .data(using: .utf8)
        )

        let pamPPMBinaryImages: [(pam: Pam, pixels: [[[Sample]]])] = pamPPMPlainImages.map { image in
            var pam = image.pam
            pam.format = RPPM_FORMAT
            pam.plainformat = false
            return (
                pam: pam,
                pixels: image.pixels
            )
        }

        let binary = try PAMImageWriter.write(images: pamPPMBinaryImages)
        // Now test that binary image could be read and it's the same
        let iSeqBinary = try PAMImageSequence(data: binary)

        images = []

        for try await imageElementSequence in iSeqBinary {
            let colors: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append(contentsOf: $1)
            }
            let pixels = colors.chunks(ofCount: 3).map(Array.init)
            images.append(
                (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            )
        }

        first = images[0]
        XCTAssertEqual(first.cols, 2)
        XCTAssertEqual(first.rows, 3)
        XCTAssertEqual(first.pixels.count, 2 * 3)
        XCTAssertEqual(
            first.pixels,
            [
                [Sample(255), Sample(0),   Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(0),   Sample(255)],
                [Sample(255), Sample(255), Sample(255)]
            ]
        )
    }

    func testPAMReadWrite() async throws {
        let iSeq = try PAMImageSequence(data:
            """
            P7
            WIDTH 3
            HEIGHT 5
            DEPTH 3
            MAXVAL 255
            TUPLTYPE RGB
            ENDHDR

            """
            .data(using: .utf8)!
            + 
            Data(
                [255,0,0, 0,255,0, 0,0,255,
                 0,255,255, 128,128,128, 255,165,0,
                 255,192,203, 128,128,0, 0,0,128,
                 255,69,0, 75,0,130, 72,61,139,
                 106,90,205, 0,206,209, 123,104,238
                ] as [UInt8]
            )
        )

        var images: [(cols: Int, rows: Int, pixels: [[Sample]])] = []

        for try await imageElementSequence in iSeq {
            let colors: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append(contentsOf: $1)
            }
            let pixels = colors.chunks(ofCount: 3).map(Array.init)
            images.append(
                (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            )
        }

        XCTAssertEqual(images.count, 1)

        var first = images[0]
        XCTAssertEqual(first.cols, 3)
        XCTAssertEqual(first.rows, 5)
        XCTAssertEqual(first.pixels.count, 3 * 5)
        XCTAssertTrue(first.pixels.allSatisfy { $0.count == 3 })
        XCTAssertEqual(
            first.pixels,
            [
                [Sample(255), Sample(0), Sample(0)],  [Sample(0), Sample(255), Sample(0)],  [Sample(0), Sample(0), Sample(255)],
                [Sample(0), Sample(255), Sample(255)],  [Sample(128), Sample(128), Sample(128)],  [Sample(255), Sample(165), Sample(0)],
                [Sample(255), Sample(192), Sample(203)],  [Sample(128), Sample(128), Sample(0)],  [Sample(0), Sample(0), Sample(128)],
                [Sample(255), Sample(69), Sample(0)],  [Sample(75), Sample(0), Sample(130)],  [Sample(72), Sample(61), Sample(139)],
                [Sample(106), Sample(90), Sample(205)],  [Sample(0), Sample(206), Sample(209)],  [Sample(123), Sample(104), Sample(238)]
            ]
        )

        /*
        let pamPPMPlainImages: [(pam: Pam, pixels: [[[Sample]]])] = images.map { image in
            var pam = Pam()
            pam.width = Int32(image.cols)
            pam.height = Int32(image.rows)
            pam.depth = 3
            pam.maxVal = 255
            pam.format = PPM_FORMAT
            pam.plainformat = true
            return (
                pam: pam,
                pixels: image.pixels.chunks(ofCount: image.cols).map(Array.init)
            )
        }

        let data = try PAMImageWriter.write(images: pamPPMPlainImages)
        XCTAssertEqual(
            data,
            """
            P3
            2 3
            255
            255 0 0 0 255 0
            0 255 0 0 255 0
            0 0 255 255 255 255

            """
            .data(using: .utf8)
        )

        let pamPPMBinaryImages: [(pam: Pam, pixels: [[[Sample]]])] = pamPPMPlainImages.map { image in
            var pam = image.pam
            pam.format = RPPM_FORMAT
            pam.plainformat = false
            return (
                pam: pam,
                pixels: image.pixels
            )
        }

        let binary = try PAMImageWriter.write(images: pamPPMBinaryImages)
        // Now test that binary image could be read and it's the same
        let iSeqBinary = try PAMImageSequence(data: binary)

        images = []

        for try await imageElementSequence in iSeqBinary {
            let colors: [Sample] = try await imageElementSequence.reduce(into: []) { $0.append(contentsOf: $1)
            }
            let pixels = colors.chunks(ofCount: 3).map(Array.init)
            images.append(
                (cols: imageElementSequence.width, rows: imageElementSequence.height, pixels: pixels)
            )
        }

        first = images[0]
        XCTAssertEqual(first.cols, 2)
        XCTAssertEqual(first.rows, 3)
        XCTAssertEqual(first.pixels.count, 2 * 3)
        XCTAssertEqual(
            first.pixels,
            [
                [Sample(255), Sample(0),   Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(255), Sample(0)],
                [Sample(0),   Sample(0),   Sample(255)],
                [Sample(255), Sample(255), Sample(255)]
            ]
        )
         */
    }

}


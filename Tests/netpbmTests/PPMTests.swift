import Foundation

import XCTest
@testable import netpbm

final class PPMTests: XCTestCase {

    func testReadWrite() async throws {
        let iSeq = try PPMImageSequence(data:
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

        var images: [(cols: Int, rows: Int,  maxValue: Pixval, pixels: [Pixel])] = []

        for try await imageSequence in iSeq {
            let pixels: [Pixel] = try await imageSequence.reduce(into: [Pixel]()) { $0.append($1) }
            images.append(
                (cols: imageSequence.width, rows: imageSequence.height, maxValue: imageSequence.maxValue, pixels: pixels)
            )
        }

        print(images[0].pixels)

        XCTAssertEqual(images.count, 1)

        var first = images[0]
        XCTAssertEqual(first.cols, 2)
        XCTAssertEqual(first.rows, 3)
        XCTAssertEqual(first.pixels.count, 2 * 3)
        XCTAssertEqual(
            first.pixels,
            [
                Pixel(r: 255, g: 0, b: 0),
                Pixel(r: 0, g: 255, b: 0),
                Pixel(r: 0, g: 255, b: 0),
                Pixel(r: 0, g: 255, b: 0),
                Pixel(r: 0, g: 0, b: 255), 
                Pixel(r: 255, g: 255, b: 255)
            ]
        )

        let data = try PPMImageWriter.write(images: images, forcePlane: true)
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

        let binary = try PPMImageWriter.write(images: images, forcePlane: false)
        // Now test that binary image could be read and it's the same
        let iSeqBinary = try PPMImageSequence(data: binary)

        images = []

        for try await imagePixelSequence in iSeqBinary {
            let pixels: [Pixel] = try await imagePixelSequence.reduce(into: [Pixel]()) { $0.append($1) }
            images.append(
                (cols: imagePixelSequence.width, rows: imagePixelSequence.height, maxValue: imagePixelSequence.maxValue, pixels: pixels)
            )
        }

        first = images[0]
        XCTAssertEqual(first.cols, 2)
        XCTAssertEqual(first.rows, 3)
        XCTAssertEqual(first.pixels.count, 2 * 3)
        XCTAssertEqual(
            first.pixels,
            [
                Pixel(r: 255, g: 0, b: 0),
                Pixel(r: 0, g: 255, b: 0),
                Pixel(r: 0, g: 255, b: 0),
                Pixel(r: 0, g: 255, b: 0),
                Pixel(r: 0, g: 0, b: 255),
                Pixel(r: 255, g: 255, b: 255)
            ]
        )
    }

}

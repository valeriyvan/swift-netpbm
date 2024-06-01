import XCTest
@testable import netpbm

final class URLTests: XCTestCase {

    func testRoundTrip() throws {
        let string = "Hello, World!"
        let url = try XCTUnwrap(URL(dataUrlFromString: string))
        let content = try String(contentsOf: url)
        XCTAssertEqual(string, content)
    }

    func testValidString() {
        let testString = "Hello, world!"
        let expectedBase64 = "SGVsbG8sIHdvcmxkIQ=="
        let expectedURLString = "data:text/plain;charset=UTF-8;base64,\(expectedBase64)"

        if let url = URL(dataUrlFromString: testString) {
            XCTAssertEqual(url.absoluteString, expectedURLString)
        } else {
            XCTFail("URL creation failed for a valid string.")
        }
    }

    func testEmptyString() {
        let testString = ""
        let expectedBase64 = ""
        let expectedURLString = "data:text/plain;charset=UTF-8;base64,\(expectedBase64)"

        if let url = URL(dataUrlFromString: testString) {
            XCTAssertEqual(url.absoluteString, expectedURLString)
        } else {
            XCTFail("URL creation failed for an empty string.")
        }
    }

    func testSpecialCharacters() {
        let testString = "こんにちは世界"
        let expectedBase64 = "44GT44KT44Gr44Gh44Gv5LiW55WM"
        let expectedURLString = "data:text/plain;charset=UTF-8;base64,\(expectedBase64)"

        if let url = URL(dataUrlFromString: testString) {
            XCTAssertEqual(url.absoluteString, expectedURLString)
        } else {
            XCTFail("URL creation failed for a string with special characters.")
        }
    }

}

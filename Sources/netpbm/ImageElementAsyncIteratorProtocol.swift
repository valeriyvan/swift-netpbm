import Foundation

// A type that provides asynchronous, sequential, iterated access to the elements of an image.
// An element of an image can be a bit, a single or multiple byte word representing pixel intensity,
// or a pixel defining the red, green, and blue colors, depending on the image format.

public protocol ImageElementAsyncIteratorProtocol: AsyncIteratorProtocol {
    associatedtype Element

    var currentRow: Int { get set }
    var currentElementIndex: Int { get set }
    var row: [Element] { get set }
    var cols: Int32 { get }
    var rows: Int32 { get }
    var format: Int32 { get }
    var file: UnsafeMutablePointer<FILE> { get }

    mutating func readRow() throws -> [Element]
}

extension ImageElementAsyncIteratorProtocol {
    public mutating func next() async throws -> Element? {
        if currentRow == -1 {
            row = try readRow()
            currentRow = 0
            currentElementIndex = 0
            defer { currentElementIndex += 1 }
            return row[currentElementIndex]
        } else if currentElementIndex < row.count {
            defer { currentElementIndex += 1 }
            return row[currentElementIndex]
        } else if currentRow < rows - 1 {
            row = try readRow()
            currentRow += 1
            currentElementIndex = 0
            defer { currentElementIndex += 1 }
            return row[currentElementIndex]
        }
        return nil
    }
}

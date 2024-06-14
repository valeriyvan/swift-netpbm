import Foundation

public protocol ImageElementAsyncSequence: AsyncSequence {
    associatedtype Element
    associatedtype AsyncIterator = ImageElementAsyncIteratorProtocol where AsyncIterator.Element == Element

    var width: Int { get }
    var height: Int { get }

    var file: UnsafeMutablePointer<FILE> { get }
    var cols: Int32 { get }
    var rows: Int32 { get }
    var format: Int32 { get }

    init(file: UnsafeMutablePointer<FILE>) throws
}

// TODO: would be nice to provide default implementation for required initializer but that looks impossible
// extension ImageElementAsyncSequence {
//     public init(file: UnsafeMutablePointer<FILE>) throws {
//         self.file = file
//         (cols, rows, format) = try _pbm_readpbminit(file) // TODO: test with broken header
//     }
// }

import Foundation

public protocol ImageAsyncIteratorProtocol: AsyncIteratorProtocol {
    associatedtype Element = ImageElementAsyncSequence

    var file: UnsafeMutablePointer<FILE> { get }

    init(file: UnsafeMutablePointer<FILE>)
}

// TODO: would be nice avoidong repeating following function
// extension ImageAsyncIteratorProtocol {
//     mutating func next() async throws -> (some ImageElementAsyncSequence)? {
//         let eof = try _pm_nextimage(file)
//         guard !eof else { return nil }
//         return try (any ImageElementAsyncSequence)(file: file)
//     }
// }

import Foundation

// A type that provides asynchronous, sequential, iterated access to multiple images in a file.

public protocol ImageAsyncSequence: AsyncSequence {
    associatedtype Element
    associatedtype ImageAsyncIterator: AsyncIteratorProtocol where ImageAsyncIterator.Element == Element

    var file: UnsafeMutablePointer<FILE> { get }
    var fileWrapper: FileWrapper { get set }

    init(fileWrapper: FileWrapper) throws

    func makeAsyncIterator() -> ImageAsyncIterator
}

extension ImageAsyncSequence {
    var file: UnsafeMutablePointer<FILE> { fileWrapper.file }

    public init(data: Data) throws {
        let (file, buffer) = try data.withUnsafeBytes {
            // Make a copy of $0 otherwise file operations will read deallocated memory
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: $0.count, alignment: MemoryLayout<UInt8>.alignment)
            buffer.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
            guard let file: UnsafeMutablePointer<FILE> = fmemopen(buffer, $0.count, "r") else {
                throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
            }
            return (file, buffer)
        }
        try self.init(fileWrapper: FileWrapper(file: file, buffer: buffer))
    }

    public init(pathname: String) throws {
        guard let file: UnsafeMutablePointer<FILE> = fopen(pathname, "r") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        try self.init(fileWrapper: FileWrapper(file: file))
    }
}

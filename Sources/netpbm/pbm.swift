import Foundation
import libnetpbm

extension String: Error {} // TODO: REMOVE!!!

var argc: Int32 = 1;
var `nil`: CChar = 0
var argv: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(&`nil`), nil]

public struct PBM {

    public init() {
        pbm_init(&argc, &argv)
    }

    // C ordering for pixels, row by row
    public static func readFirstImage(filename: String) throws -> (rows: Int, cols: Int, pixels: [UInt8]) {
        guard let file: UnsafeMutablePointer<FILE> = fopen(filename, "r") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        defer { fclose(file) }
        return try PBM.readImage(file: file)
    }

    public static func readFirstImage(string: String) throws -> (rows: Int, cols: Int, pixels: [UInt8]) {
        try string.withCString {
            guard let file: UnsafeMutablePointer<FILE> = fmemopen(UnsafeMutableRawPointer(mutating: $0), strlen($0), "r") else {
                throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
            }
            defer { fclose(file) }
            return try PBM.readImage(file: file)
        }
    }

    public static func images(filename: String) throws -> [(rows: Int, cols: Int, pixels: [UInt8])] {
        guard let file: UnsafeMutablePointer<FILE> = fopen(filename, "r") else {
            throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
        }
        defer { fclose(file) }
        return try PBM.images(file: file)
    }

    public static func images(string: String) throws -> [(rows: Int, cols: Int, pixels: [UInt8])] {
        try string.withCString {
            guard let file: UnsafeMutablePointer<FILE> = fmemopen(UnsafeMutableRawPointer(mutating: $0), strlen($0), "r") else {
                throw NSError(domain: URLError.errorDomain, code: URLError.cannotOpenFile.rawValue)
            }
            defer { fclose(file) }
            return try PBM.images(file: file)
        }
    }

    private static func images(file: UnsafeMutablePointer<FILE>) throws -> [(rows: Int, cols: Int, pixels: [UInt8])] {
        var images: [(rows: Int, cols: Int, pixels: [UInt8])] = []
        while true {
            var eof: Int32 = 0
            pm_nextimage(file, &eof)
            guard eof == 0 else { break }
            images.append(try PBM.readImage(file: file))
        }
        return images
    }

    // Leaves file open ready to read next image from the same file
    private static func readImage(file: UnsafeMutablePointer<FILE>) throws -> (rows: Int, cols: Int, pixels: [UInt8]) {
        var cols: Int32 = 0
        var rows: Int32 = 0
        guard let bits: UnsafeMutablePointer<UnsafeMutablePointer<bit>?> = pbm_readpbm(file, &cols, &rows) else {
            throw "Error reading file" // TODO: !!!
        }
        let capacity = Int(rows * cols)
        let pixels: [UInt8] = try .init(unsafeUninitializedCapacity: capacity) { buffer, initializedCount in
            for row in 0..<Int(rows) {
                for col in 0..<Int(cols) {
                    guard let aRow = bits[row] else {
                        throw "Internal error or broken file"
                    }
                    buffer[row * Int(cols) + Int(col)] = aRow[col]
                }
            }
            initializedCount = capacity
        }
        pbm_freearray(bits, rows)
        return (rows: Int(rows), cols: Int(cols), pixels: pixels)
    }

}

//private func pbm_allocarray(_ cols: Int32, _ rows: Int32) -> UnsafeMutablePointer<UnsafeMutablePointer<bit>?> {
//    UnsafeMutablePointer<UnsafeMutablePointer<bit>?>(bitPattern:
//        UInt(bitPattern: pm_allocarray(cols, rows, Int32(MemoryLayout<CChar>.stride)))
//    )!
//}

private func pbm_freearray(_ bits: UnsafeMutablePointer<UnsafeMutablePointer<bit>?>, _ rows: Int32) {
    pm_freearray(UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>(bitPattern: UInt(bitPattern: bits)), rows)
}

private func pbm_freerow(_ bitrow: UnsafeMutablePointer<CChar>) {
    pm_freerow(bitrow)
}

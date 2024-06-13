import Foundation

// Closes file and deallocates buffer on deinit.
class FileWrapper {
    let file: UnsafeMutablePointer<FILE>
    let buffer: UnsafeMutableRawPointer?

    init(file: UnsafeMutablePointer<FILE>, buffer: UnsafeMutableRawPointer? = nil) {
        self.file = file
        self.buffer = buffer
    }

    deinit {
        if fclose(file) == EOF {
            print("Error \(errno) closing file")
        }
        buffer?.deallocate()
    }
}

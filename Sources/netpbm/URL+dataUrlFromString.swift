import Foundation

extension URL {
    init?(dataUrlFromString string: String) {
        guard let data = string.data(using: .utf8), 
              let url = URL(string: "data:text/plain;charset=UTF-8;base64,\(data.base64EncodedString())")
        else {
            return nil
        }
        self = url
    }
}

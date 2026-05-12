import Foundation

public enum IPCCoder {
    public static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.dataEncodingStrategy = .base64
        return enc
    }()

    public static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        dec.dataDecodingStrategy = .base64
        return dec
    }()
}

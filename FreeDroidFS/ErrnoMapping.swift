import Foundation
import FreeDroidDomain

enum ErrnoMapping {
    static func errno(for error: TransportError) -> Int32 {
        switch error {
        case .notConnected: ENODEV
        case .unauthorized: EACCES
        case .timeout: ETIMEDOUT
        case .ioFailure: EIO
        case .notFound: ENOENT
        case .alreadyExists: EEXIST
        case .unsupported: ENOTSUP
        case .cancelled: ECANCELED
        }
    }
}

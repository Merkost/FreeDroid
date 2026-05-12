import FileProvider
import Foundation
@_exported import FreeDroidDomain

public enum ProviderError {
    public static func map(_ error: TransportError) -> NSError {
        let code: NSFileProviderError.Code
        switch error {
        case .notConnected:            code = .serverUnreachable
        case .notFound:                code = .noSuchItem
        case .alreadyExists:           code = .filenameCollision
        case .unsupported:             code = .noSuchItem
        case .unauthorized:            code = .notAuthenticated
        case .ioFailure:               code = .cannotSynchronize
        case .timeout:                 code = .serverUnreachable
        case .cancelled:               code = .cannotSynchronize
        }
        return NSFileProviderError(code).toNSError(message: String(describing: error))
    }
}

private extension NSFileProviderError {
    func toNSError(message: String) -> NSError {
        let underlying = (self as NSError)
        return NSError(
            domain: underlying.domain,
            code: underlying.code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

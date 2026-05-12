import Foundation
import FreeDroidDomain

public enum IPCResponse: Codable, Sendable {
    case entries([RemoteEntry])
    case entry(RemoteEntry)
    case data(Data)
    case empty
    case failure(IPCError)
}

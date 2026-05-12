import Foundation
import FreeDroidDomain

public enum IPCRequest: Codable, Sendable {
    case list(deviceID: DeviceID, path: RemotePath)
    case stat(deviceID: DeviceID, path: RemotePath)
    case read(deviceID: DeviceID, path: RemotePath, offset: Int64, length: Int)
    case write(deviceID: DeviceID, path: RemotePath, data: Data, offset: Int64)
    case fetchToFile(deviceID: DeviceID, path: RemotePath, destination: String)
    case uploadFromFile(deviceID: DeviceID, source: String, path: RemotePath)
    case mkdir(deviceID: DeviceID, path: RemotePath)
    case remove(deviceID: DeviceID, path: RemotePath)
    case rename(deviceID: DeviceID, from: RemotePath, to: RemotePath)
}

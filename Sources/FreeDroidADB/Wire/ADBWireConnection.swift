import Foundation
import Network

public actor ADBWireConnection {
    private let connection: NWConnection
    private var receiveBuffer: Data = Data()

    public static func connect(host: String = "127.0.0.1", port: UInt16 = 5037) async throws -> ADBWireConnection {
        let conn = ADBWireConnection(host: host, port: port)
        try await conn.waitForReady()
        return conn
    }

    private init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        connection = NWConnection(to: endpoint, using: .tcp)
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func waitForReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task { await self.clearStateHandler() }
                    continuation.resume()
                case .failed(let err):
                    Task { await self.clearStateHandler() }
                    continuation.resume(throwing: err)
                case .cancelled:
                    Task { await self.clearStateHandler() }
                    continuation.resume(throwing: ADBWireError.socketClosed)
                default:
                    break
                }
            }
        }
    }

    private func clearStateHandler() {
        connection.stateUpdateHandler = nil
    }

    public nonisolated func cancel() {
        Task { await self._cancel() }
    }

    private func _cancel() {
        connection.cancel()
    }

    public func writeHostMessage(_ message: String) async throws {
        let hex = String(format: "%04x", message.utf8.count)
        let frame = (hex + message).data(using: .utf8)!
        try await send(frame)
    }

    public func readOKAY() async throws {
        let header = try await readBytes(4)
        let tag = String(decoding: header, as: UTF8.self)
        if tag == "OKAY" { return }
        if tag == "FAIL" {
            let lenHex = try await readBytes(4)
            let lenStr = String(decoding: lenHex, as: UTF8.self)
            let len = Int(lenStr, radix: 16) ?? 0
            let msgData = try await readBytes(len)
            throw ADBWireError.okayExpected(got: String(decoding: msgData, as: UTF8.self))
        }
        throw ADBWireError.okayExpected(got: tag)
    }

    public func readU32LE() async throws -> UInt32 {
        let bytes = try await readBytes(4)
        return bytes.readU32LE()
    }

    public func readString(_ length: Int) async throws -> String {
        let data = try await readBytes(length)
        return String(decoding: data, as: UTF8.self)
    }

    public func readBytes(_ count: Int) async throws -> Data {
        while receiveBuffer.count < count {
            let chunk = try await receiveOnce()
            receiveBuffer.append(chunk)
        }
        let result = Data(receiveBuffer.prefix(count))
        receiveBuffer = Data(receiveBuffer.dropFirst(count))
        return result
    }

    public func receiveAvailable() async throws -> Data {
        if !receiveBuffer.isEmpty {
            let drained = receiveBuffer
            receiveBuffer = Data()
            return drained
        }
        do {
            return try await receiveOnce()
        } catch ADBWireError.socketClosed {
            return Data()
        }
    }

    public func sendRaw(_ data: Data) async throws {
        try await send(data)
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { err in
                if let err {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveOnce() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, err in
                if let err {
                    continuation.resume(throwing: err)
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: ADBWireError.socketClosed)
                    return
                }
                continuation.resume(throwing: ADBWireError.socketClosed)
            }
        }
    }
}

import Foundation

public struct ShellResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public actor ADBShellClient {
    private let host: String
    private let port: UInt16
    private let features: Set<String>

    public init(host: String = "127.0.0.1", port: UInt16 = 5037, features: Set<String> = []) {
        self.host = host
        self.port = port
        self.features = features
    }

    public func run(serial: String, command: String) async throws -> ShellResult {
        let conn = try await ADBWireConnection.connect(host: host, port: port)
        defer { conn.cancel() }

        try await conn.writeHostMessage("host:transport:\(serial)")
        try await conn.readOKAY()

        if features.contains("shell_v2") {
            try await conn.writeHostMessage("shell,v2,raw:\(command)")
            try await conn.readOKAY()
            return try await readShellV2Output(conn: conn)
        } else {
            try await conn.writeHostMessage("shell:\(command)")
            try await conn.readOKAY()
            return try await readShellV1Output(conn: conn)
        }
    }

    private func readShellV1Output(conn: ADBWireConnection) async throws -> ShellResult {
        var stdout = Data()
        while true {
            let chunk = try await conn.receiveAvailable()
            if chunk.isEmpty { break }
            stdout.append(chunk)
        }
        return ShellResult(
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: "",
            exitCode: 0
        )
    }

    private func readShellV2Output(conn: ADBWireConnection) async throws -> ShellResult {
        var stdoutParts: [Data] = []
        var stderrParts: [Data] = []
        var exitCode: Int32 = 0

        while true {
            let typeByte = try await conn.readBytes(1)
            let msgType = typeByte[0]
            let lengthData = try await conn.readBytes(4)
            let length = lengthData.readU32LE()

            switch msgType {
            case 1:
                let data = try await conn.readBytes(Int(length))
                stdoutParts.append(data)
            case 2:
                let data = try await conn.readBytes(Int(length))
                stderrParts.append(data)
            case 3:
                let data = try await conn.readBytes(Int(length))
                exitCode = Int32(bitPattern: data.readU32LE())
                let stdoutData = stdoutParts.reduce(Data(), +)
                let stderrData = stderrParts.reduce(Data(), +)
                return ShellResult(
                    stdout: String(decoding: stdoutData, as: UTF8.self),
                    stderr: String(decoding: stderrData, as: UTF8.self),
                    exitCode: exitCode
                )
            default:
                throw ADBWireError.framingViolation(
                    context: "shell_v2 unknown msgType",
                    firstBytes: [msgType]
                )
            }
        }
    }
}

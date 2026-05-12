import Foundation

public protocol ADBRunner: Sendable {
    func run(_ command: ADBCommand, timeout: Duration) async throws -> ADBProcessOutput
    func runStreaming(
        _ command: ADBCommand,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32
}

public struct ADBProcessOutput: Hashable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var combinedOutput: String {
        stdout + (stderr.isEmpty ? "" : "\n" + stderr)
    }
}

public enum ADBRunnerError: Error, Sendable, Equatable {
    case nonZeroExit(code: Int32, stderr: String)
    case spawnFailed(message: String)
    case timeout
}

public actor LiveADBRunner: ADBRunner {
    private let binary: URL
    private let port: Int

    public init(binary: URL, port: Int = 5037) {
        self.binary = binary
        self.port = port
    }

    public func run(_ command: ADBCommand, timeout: Duration = .seconds(30)) async throws -> ADBProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = command.arguments
            process.environment = serverEnvironment()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let timeoutTask = Task {
                try await Task.sleep(for: timeout)
                if process.isRunning {
                    process.terminate()
                    continuation.resume(throwing: ADBRunnerError.timeout)
                }
            }

            process.terminationHandler = { proc in
                timeoutTask.cancel()
                let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let output = ADBProcessOutput(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
                if proc.terminationStatus != 0 {
                    continuation.resume(throwing: ADBRunnerError.nonZeroExit(code: proc.terminationStatus, stderr: stderr))
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                continuation.resume(throwing: ADBRunnerError.spawnFailed(message: error.localizedDescription))
            }
        }
    }

    public func runStreaming(
        _ command: ADBCommand,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = command.arguments
            process.environment = serverEnvironment()

            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = Pipe()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in chunk.split(separator: "\n") {
                    onLine(String(line))
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ADBRunnerError.spawnFailed(message: error.localizedDescription))
            }
        }
    }

    private func serverEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ANDROID_ADB_SERVER_PORT"] = String(port)
        return env
    }
}

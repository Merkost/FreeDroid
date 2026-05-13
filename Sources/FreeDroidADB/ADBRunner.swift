import Foundation
import os

public protocol ADBRunner: Sendable {
    func run(_ command: ADBCommand, timeout: Duration) async throws -> ADBProcessOutput
    func runWithStdin(_ command: ADBCommand, stdin: String, timeout: Duration) async throws -> ADBProcessOutput
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

            let resolver = ContinuationResolver(continuation: continuation)
            let buffer = StreamingBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { return }
                buffer.append(chunk)
            }

            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                if process.isRunning {
                    process.terminate()
                    resolver.fail(ADBRunnerError.timeout)
                }
            }

            process.terminationHandler = { proc in
                timeoutTask.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                if let tail = try? stdoutPipe.fileHandleForReading.readToEnd() {
                    buffer.append(tail)
                }
                let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stdout = String(data: buffer.snapshot(), encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let output = ADBProcessOutput(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
                if proc.terminationStatus != 0 {
                    resolver.fail(ADBRunnerError.nonZeroExit(code: proc.terminationStatus, stderr: stderr))
                } else {
                    resolver.succeed(output)
                }
            }

            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                resolver.fail(ADBRunnerError.spawnFailed(message: error.localizedDescription))
            }
        }
    }

    public func runWithStdin(_ command: ADBCommand, stdin stdinPayload: String, timeout: Duration = .seconds(30)) async throws -> ADBProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = command.arguments
            process.environment = serverEnvironment()

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let resolver = ContinuationResolver(continuation: continuation)
            let buffer = StreamingBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { return }
                buffer.append(chunk)
            }

            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                if process.isRunning {
                    process.terminate()
                    resolver.fail(ADBRunnerError.timeout)
                }
            }

            process.terminationHandler = { proc in
                timeoutTask.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                if let tail = try? stdoutPipe.fileHandleForReading.readToEnd() {
                    buffer.append(tail)
                }
                let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stdout = String(data: buffer.snapshot(), encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let output = ADBProcessOutput(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
                if proc.terminationStatus != 0 {
                    resolver.fail(ADBRunnerError.nonZeroExit(code: proc.terminationStatus, stderr: stderr))
                } else {
                    resolver.succeed(output)
                }
            }

            do {
                try process.run()
                if let data = (stdinPayload + "\n").data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(data)
                }
                try? stdinPipe.fileHandleForWriting.close()
            } catch {
                timeoutTask.cancel()
                resolver.fail(ADBRunnerError.spawnFailed(message: error.localizedDescription))
            }
        }
    }

    public func runStreaming(
        _ command: ADBCommand,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            let process = Process()
            process.executableURL = binary
            process.arguments = command.arguments
            process.environment = serverEnvironment()

            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = Pipe()

            let resolver = ContinuationResolver(continuation: continuation)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in chunk.split(separator: "\n") {
                    onLine(String(line))
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                resolver.succeed(proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                resolver.fail(ADBRunnerError.spawnFailed(message: error.localizedDescription))
            }
        }
    }

    private final class StreamingBuffer: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock<Data>(initialState: Data())

        func append(_ chunk: Data) {
            state.withLock { $0.append(chunk) }
        }

        func snapshot() -> Data {
            state.withLock { $0 }
        }
    }

    private final class ContinuationResolver<T: Sendable>: @unchecked Sendable {
        private let state: OSAllocatedUnfairLock<CheckedContinuation<T, Error>?>

        init(continuation: CheckedContinuation<T, Error>) {
            self.state = OSAllocatedUnfairLock(initialState: continuation)
        }

        func succeed(_ value: T) {
            let taken = state.withLock { current -> CheckedContinuation<T, Error>? in
                let existing = current
                current = nil
                return existing
            }
            taken?.resume(returning: value)
        }

        func fail(_ error: Error) {
            let taken = state.withLock { current -> CheckedContinuation<T, Error>? in
                let existing = current
                current = nil
                return existing
            }
            taken?.resume(throwing: error)
        }
    }

    private func serverEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ANDROID_ADB_SERVER_PORT"] = String(port)
        return env
    }
}

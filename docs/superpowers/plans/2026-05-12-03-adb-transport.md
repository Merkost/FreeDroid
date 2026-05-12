# FreeDroid Plan #3 — ADB Transport

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `FreeDroidADB` Swift Package that wraps Android's `adb` binary. Provides a long-lived `ADBServer` actor, a per-device `ADBSession` actor implementing the `Transport` protocol, and a Trust prompt observer for the `unauthorized` state. Includes integration tests against an Android emulator.

**Architecture:** One package, two actors (`ADBServer`, `ADBSession`), a strongly-typed `ADBCommand` enum, and a `Process`-wrapping `ADBRunner`. File operations use the `adb sync` protocol via `adb push`/`adb pull`. Output parsing is implemented as pure functions on String/Data so it's trivially unit-testable.

**Tech Stack:** Swift 6 with strict concurrency, Foundation `Process`, swift-async-algorithms, FreeDroidDomain, Android Platform-Tools `adb` binary (Apache 2.0).

---

## File Structure

```
Packages/FreeDroidADB/
├── Package.swift                                       create
├── Resources/
│   └── adb                                              binary added in Task 2
├── Sources/FreeDroidADB/
│   ├── ADBRunner.swift                                  create — process spawning
│   ├── ADBServer.swift                                  create — server lifecycle
│   ├── ADBSession.swift                                 create — Transport impl
│   ├── ADBCommand.swift                                 create — command DSL
│   ├── ADBOutputParser.swift                            create — pure parsing
│   ├── ADBDeviceListEntry.swift                         create — parsed type
│   ├── ADBAuthorizationObserver.swift                   create — unauthorized polling
│   ├── ADBFileSync.swift                                create — push/pull wrappers
│   └── ADBBinary.swift                                  create — binary path resolver
└── Tests/FreeDroidADBTests/
    ├── ADBOutputParserTests.swift                       create
    ├── ADBCommandTests.swift                            create
    ├── ADBRunnerMockTests.swift                         create
    └── Integration/
        ├── ADBServerIntegrationTests.swift              create
        └── ADBSessionIntegrationTests.swift             create
```

Integration tests are gated by an env var so unit tests always run; integration runs only when an emulator is available.

---

## Task 1: Create `FreeDroidADB` package skeleton

**Files:**
- Create: `Packages/FreeDroidADB/Package.swift`

- [ ] **Step 1: Write the manifest**

Write `Packages/FreeDroidADB/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidADB",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidADB", targets: ["FreeDroidADB"])
    ],
    dependencies: [
        .package(path: "../FreeDroidDomain"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4")
    ],
    targets: [
        .target(
            name: "FreeDroidADB",
            dependencies: [
                "FreeDroidDomain",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            resources: [.copy("../../Resources/adb")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FreeDroidADBTests",
            dependencies: ["FreeDroidADB"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
```

- [ ] **Step 2: Create directory placeholders**

```bash
mkdir -p Packages/FreeDroidADB/Sources/FreeDroidADB
mkdir -p Packages/FreeDroidADB/Tests/FreeDroidADBTests/Integration
mkdir -p Packages/FreeDroidADB/Resources
touch Packages/FreeDroidADB/Sources/FreeDroidADB/.gitkeep
touch Packages/FreeDroidADB/Tests/FreeDroidADBTests/.gitkeep
```

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "feat(adb): scaffold FreeDroidADB package"
```

---

## Task 2: Bundle the `adb` binary

**Files:**
- Create: `Packages/FreeDroidADB/Resources/adb` (binary)
- Create: `Packages/FreeDroidADB/Resources/README.md`
- Modify: `.gitignore`

- [ ] **Step 1: Download Android Platform-Tools**

Run:

```bash
cd /tmp
curl -L -o platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
unzip -q platform-tools.zip
ls platform-tools
```

Expected: a `platform-tools` directory containing `adb`.

- [ ] **Step 2: Copy `adb` into the package resources**

Run:

```bash
cp /tmp/platform-tools/adb /Users/kostakttipay/StudioProjects/FreeDroid/Packages/FreeDroidADB/Resources/adb
chmod +x /Users/kostakttipay/StudioProjects/FreeDroid/Packages/FreeDroidADB/Resources/adb
```

- [ ] **Step 3: Verify it runs**

Run: `Packages/FreeDroidADB/Resources/adb --version`
Expected: e.g. `Android Debug Bridge version 1.0.41` plus a version string.

- [ ] **Step 4: Write a README explaining the source**

Write `Packages/FreeDroidADB/Resources/README.md`:

```markdown
# `adb` binary

This binary is `adb` from Google's Android Platform-Tools.

- **Source:** https://developer.android.com/tools/releases/platform-tools
- **License:** Apache License 2.0 (see `LICENSE-ADB.txt` at release-build time)
- **Update process:** `.github/workflows/update-adb.yml` runs weekly and opens a PR if a newer release ships.

We bundle this binary for convenience; users may override it via the `FREEDROID_ADB_PATH` environment variable when developing.
```

- [ ] **Step 5: Commit**

```bash
git add Packages/FreeDroidADB/Resources
git commit -m "chore(adb): bundle Android Platform-Tools adb binary"
```

---

## Task 3: `ADBBinary` resolver with tests

**Files:**
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBBinary.swift`

- [ ] **Step 1: Implement `ADBBinary`**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBBinary.swift`:

```swift
import Foundation

public enum ADBBinary {
    public static func path() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["FREEDROID_ADB_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ADBBinaryError.overrideNotExecutable(url)
            }
            return url
        }
        guard let bundled = Bundle.module.url(forResource: "adb", withExtension: nil) else {
            throw ADBBinaryError.notBundled
        }
        return bundled
    }
}

public enum ADBBinaryError: Error, Sendable, Equatable {
    case notBundled
    case overrideNotExecutable(URL)
}
```

- [ ] **Step 2: Build to verify**

Run: `cd Packages/FreeDroidADB && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "feat(adb): add ADBBinary path resolver with env override"
```

---

## Task 4: `ADBCommand` enum with tests

**Files:**
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBCommand.swift`
- Create: `Packages/FreeDroidADB/Tests/FreeDroidADBTests/ADBCommandTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `Packages/FreeDroidADB/Tests/FreeDroidADBTests/ADBCommandTests.swift`:

```swift
import Testing
@testable import FreeDroidADB

@Suite("ADBCommand")
struct ADBCommandTests {
    @Test func serverStartProducesCorrectArgs() {
        #expect(ADBCommand.startServer.arguments == ["start-server"])
    }

    @Test func serverKillProducesCorrectArgs() {
        #expect(ADBCommand.killServer.arguments == ["kill-server"])
    }

    @Test func listDevicesProducesCorrectArgs() {
        #expect(ADBCommand.listDevices.arguments == ["devices", "-l"])
    }

    @Test func shellAddsDeviceFlag() {
        let cmd = ADBCommand.shell(serial: "ABC123", script: "ls /sdcard")
        #expect(cmd.arguments == ["-s", "ABC123", "shell", "ls /sdcard"])
    }

    @Test func pullProducesCorrectArgs() {
        let cmd = ADBCommand.pull(serial: "ABC123", remote: "/sdcard/x", local: "/tmp/x")
        #expect(cmd.arguments == ["-s", "ABC123", "pull", "/sdcard/x", "/tmp/x"])
    }

    @Test func pushProducesCorrectArgs() {
        let cmd = ADBCommand.push(serial: "ABC123", local: "/tmp/x", remote: "/sdcard/x")
        #expect(cmd.arguments == ["-s", "ABC123", "push", "/tmp/x", "/sdcard/x"])
    }

    @Test func getPropProducesCorrectArgs() {
        let cmd = ADBCommand.getProp(serial: "ABC123", property: "ro.product.model")
        #expect(cmd.arguments == ["-s", "ABC123", "shell", "getprop", "ro.product.model"])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/FreeDroidADB && swift test`
Expected: build error — `cannot find 'ADBCommand'`.

- [ ] **Step 3: Implement `ADBCommand`**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBCommand.swift`:

```swift
public enum ADBCommand: Hashable, Sendable {
    case version
    case startServer
    case killServer
    case listDevices
    case shell(serial: String, script: String)
    case getProp(serial: String, property: String)
    case pull(serial: String, remote: String, local: String)
    case push(serial: String, local: String, remote: String)

    public var arguments: [String] {
        switch self {
        case .version:
            return ["--version"]
        case .startServer:
            return ["start-server"]
        case .killServer:
            return ["kill-server"]
        case .listDevices:
            return ["devices", "-l"]
        case let .shell(serial, script):
            return ["-s", serial, "shell", script]
        case let .getProp(serial, property):
            return ["-s", serial, "shell", "getprop", property]
        case let .pull(serial, remote, local):
            return ["-s", serial, "pull", remote, local]
        case let .push(serial, local, remote):
            return ["-s", serial, "push", local, remote]
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/FreeDroidADB && swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "feat(adb): add ADBCommand DSL with tests"
```

---

## Task 5: `ADBOutputParser` pure functions

**Files:**
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBDeviceListEntry.swift`
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBOutputParser.swift`
- Create: `Packages/FreeDroidADB/Tests/FreeDroidADBTests/ADBOutputParserTests.swift`

- [ ] **Step 1: Implement `ADBDeviceListEntry`**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBDeviceListEntry.swift`:

```swift
public enum ADBDeviceState: String, Hashable, Sendable {
    case device
    case unauthorized
    case offline
    case noPermissions = "no permissions"
    case recovery
    case sideload
    case bootloader
    case unknown
}

public struct ADBDeviceListEntry: Hashable, Sendable {
    public let serial: String
    public let state: ADBDeviceState
    public let product: String?
    public let model: String?
    public let device: String?
    public let transportId: String?
}
```

- [ ] **Step 2: Write failing tests**

Write `Packages/FreeDroidADB/Tests/FreeDroidADBTests/ADBOutputParserTests.swift`:

```swift
import Testing
@testable import FreeDroidADB

@Suite("ADBOutputParser")
struct ADBOutputParserTests {
    @Test func parsesEmptyDeviceList() {
        let out = """
        List of devices attached

        """
        let result = ADBOutputParser.parseDeviceList(out)
        #expect(result.isEmpty)
    }

    @Test func parsesAuthorizedDevice() {
        let out = """
        List of devices attached
        emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
        """
        let result = ADBOutputParser.parseDeviceList(out)
        #expect(result.count == 1)
        #expect(result[0].serial == "emulator-5554")
        #expect(result[0].state == .device)
        #expect(result[0].model == "sdk_gphone64_arm64")
        #expect(result[0].transportId == "1")
    }

    @Test func parsesUnauthorizedDevice() {
        let out = """
        List of devices attached
        ABC123XYZ              unauthorized usb:1-2 transport_id:2
        """
        let result = ADBOutputParser.parseDeviceList(out)
        #expect(result.count == 1)
        #expect(result[0].serial == "ABC123XYZ")
        #expect(result[0].state == .unauthorized)
    }

    @Test func parsesMultipleDevices() {
        let out = """
        List of devices attached
        ABC123                 device product:p1 model:M1 device:d1 transport_id:1
        DEF456                 unauthorized transport_id:2
        """
        let result = ADBOutputParser.parseDeviceList(out)
        #expect(result.count == 2)
        #expect(result[0].state == .device)
        #expect(result[1].state == .unauthorized)
    }

    @Test func parsesLsLineForFile() {
        let line = "-rw-rw---- 1 u0_a26 ext_data_rw 12345 2024-08-10 14:23 photo.jpg"
        let parsed = ADBOutputParser.parseLsLine(line)
        #expect(parsed != nil)
        #expect(parsed?.name == "photo.jpg")
        #expect(parsed?.size == 12345)
        #expect(parsed?.isDirectory == false)
    }

    @Test func parsesLsLineForDirectory() {
        let line = "drwxrwx--x 6 root sdcard_rw 4096 2024-09-01 10:11 DCIM"
        let parsed = ADBOutputParser.parseLsLine(line)
        #expect(parsed?.name == "DCIM")
        #expect(parsed?.isDirectory == true)
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd Packages/FreeDroidADB && swift test --filter ADBOutputParserTests`
Expected: build error — `cannot find 'ADBOutputParser'`.

- [ ] **Step 4: Implement the parser**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBOutputParser.swift`:

```swift
import Foundation

public enum ADBOutputParser {
    public struct LsEntry: Hashable, Sendable {
        public let name: String
        public let size: Int64
        public let modifiedAt: String
        public let isDirectory: Bool
    }

    public static func parseDeviceList(_ output: String) -> [ADBDeviceListEntry] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { line -> ADBDeviceListEntry? in
            let s = String(line)
            if s.hasPrefix("List of devices") { return nil }
            return parseDeviceLine(s)
        }
    }

    static func parseDeviceLine(_ line: String) -> ADBDeviceListEntry? {
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2 else { return nil }
        let serial = parts[0]
        let stateString = parts[1]
        let state = ADBDeviceState(rawValue: stateString) ?? .unknown

        var product: String?
        var model: String?
        var device: String?
        var transportId: String?
        for token in parts.dropFirst(2) {
            let kv = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "product": product = kv[1]
            case "model": model = kv[1]
            case "device": device = kv[1]
            case "transport_id": transportId = kv[1]
            default: break
            }
        }

        return ADBDeviceListEntry(
            serial: serial,
            state: state,
            product: product,
            model: model,
            device: device,
            transportId: transportId
        )
    }

    public static func parseLsLine(_ line: String) -> LsEntry? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 8 else { return nil }
        let permString = parts[0]
        let isDir = permString.first == "d"
        guard let size = Int64(parts[4]) else { return nil }
        let date = parts[5]
        let time = parts[6]
        let name = parts[7...].joined(separator: " ")
        return LsEntry(
            name: name,
            size: size,
            modifiedAt: "\(date) \(time)",
            isDirectory: isDir
        )
    }
}
```

- [ ] **Step 5: Run tests**

Run: `cd Packages/FreeDroidADB && swift test --filter ADBOutputParserTests`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "feat(adb): add output parsers for device list and ls"
```

---

## Task 6: `ADBRunner` process wrapper

**Files:**
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBRunner.swift`

- [ ] **Step 1: Implement `ADBRunner` protocol and live implementation**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBRunner.swift`:

```swift
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
```

- [ ] **Step 2: Build to verify**

Run: `cd Packages/FreeDroidADB && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "feat(adb): add ADBRunner process wrapper with timeout"
```

---

## Task 7: `ADBServer` lifecycle actor

**Files:**
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBServer.swift`

- [ ] **Step 1: Implement `ADBServer`**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBServer.swift`:

```swift
import Foundation

public actor ADBServer {
    private let runner: any ADBRunner
    private var isRunning = false

    public init(runner: any ADBRunner) {
        self.runner = runner
    }

    public static func live(port: Int = 5037) async throws -> ADBServer {
        let binary = try ADBBinary.path()
        return ADBServer(runner: LiveADBRunner(binary: binary, port: port))
    }

    public func start() async throws {
        guard !isRunning else { return }
        _ = try await runner.run(.startServer, timeout: .seconds(15))
        isRunning = true
    }

    public func stop() async {
        guard isRunning else { return }
        _ = try? await runner.run(.killServer, timeout: .seconds(5))
        isRunning = false
    }

    public func listDevices() async throws -> [ADBDeviceListEntry] {
        let output = try await runner.run(.listDevices, timeout: .seconds(5))
        return ADBOutputParser.parseDeviceList(output.stdout)
    }

    public func runner(for serial: String) -> any ADBRunner {
        runner
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd Packages/FreeDroidADB && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "feat(adb): add ADBServer lifecycle actor"
```

---

## Task 8: Mock `ADBRunner` and `ADBServer` integration tests

**Files:**
- Create: `Packages/FreeDroidADB/Tests/FreeDroidADBTests/ADBRunnerMockTests.swift`

- [ ] **Step 1: Write the failing test**

Write `Packages/FreeDroidADB/Tests/FreeDroidADBTests/ADBRunnerMockTests.swift`:

```swift
import Testing
@testable import FreeDroidADB

actor StubRunner: ADBRunner {
    var recorded: [ADBCommand] = []
    let outputs: [String: String]

    init(outputs: [String: String]) {
        self.outputs = outputs
    }

    func run(_ command: ADBCommand, timeout: Duration) async throws -> ADBProcessOutput {
        recorded.append(command)
        let key = command.arguments.joined(separator: " ")
        let stdout = outputs[key] ?? ""
        return ADBProcessOutput(exitCode: 0, stdout: stdout, stderr: "")
    }

    func runStreaming(_ command: ADBCommand, onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        recorded.append(command)
        return 0
    }
}

@Suite("ADBServer with stub runner")
struct ADBServerStubTests {
    @Test func startInvokesStartServerOnce() async throws {
        let stub = StubRunner(outputs: [:])
        let server = ADBServer(runner: stub)
        try await server.start()
        try await server.start()
        let recorded = await stub.recorded
        #expect(recorded == [.startServer])
    }

    @Test func listDevicesParsesStubOutput() async throws {
        let outputs: [String: String] = [
            "devices -l": """
            List of devices attached
            emulator-5554          device product:sdk model:Emulator device:e1 transport_id:1
            """
        ]
        let stub = StubRunner(outputs: outputs)
        let server = ADBServer(runner: stub)
        try await server.start()
        let devices = try await server.listDevices()
        #expect(devices.count == 1)
        #expect(devices[0].serial == "emulator-5554")
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `cd Packages/FreeDroidADB && swift test --filter ADBServerStubTests`
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "test(adb): ADBServer unit tests with stub runner"
```

---

## Task 9: `ADBAuthorizationObserver`

**Files:**
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBAuthorizationObserver.swift`

- [ ] **Step 1: Implement the observer**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBAuthorizationObserver.swift`:

```swift
import Foundation
import AsyncAlgorithms

public enum ADBAuthorizationStatus: Hashable, Sendable {
    case authorized
    case unauthorized
    case missing
}

public actor ADBAuthorizationObserver {
    private let server: ADBServer
    private let serial: String
    private let pollInterval: Duration

    public init(server: ADBServer, serial: String, pollInterval: Duration = .milliseconds(750)) {
        self.server = server
        self.serial = serial
        self.pollInterval = pollInterval
    }

    public func status() async throws -> ADBAuthorizationStatus {
        let devices = try await server.listDevices()
        guard let device = devices.first(where: { $0.serial == serial }) else {
            return .missing
        }
        switch device.state {
        case .device: return .authorized
        case .unauthorized: return .unauthorized
        default: return .missing
        }
    }

    public func observe() -> AsyncThrowingStream<ADBAuthorizationStatus, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var last: ADBAuthorizationStatus?
                while !Task.isCancelled {
                    do {
                        let current = try await self.status()
                        if current != last {
                            continuation.yield(current)
                            last = current
                        }
                        if current == .authorized { continuation.finish(); return }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    try? await Task.sleep(for: pollInterval)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd Packages/FreeDroidADB && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "feat(adb): add ADBAuthorizationObserver for trust prompt polling"
```

---

## Task 10: `ADBSession` implementing `Transport`

**Files:**
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBFileSync.swift`
- Create: `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBSession.swift`

- [ ] **Step 1: Implement `ADBFileSync` helpers**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBFileSync.swift`:

```swift
import Foundation

enum ADBFileSync {
    static func tempLocalPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("freedroid-adb-\(UUID().uuidString)", isDirectory: false)
    }
}
```

- [ ] **Step 2: Implement `ADBSession`**

Write `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBSession.swift`:

```swift
import Foundation
import FreeDroidDomain

public actor ADBSession: Transport {
    public let deviceID: DeviceID
    public let capabilities = TransportCapabilities(
        supportsRangeRead: false,
        supportsRangeWrite: false,
        supportsSymlinks: true,
        recommendedChunkBytes: 1 << 20
    )

    private let serial: String
    private let server: ADBServer
    private var cachedInfo: DeviceInfo?

    public init(deviceID: DeviceID, serial: String, server: ADBServer) {
        self.deviceID = deviceID
        self.serial = serial
        self.server = server
    }

    public var info: DeviceInfo {
        get async throws {
            if let cachedInfo { return cachedInfo }
            let runner = await server.runner(for: serial)
            async let manufacturer = property(runner: runner, key: "ro.product.manufacturer")
            async let model = property(runner: runner, key: "ro.product.model")
            async let version = property(runner: runner, key: "ro.build.version.release")
            let info = DeviceInfo(
                serial: serial,
                manufacturer: try await manufacturer,
                model: try await model,
                androidVersion: try await version,
                storageCapacityBytes: nil,
                storageFreeBytes: nil
            )
            cachedInfo = info
            return info
        }
    }

    private func property(runner: any ADBRunner, key: String) async throws -> String {
        let out = try await runner.run(.getProp(serial: serial, property: key), timeout: .seconds(5))
        return out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func list(_ path: RemotePath) async throws -> [RemoteEntry] {
        let runner = await server.runner(for: serial)
        let out = try await runner.run(
            .shell(serial: serial, script: "ls -al --time-style=long-iso \(escape(path.raw))"),
            timeout: .seconds(15)
        )
        let lines = out.stdout.split(separator: "\n").map(String.init)
        return lines.compactMap { line -> RemoteEntry? in
            guard !line.hasPrefix("total ") else { return nil }
            guard let parsed = ADBOutputParser.parseLsLine(line) else { return nil }
            guard parsed.name != "." && parsed.name != ".." else { return nil }
            return RemoteEntry(
                path: path.appending(parsed.name),
                name: parsed.name,
                kind: parsed.isDirectory ? .directory : .file,
                sizeBytes: parsed.isDirectory ? nil : parsed.size,
                modifiedAt: nil,
                isHidden: parsed.name.hasPrefix(".")
            )
        }
    }

    public func stat(_ path: RemotePath) async throws -> RemoteEntry {
        let parent = path.parent ?? .root
        let entries = try await list(parent)
        guard let match = entries.first(where: { $0.name == path.name }) else {
            throw TransportError.notFound(path)
        }
        return match
    }

    public func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        let temp = ADBFileSync.tempLocalPath()
        defer { try? FileManager.default.removeItem(at: temp) }
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.pull(serial: serial, remote: path.raw, local: temp.path), timeout: .seconds(120))
        let data = try Data(contentsOf: temp)
        let start = Int(offset)
        let end = min(start + length, data.count)
        guard start < data.count else { return Data() }
        return data.subdata(in: start..<end)
    }

    public func write(_ path: RemotePath, data: Data, offset: Int64) async throws {
        guard offset == 0 else { throw TransportError.unsupported(reason: "ADB push does not support offset writes") }
        let temp = ADBFileSync.tempLocalPath()
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.push(serial: serial, local: temp.path, remote: path.raw), timeout: .seconds(300))
    }

    public func mkdir(_ path: RemotePath) async throws {
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.shell(serial: serial, script: "mkdir -p \(escape(path.raw))"), timeout: .seconds(5))
    }

    public func remove(_ path: RemotePath) async throws {
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.shell(serial: serial, script: "rm -rf \(escape(path.raw))"), timeout: .seconds(30))
    }

    public func rename(_ from: RemotePath, to dest: RemotePath) async throws {
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.shell(serial: serial, script: "mv \(escape(from.raw)) \(escape(dest.raw))"), timeout: .seconds(30))
    }

    public func close() async {
        cachedInfo = nil
    }

    private func escape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd Packages/FreeDroidADB && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "feat(adb): add ADBSession implementing Transport protocol"
```

---

## Task 11: Integration tests gated by env var

**Files:**
- Create: `Packages/FreeDroidADB/Tests/FreeDroidADBTests/Integration/ADBServerIntegrationTests.swift`
- Create: `Packages/FreeDroidADB/Tests/FreeDroidADBTests/Integration/ADBSessionIntegrationTests.swift`

- [ ] **Step 1: Write integration tests**

Write `Packages/FreeDroidADB/Tests/FreeDroidADBTests/Integration/ADBServerIntegrationTests.swift`:

```swift
import Testing
import Foundation
@testable import FreeDroidADB

@Suite(
    "ADBServer integration",
    .enabled(if: ProcessInfo.processInfo.environment["FREEDROID_RUN_ADB_INTEGRATION"] == "1")
)
struct ADBServerIntegrationTests {
    @Test func canStartServerAndListDevices() async throws {
        let server = try await ADBServer.live()
        try await server.start()
        let devices = try await server.listDevices()
        #expect(devices.count >= 1, "Expected at least one running emulator/device")
        await server.stop()
    }
}
```

Write `Packages/FreeDroidADB/Tests/FreeDroidADBTests/Integration/ADBSessionIntegrationTests.swift`:

```swift
import Testing
import Foundation
import FreeDroidDomain
@testable import FreeDroidADB

@Suite(
    "ADBSession integration",
    .enabled(if: ProcessInfo.processInfo.environment["FREEDROID_RUN_ADB_INTEGRATION"] == "1")
)
struct ADBSessionIntegrationTests {
    private func makeSession() async throws -> (ADBServer, ADBSession) {
        let server = try await ADBServer.live()
        try await server.start()
        let devices = try await server.listDevices()
        guard let device = devices.first(where: { $0.state == .device }) else {
            throw TransportError.notConnected
        }
        let session = ADBSession(deviceID: DeviceID(raw: device.serial), serial: device.serial, server: server)
        return (server, session)
    }

    @Test func canFetchDeviceInfo() async throws {
        let (server, session) = try await makeSession()
        let info = try await session.info
        #expect(!info.manufacturer.isEmpty)
        #expect(!info.model.isEmpty)
        await server.stop()
    }

    @Test func canListSdcard() async throws {
        let (server, session) = try await makeSession()
        let entries = try await session.list(RemotePath(raw: "/sdcard"))
        #expect(!entries.isEmpty)
        await server.stop()
    }

    @Test func canRoundtripFileWriteReadDelete() async throws {
        let (server, session) = try await makeSession()
        let path = RemotePath(raw: "/sdcard/freedroid-test-\(UUID().uuidString).txt")
        let payload = Data("hello freedroid".utf8)
        try await session.write(path, data: payload, offset: 0)
        let readBack = try await session.read(path, offset: 0, length: 1024)
        #expect(readBack == payload)
        try await session.remove(path)
        await server.stop()
    }
}
```

- [ ] **Step 2: Verify the gating works (no emulator required)**

Run: `cd Packages/FreeDroidADB && swift test`
Expected: integration tests are skipped, others pass.

- [ ] **Step 3: Run with emulator (manual verification)**

Start an Android emulator (Android Studio or `emulator -avd <name>`), then:

```bash
FREEDROID_RUN_ADB_INTEGRATION=1 cd Packages/FreeDroidADB && swift test
```

Expected: integration tests run and pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidADB
git commit -m "test(adb): add integration tests gated by FREEDROID_RUN_ADB_INTEGRATION"
```

---

## Task 12: Update CI to run ADB unit tests

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add an `test-adb` job**

In `.github/workflows/ci.yml`, append after `test-ui`:

```yaml
  test-adb:
    name: Test FreeDroidADB
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'
      - name: Build & test
        run: |
          cd Packages/FreeDroidADB
          swift test --parallel
```

Add `test-adb` to the `needs` array of the `build-app` job.

- [ ] **Step 2: Commit**

```bash
git add .github
git commit -m "ci: run FreeDroidADB unit test suite"
```

---

## Done When

- `swift test` in `FreeDroidADB` passes (unit + parser tests).
- With `FREEDROID_RUN_ADB_INTEGRATION=1` and a running emulator, integration tests pass: device listing, info, ls, write/read/delete roundtrip.
- `ADBSession` fully implements `Transport`.
- `ADBAuthorizationObserver` emits status changes for an `unauthorized` device.
- SwiftLint passes.

## Self-Review

- Spec §6.1 (FreeDroidADB) → Tasks 1–10.
- Spec §5.3 (Transport protocol) → Task 10.
- Spec §9.3 (cancellation/retry) → `ADBRunnerError.timeout` plus `TransportError.isRetryable` from Domain Plan #1.
- Spec §6.3 (auto-selection) → out of scope here; happens in `FreeDroidData` (Plan #5).
- Spec §11.1 (license matrix) → `adb` Apache 2.0 noted in `Resources/README.md`.

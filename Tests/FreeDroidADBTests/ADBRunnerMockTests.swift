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

    func runWithStdin(_ command: ADBCommand, stdin: String, timeout: Duration) async throws -> ADBProcessOutput {
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

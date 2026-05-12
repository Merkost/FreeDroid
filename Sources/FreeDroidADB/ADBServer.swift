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
        _ = serial
        return runner
    }
}

public extension ADBServer {
    static func liveSync(port: Int = 5037) throws -> ADBServer {
        let binary = try ADBBinary.path()
        return ADBServer(runner: LiveADBRunner(binary: binary, port: port))
    }
}

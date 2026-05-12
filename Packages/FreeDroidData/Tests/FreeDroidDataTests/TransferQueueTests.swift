import Foundation
import Testing
import FreeDroidDomain
@testable import FreeDroidData

actor FakeTransport: Transport {
    nonisolated let deviceID = DeviceID(raw: "FAKE")
    nonisolated let capabilities = TransportCapabilities(
        supportsRangeRead: true,
        supportsRangeWrite: false,
        supportsSymlinks: false,
        recommendedChunkBytes: 1024
    )

    var content: [RemotePath: Data] = [:]

    nonisolated var info: DeviceInfo {
        get async throws {
            DeviceInfo(
                serial: "FAKE",
                manufacturer: "Test",
                model: "Fake",
                androidVersion: nil,
                storageCapacityBytes: nil,
                storageFreeBytes: nil
            )
        }
    }

    func list(_ path: RemotePath) async throws -> [RemoteEntry] { [] }

    func stat(_ path: RemotePath) async throws -> RemoteEntry {
        guard let data = content[path] else { throw TransportError.notFound(path) }
        return RemoteEntry(
            path: path,
            name: path.name,
            kind: .file,
            sizeBytes: Int64(data.count),
            modifiedAt: nil,
            isHidden: false
        )
    }

    func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        guard let data = content[path] else { throw TransportError.notFound(path) }
        let start = Int(offset)
        let end = min(start + length, data.count)
        return data.subdata(in: start..<end)
    }

    func write(_ path: RemotePath, data: Data, offset: Int64) async throws {
        content[path] = data
    }

    func mkdir(_ path: RemotePath) async throws {}

    func remove(_ path: RemotePath) async throws {
        content[path] = nil
    }

    func rename(_ from: RemotePath, to destination: RemotePath) async throws {
        content[destination] = content[from]
        content[from] = nil
    }

    func close() async {}
}

@Suite("TransferQueue")
struct TransferQueueTests {
    @Test func pullsFileToLocal() async throws {
        let transport = FakeTransport()
        let path = RemotePath(raw: "/x/file.bin")
        try await transport.write(path, data: Data(repeating: 9, count: 2048), offset: 0)
        let queue = TransferQueue()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("freedroid-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dest) }

        let job = TransferJob(
            deviceID: DeviceID(raw: "FAKE"),
            direction: .toMac,
            items: [path],
            destination: dest
        )
        let engine = TransferEngine(transport: transport, chunkSize: 1024)
        let stream = await queue.enqueue(job, engine: engine)
        var lastProgress: TransferProgress?
        for try await progress in stream { lastProgress = progress }
        #expect(lastProgress?.completedBytes == 2048)
        let written = try Data(contentsOf: dest.appendingPathComponent("file.bin"))
        #expect(written.count == 2048)
    }
}

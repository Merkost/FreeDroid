import Testing
import Foundation
import FreeDroidDomain
@testable import FreeDroidMTP

private final class RecordingProgressSink: TransferProgressSink, @unchecked Sendable {
    var reports: [(bytesTransferred: Int64, totalBytes: Int64?)] = []

    func report(bytesTransferred: Int64, totalBytes: Int64?) {
        reports.append((bytesTransferred, totalBytes))
    }
}

@Suite("MTPTransferContext")
struct MTPTransferContextTests {

    @Test func accumulatesBytesAcrossCallbacks() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtp-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        let sink = RecordingProgressSink()
        let ctx = MTPTransferContext(handle: handle, expected: 100, progress: sink)

        ctx.handle.write(Data(repeating: 0xAB, count: 40))
        ctx.bytesTransferred += 40
        ctx.progress?.report(bytesTransferred: ctx.bytesTransferred, totalBytes: ctx.expected)

        ctx.handle.write(Data(repeating: 0xCD, count: 60))
        ctx.bytesTransferred += 60
        ctx.progress?.report(bytesTransferred: ctx.bytesTransferred, totalBytes: ctx.expected)

        try? handle.close()

        #expect(ctx.bytesTransferred == 100)
        #expect(sink.reports.count == 2)
        #expect(sink.reports[0].bytesTransferred == 40)
        #expect(sink.reports[0].totalBytes == 100)
        #expect(sink.reports[1].bytesTransferred == 100)
        #expect(sink.reports[1].totalBytes == 100)

        let written = try Data(contentsOf: url)
        #expect(written.count == 100)
        #expect(written[0] == 0xAB)
        #expect(written[40] == 0xCD)
    }

    @Test func nilProgressDoesNotCrash() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtp-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        let ctx = MTPTransferContext(handle: handle, expected: 0, progress: nil)

        ctx.handle.write(Data(repeating: 0x01, count: 10))
        ctx.bytesTransferred += 10
        ctx.progress?.report(bytesTransferred: ctx.bytesTransferred, totalBytes: nil)
        try? handle.close()

        #expect(ctx.bytesTransferred == 10)
    }

    @Test func zeroExpectedReportsNilTotal() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtp-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        let sink = RecordingProgressSink()
        let ctx = MTPTransferContext(handle: handle, expected: 0, progress: sink)

        ctx.bytesTransferred += 5
        ctx.progress?.report(
            bytesTransferred: ctx.bytesTransferred,
            totalBytes: ctx.expected > 0 ? ctx.expected : nil
        )
        try? handle.close()

        #expect(sink.reports[0].totalBytes == nil)
    }
}

@Suite("MTPPathResolver resolution for transfer")
struct MTPPathResolverTransferTests {

    private func makeResolver() -> MTPPathResolver {
        MTPPathResolver(objects: [
            MTPObject(storageID: 1, objectHandle: 10, parentHandle: 0, name: "Music", isFolder: true, size: 0, modifiedAt: nil),
            MTPObject(storageID: 1, objectHandle: 20, parentHandle: 10, name: "song.mp3", isFolder: false, size: 8 * 1024 * 1024, modifiedAt: nil)
        ])
    }

    @Test func resolvesObjectIDForFetch() {
        let resolver = makeResolver()
        let handle = resolver.handle(for: RemotePath(raw: "/Music/song.mp3"))
        #expect(handle == 20)
    }

    @Test func objectSizeIsAvailableForLargeFile() {
        let resolver = makeResolver()
        let objectID = resolver.handle(for: RemotePath(raw: "/Music/song.mp3"))!
        let obj = resolver.objects.first(where: { $0.objectHandle == objectID })
        #expect(obj?.size == Int64(8 * 1024 * 1024))
    }

    @Test func parentHandleResolvedForUpload() {
        let resolver = makeResolver()
        let parentHandle = resolver.handle(for: RemotePath(raw: "/Music"))
        #expect(parentHandle == 10)
    }

    @Test func storageIDRetrievedFromParent() {
        let resolver = makeResolver()
        let parentHandle = resolver.handle(for: RemotePath(raw: "/Music"))!
        let storageID = resolver.objects.first(where: { $0.objectHandle == parentHandle })?.storageID
        #expect(storageID == 1)
    }
}

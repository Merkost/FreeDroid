import Foundation
import FreeDroidDomain

actor MountedVolumeStore {
    private let url: URL
    private var snapshot: [String: URL]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent("FreeDroid", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.url = folder.appendingPathComponent("mounted-volumes.json")
        if let data = try? Data(contentsOf: url),
           let map = try? JSONDecoder().decode([String: URL].self, from: data) {
            let mounted = Self.currentlyMountedPaths()
            self.snapshot = map.filter { mounted.contains($0.value.standardizedFileURL.path) }
        } else {
            self.snapshot = [:]
        }
    }

    private static func currentlyMountedPaths() -> Set<String> {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        return Set(urls.map { $0.standardizedFileURL.path })
    }

    func record(_ deviceID: DeviceID, mountedAt mountURL: URL) {
        snapshot[deviceID.raw] = mountURL
        try? persist()
    }

    func forget(_ deviceID: DeviceID) {
        snapshot[deviceID.raw] = nil
        try? persist()
    }

    func mountURL(for deviceID: DeviceID) -> URL? {
        snapshot[deviceID.raw]
    }

    func all() -> [(DeviceID, URL)] {
        snapshot.map { (DeviceID(raw: $0.key), $0.value) }
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }
}

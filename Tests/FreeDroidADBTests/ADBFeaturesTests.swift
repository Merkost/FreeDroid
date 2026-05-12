import Foundation
import Testing
@testable import FreeDroidADB

@Suite("ADBFeatures")
struct ADBFeaturesTests {
    @Test func parsesCommaSeparatedFeatures() {
        let raw = "shell_v2,cmd,stat_v2,ls_v2,fixed_push_mkdir,apex,abb,fixed_push_symlink_timestamp,abb_exec,remount_shell,track_app,sendrecv_v2,sendrecv_v2_brotli,sendrecv_v2_lz4,sendrecv_v2_zstd,sendrecv_v2_dry_run_send,openscreen_mdns,zstd_compress,zstd_decompress"
        let features = ADBOutputParser.parseFeatures(raw)
        #expect(features.contains("zstd_compress"))
        #expect(features.contains("zstd_decompress"))
        #expect(features.contains("shell_v2"))
        #expect(features.count == 19)
    }

    @Test func parsesEmptyStringToEmptySet() {
        let features = ADBOutputParser.parseFeatures("")
        #expect(features.isEmpty)
    }

    @Test func parsesFeaturesWithWhitespace() {
        let raw = "zstd_compress, zstd_decompress, shell_v2"
        let features = ADBOutputParser.parseFeatures(raw)
        #expect(features.contains("zstd_compress"))
        #expect(features.contains("zstd_decompress"))
        #expect(features.contains("shell_v2"))
    }

    @Test func zstdEnabledWhenBothFeaturesPresent() {
        let features: Set<String> = ["zstd_compress", "zstd_decompress", "shell_v2"]
        #expect(features.contains("zstd_compress") && features.contains("zstd_decompress"))
    }

    @Test func zstdDisabledWhenOnlyOneFeaturePresent() {
        let featuresCompressOnly: Set<String> = ["zstd_compress", "shell_v2"]
        #expect(!(featuresCompressOnly.contains("zstd_compress") && featuresCompressOnly.contains("zstd_decompress")))

        let featuresDecompressOnly: Set<String> = ["zstd_decompress", "shell_v2"]
        #expect(!(featuresDecompressOnly.contains("zstd_compress") && featuresDecompressOnly.contains("zstd_decompress")))
    }

    @Test func bundledAdbVersionIsAtLeast1041() throws {
        let adbPath = try ADBBinary.path()
        let process = Process()
        process.executableURL = adbPath
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let versionLine = output.split(separator: "\n").first.map(String.init) ?? ""
        let components = versionLine.split(separator: " ")
        guard let versionIndex = components.firstIndex(of: "version"),
              components.indices.contains(versionIndex + 1) else {
            Issue.record("Could not parse adb version from: \(versionLine)")
            return
        }
        let versionString = String(components[versionIndex + 1])
        let parts = versionString.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else {
            Issue.record("Unexpected version format: \(versionString)")
            return
        }
        let major = parts[0], minor = parts[1], patch = parts[2]
        let meetsMinimum = (major, minor, patch) >= (1, 0, 41)
        #expect(meetsMinimum, "Bundled adb \(versionString) is below minimum 1.0.41 required for zstd compression")
    }
}

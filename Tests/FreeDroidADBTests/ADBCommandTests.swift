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
        #expect(cmd.arguments == ["-s", "ABC123", "pull", "-a", "/sdcard/x", "/tmp/x"])
    }

    @Test func pushProducesCorrectArgs() {
        let cmd = ADBCommand.push(serial: "ABC123", local: "/tmp/x", remote: "/sdcard/x")
        #expect(cmd.arguments == ["-s", "ABC123", "push", "/tmp/x", "/sdcard/x"])
    }

    @Test func getPropProducesCorrectArgs() {
        let cmd = ADBCommand.getProp(serial: "ABC123", property: "ro.product.model")
        #expect(cmd.arguments == ["-s", "ABC123", "shell", "getprop", "ro.product.model"])
    }

    @Test func pairProducesCorrectArgs() {
        let cmd = ADBCommand.pair(host: "192.168.1.5", port: 37561)
        #expect(cmd.arguments == ["pair", "192.168.1.5:37561"])
    }

    @Test func connectProducesCorrectArgs() {
        let cmd = ADBCommand.connect(host: "192.168.1.5", port: 5555)
        #expect(cmd.arguments == ["connect", "192.168.1.5:5555"])
    }

    @Test func disconnectProducesCorrectArgs() {
        let cmd = ADBCommand.disconnect(host: "192.168.1.5", port: 5555)
        #expect(cmd.arguments == ["disconnect", "192.168.1.5:5555"])
    }

    @Test func hostFeaturesProducesCorrectArgs() {
        #expect(ADBCommand.hostFeatures.arguments == ["host-features"])
    }

    @Test func pullWithCompressionAddsZstdFlag() {
        let cmd = ADBCommand.pull(serial: "ABC123", remote: "/sdcard/x", local: "/tmp/x", compressed: true)
        #expect(cmd.arguments == ["-s", "ABC123", "pull", "-a", "-z", "zstd", "/sdcard/x", "/tmp/x"])
    }

    @Test func pullWithoutCompressionOmitsFlag() {
        let cmd = ADBCommand.pull(serial: "ABC123", remote: "/sdcard/x", local: "/tmp/x", compressed: false)
        #expect(cmd.arguments == ["-s", "ABC123", "pull", "-a", "/sdcard/x", "/tmp/x"])
    }

    @Test func pushWithCompressionAddsZstdFlag() {
        let cmd = ADBCommand.push(serial: "ABC123", local: "/tmp/x", remote: "/sdcard/x", compressed: true)
        #expect(cmd.arguments == ["-s", "ABC123", "push", "-z", "zstd", "/tmp/x", "/sdcard/x"])
    }

    @Test func pushWithoutCompressionOmitsFlag() {
        let cmd = ADBCommand.push(serial: "ABC123", local: "/tmp/x", remote: "/sdcard/x", compressed: false)
        #expect(cmd.arguments == ["-s", "ABC123", "push", "/tmp/x", "/sdcard/x"])
    }
}

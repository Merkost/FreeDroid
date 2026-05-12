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

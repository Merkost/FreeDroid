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

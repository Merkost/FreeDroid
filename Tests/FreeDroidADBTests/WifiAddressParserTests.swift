import Testing
@testable import FreeDroidADB

@Suite("Wifi address parsing")
struct WifiAddressParserTests {
    func parse(_ raw: String) -> (host: String, port: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let port = Int(parts[1]), port > 0, port <= 65535 else { return nil }
        return (String(parts[0]), port)
    }

    @Test func validAddressParses() {
        let result = parse("192.168.1.5:37561")
        #expect(result?.host == "192.168.1.5")
        #expect(result?.port == 37561)
    }

    @Test func missingPortReturnsNil() {
        #expect(parse("192.168.1.5") == nil)
    }

    @Test func portOutOfRangeReturnsNil() {
        #expect(parse("192.168.1.5:99999") == nil)
    }

    @Test func emptyStringReturnsNil() {
        #expect(parse("") == nil)
    }

    @Test func zeroPortReturnsNil() {
        #expect(parse("192.168.1.5:0") == nil)
    }

    @Test func pairCommandUsesFullAddress() {
        let cmd = ADBCommand.pair(host: "192.168.1.5", port: 37561)
        #expect(cmd.arguments.first == "pair")
        #expect(cmd.arguments.last == "192.168.1.5:37561")
    }

    @Test func connectCommandUsesFullAddress() {
        let cmd = ADBCommand.connect(host: "10.0.0.1", port: 5555)
        #expect(cmd.arguments.first == "connect")
        #expect(cmd.arguments.last == "10.0.0.1:5555")
    }
}

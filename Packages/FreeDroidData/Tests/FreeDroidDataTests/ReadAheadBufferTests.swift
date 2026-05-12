import Foundation
import Testing
@testable import FreeDroidData

@Suite("ReadAheadBuffer")
struct ReadAheadBufferTests {
    @Test func storesAndRetrievesRange() async {
        let buffer = ReadAheadBuffer(capacity: 1024)
        await buffer.store(offset: 0, data: Data(repeating: 7, count: 256))
        let result = await buffer.read(offset: 0, length: 100)
        #expect(result?.count == 100)
        #expect(result?.allSatisfy { $0 == 7 } ?? false)
    }

    @Test func cacheMissWhenRangeNotStored() async {
        let buffer = ReadAheadBuffer(capacity: 1024)
        await buffer.store(offset: 0, data: Data(repeating: 1, count: 100))
        let result = await buffer.read(offset: 200, length: 50)
        #expect(result == nil)
    }
}

import Foundation

actor FetchGate {
    private let limit: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    static func defaultLimit() -> Int {
        let suite = UserDefaults(suiteName: "group.com.merkost.freedroid") ?? .standard
        let stored = suite.integer(forKey: "FreeDroid.ParallelTransfersPerDevice")
        return stored == 0 ? 3 : max(1, min(stored, 16))
    }

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
            return
        }
        inFlight = max(0, inFlight - 1)
    }

    func withSlot<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }
}

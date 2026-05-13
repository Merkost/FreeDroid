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
        inFlight += 1
    }

    func release() {
        inFlight -= 1
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        }
    }
}

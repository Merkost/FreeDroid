public protocol Cache: Sendable {
    associatedtype Key: Hashable & Sendable
    associatedtype Value: Sendable

    func get(_ key: Key) async -> Value?
    func put(key: Key, value: Value) async
    func remove(_ key: Key) async
    func clear() async
}

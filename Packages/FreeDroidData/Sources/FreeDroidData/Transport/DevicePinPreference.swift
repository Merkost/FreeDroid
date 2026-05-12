import Foundation
import FreeDroidDomain

public actor DevicePinPreference {
    private let defaults: UserDefaults
    private let key = "FreeDroid.PinnedTransports"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func pinned(for serial: String) async -> TransportKind? {
        let map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return map[serial].flatMap(TransportKind.init(rawValue:))
    }

    public func pin(_ kind: TransportKind, for serial: String) async {
        var map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        map[serial] = kind.rawValue
        defaults.set(map, forKey: key)
    }

    public func clear(for serial: String) async {
        var map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        map.removeValue(forKey: serial)
        defaults.set(map, forKey: key)
    }
}

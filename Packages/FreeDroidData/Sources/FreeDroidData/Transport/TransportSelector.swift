import FreeDroidDomain

public enum TransportSelector {
    public static func select(
        adbAvailable: Bool,
        adbAuthorized: Bool,
        mtpAvailable: Bool,
        pinned: TransportKind?
    ) -> TransportKind? {
        if let pinned {
            switch pinned {
            case .adb where adbAvailable && adbAuthorized:
                return .adb
            case .mtp where mtpAvailable:
                return .mtp
            case .wifi:
                return nil
            default:
                break
            }
        }
        if adbAvailable && adbAuthorized { return .adb }
        if mtpAvailable { return .mtp }
        return nil
    }
}

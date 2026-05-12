import Foundation
import CLibmtp

public actor MTPRuntime {
    private var isInitialized = false

    public init() {}

    public func start() async {
        guard !isInitialized else { return }
        LIBMTP_Init()
        LIBMTP_Set_Debug(0)
        isInitialized = true
    }

    public func ensureInitialized() async {
        await start()
    }
}

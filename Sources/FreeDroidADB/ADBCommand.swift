public enum ADBCommand: Hashable, Sendable {
    case version
    case startServer
    case killServer
    case listDevices
    case hostFeatures
    case shell(serial: String, script: String)
    case getProp(serial: String, property: String)
    case pull(serial: String, remote: String, local: String, compressed: Bool = false)
    case push(serial: String, local: String, remote: String, compressed: Bool = false)

    public var arguments: [String] {
        switch self {
        case .version:
            return ["--version"]
        case .startServer:
            return ["start-server"]
        case .killServer:
            return ["kill-server"]
        case .listDevices:
            return ["devices", "-l"]
        case .hostFeatures:
            return ["host-features"]
        case let .shell(serial, script):
            return ["-s", serial, "shell", script]
        case let .getProp(serial, property):
            return ["-s", serial, "shell", "getprop", property]
        case let .pull(serial, remote, local, compressed):
            var args = ["-s", serial, "pull"]
            if compressed { args += ["-z", "zstd"] }
            args += [remote, local]
            return args
        case let .push(serial, local, remote, compressed):
            var args = ["-s", serial, "push"]
            if compressed { args += ["-z", "zstd"] }
            args += [local, remote]
            return args
        }
    }
}

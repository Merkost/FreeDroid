public enum ADBCommand: Hashable, Sendable {
    case version
    case startServer
    case killServer
    case listDevices
    case shell(serial: String, script: String)
    case getProp(serial: String, property: String)
    case pull(serial: String, remote: String, local: String)
    case push(serial: String, local: String, remote: String)
    case pair(host: String, port: Int)
    case connect(host: String, port: Int)
    case disconnect(host: String, port: Int)

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
        case let .shell(serial, script):
            return ["-s", serial, "shell", script]
        case let .getProp(serial, property):
            return ["-s", serial, "shell", "getprop", property]
        case let .pull(serial, remote, local):
            return ["-s", serial, "pull", remote, local]
        case let .push(serial, local, remote):
            return ["-s", serial, "push", local, remote]
        case let .pair(host, port):
            return ["pair", "\(host):\(port)"]
        case let .connect(host, port):
            return ["connect", "\(host):\(port)"]
        case let .disconnect(host, port):
            return ["disconnect", "\(host):\(port)"]
        }
    }
}

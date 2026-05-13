import Foundation

final class StubADBServer: @unchecked Sendable {
    private var serverFD: Int32 = -1
    private(set) var port: UInt16 = 0
    private var acceptThread: Thread?
    private let lock = NSLock()
    private var pendingHandlers: [(@Sendable (Int32) -> Void)] = []

    func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EBADF) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        let bindResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }

        guard Darwin.listen(fd, 10) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &addrLen)
            }
        }
        self.port = UInt16(bigEndian: boundAddr.sin_port)
        self.serverFD = fd

        let thread = Thread {
            self.acceptLoop()
        }
        thread.start()
        self.acceptThread = thread
    }

    func stop() {
        lock.lock()
        let fd = serverFD
        serverFD = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
    }

    func acceptOne(handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        pendingHandlers.append(handler)
        lock.unlock()
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let fd = serverFD
            lock.unlock()
            guard fd >= 0 else { break }

            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { break }

            lock.lock()
            let handler = pendingHandlers.isEmpty ? nil : pendingHandlers.removeFirst()
            lock.unlock()

            if let handler {
                let capturedFD = clientFD
                let t = Thread { handler(capturedFD) }
                t.start()
            } else {
                close(clientFD)
            }
        }
    }
}

func writeAll(fd: Int32, data: Data) throws {
    var offset = 0
    while offset < data.count {
        let written = data.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress! + offset, data.count - offset)
        }
        if written <= 0 { throw POSIXError(.EPIPE) }
        offset += written
    }
}

func readExact(fd: Int32, count: Int) throws -> Data {
    var buffer = Data(count: count)
    var offset = 0
    while offset < count {
        let n = buffer.withUnsafeMutableBytes { ptr in
            Darwin.read(fd, ptr.baseAddress! + offset, count - offset)
        }
        if n <= 0 { throw POSIXError(.ECONNRESET) }
        offset += n
    }
    return buffer
}

func readAll(fd: Int32) throws -> Data {
    var result = Data()
    var tmp = Data(count: 4096)
    while true {
        let n = tmp.withUnsafeMutableBytes { ptr in
            Darwin.read(fd, ptr.baseAddress!, 4096)
        }
        if n <= 0 { break }
        result.append(tmp.prefix(n))
    }
    return result
}


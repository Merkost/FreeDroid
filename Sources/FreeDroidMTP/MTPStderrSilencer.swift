import Darwin

/// Temporarily redirects the process stderr file descriptor to /dev/null for the
/// duration of a libmtp call, suppressing the fprintf-based noise that libmtp
/// writes unconditionally.  All Swift `os.Logger` output is unaffected because it
/// goes through the os_log subsystem, not through the stdio stderr FILE pointer.
///
/// If any C call fails the silencer degrades gracefully — the body still executes,
/// just without redirection.
enum MTPStderrSilencer {

    /// Run a synchronous throwing body with stderr redirected to /dev/null.
    static func run<T>(_ body: () throws -> T) rethrows -> T {
        let savedFD = dup(fileno(stderr))
        let devnull = fopen("/dev/null", "w")
        if let devnull, savedFD != -1 {
            dup2(fileno(devnull), fileno(stderr))
            fclose(devnull)
        }
        defer {
            if savedFD != -1 {
                fflush(stderr)
                dup2(savedFD, fileno(stderr))
                close(savedFD)
            }
        }
        return try body()
    }

    /// Run an async throwing body with stderr redirected to /dev/null.
    static func run<T>(_ body: () async throws -> T) async rethrows -> T {
        let savedFD = dup(fileno(stderr))
        let devnull = fopen("/dev/null", "w")
        if let devnull, savedFD != -1 {
            dup2(fileno(devnull), fileno(stderr))
            fclose(devnull)
        }
        defer {
            if savedFD != -1 {
                fflush(stderr)
                dup2(savedFD, fileno(stderr))
                close(savedFD)
            }
        }
        return try await body()
    }
}

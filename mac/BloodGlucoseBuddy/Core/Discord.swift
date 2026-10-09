import Darwin
import Foundation

enum DiscordError: LocalizedError {
    case notRunning, disconnected, rejected(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Discord isn't open."
        case .disconnected: return "Lost the connection to Discord."
        case .rejected(let message): return "Discord said: \(message)"
        }
    }
}

/// Talks to the Discord desktop app over its local socket (the Rich Presence "IPC" protocol).
/// Not thread-safe: use from one serial queue.
final class DiscordIPC: @unchecked Sendable {  // safe: only ever used from one serial queue
    let clientID: String
    private var fd: Int32 = -1

    init(clientID: String) { self.clientID = clientID }
    deinit { close() }

    /// Each message is: opcode (UInt32 LE), length (UInt32 LE), JSON.
    static func frame(opcode: UInt32, payload: Data) -> Data {
        var data = Data()
        withUnsafeBytes(of: opcode.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    static func socketPaths() -> [String] {
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        return (0..<10).map { (tmp as NSString).appendingPathComponent("discord-ipc-\($0)") }
    }

    /// Passing nil clears the status.
    func setActivity(_ activity: [String: Any]?) throws {
        if fd < 0 { try connect() }
        var args: [String: Any] = ["pid": Int(getpid())]
        if let activity { args["activity"] = activity }
        do {
            try send(opcode: 1, ["cmd": "SET_ACTIVITY", "args": args, "nonce": UUID().uuidString])
            let (opcode, reply) = try receive()
            if opcode == 2 { throw DiscordError.disconnected }
            if reply["evt"] as? String == "ERROR" {
                let message = (reply["data"] as? [String: Any])?["message"] as? String ?? "unknown error"
                throw DiscordError.rejected(message)
            }
        } catch {
            close()
            throw error
        }
    }

    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    private func connect() throws {
        close()
        for path in Self.socketPaths() where FileManager.default.fileExists(atPath: path) {
            guard let s = Self.open(path) else { continue }
            fd = s
            do {
                try send(opcode: 0, ["v": 1, "client_id": clientID])
                let (opcode, reply) = try receive()
                if opcode == 2 { throw DiscordError.rejected(reply["message"] as? String ?? "connection refused") }
                guard reply["evt"] as? String == "READY" else { throw DiscordError.rejected("unexpected handshake reply") }
                return
            } catch {
                close()
                throw error
            }
        }
        throw DiscordError.notRunning
    }

    private static func open(_ path: String) -> Int32? {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(s); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, size) }
        }
        guard result == 0 else { Darwin.close(s); return nil }
        return s
    }

    private func send(opcode: UInt32, _ json: [String: Any]) throws {
        let data = Self.frame(opcode: opcode, payload: try JSONSerialization.data(withJSONObject: json))
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                guard n > 0 else { throw DiscordError.disconnected }
                offset += n
            }
        }
    }

    private func receive() throws -> (UInt32, [String: Any]) {
        let header = try readExactly(8)
        let opcode = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) }
        let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        guard length < 1_000_000 else { throw DiscordError.disconnected }
        let body = try readExactly(Int(length))
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        return (opcode, json)
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { raw in
            while offset < count {
                let n = read(fd, raw.baseAddress! + offset, count - offset)
                guard n > 0 else { throw DiscordError.disconnected }
                offset += n
            }
        }
        return data
    }
}

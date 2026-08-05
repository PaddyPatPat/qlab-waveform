import Darwin
import Foundation

enum OSCValue: Sendable {
    case int(Int32)
    case float(Float)
    case double(Double)
    case string(String)
    case bool(Bool)

    var number: Double? {
        switch self {
        case .int(let value): Double(value)
        case .float(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    var boolean: Bool? {
        switch self {
        case .bool(let value): value
        case .int(let value): value != 0
        case .float(let value): value != 0
        case .double(let value): value != 0
        case .string(let value): ["true", "yes", "1"].contains(value.lowercased())
        }
    }
}

struct OSCMessage: Sendable {
    let address: String
    let arguments: [OSCValue]
}

final class OSCClient: @unchecked Sendable {
    var onMessage: (@Sendable (OSCMessage) -> Void)?

    private let queue = DispatchQueue(label: "nz.net.duncan.qlab-waveform.osc", qos: .userInteractive)
    private var socketDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var cueID: String?
    private var replyPort: Int32 = 0
    private var tick = 0

    func start() {
        queue.async { [self] in
            guard socketDescriptor < 0 else { return }
            let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard descriptor >= 0 else { return }
            socketDescriptor = descriptor

            var local = sockaddr_in()
            local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            local.sin_family = sa_family_t(AF_INET)
            local.sin_port = 0
            local.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let bindResult = withUnsafePointer(to: &local) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else {
                Darwin.close(descriptor)
                socketDescriptor = -1
                return
            }

            var bound = sockaddr_in()
            var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            withUnsafeMutablePointer(to: &bound) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = getsockname(descriptor, $0, &boundLength)
                }
            }
            replyPort = Int32(UInt16(bigEndian: bound.sin_port))

            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.receiveAvailablePackets() }
            source.setCancelHandler { Darwin.close(descriptor) }
            readSource = source
            source.resume()

            send(address: "/udpReplyPort", arguments: [.int(replyPort)])
            send(address: "/listen")
            send(address: "/version")

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }

    func monitor(cueID: String?) {
        queue.async { [weak self] in self?.cueID = cueID }
    }

    func authenticate(passcode: String) {
        queue.async { [weak self] in
            guard let self else { return }
            send(address: "/connect", arguments: [.string(passcode)])
            queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
                guard let self else { return }
                send(address: "/udpReplyPort", arguments: [.int(replyPort)])
                send(address: "/listen")
                send(address: "/version")
            }
        }
    }

    private func poll() {
        tick += 1
        if let cueID {
            send(address: "/cue_id/\(cueID)/actionElapsed")
        }
        if tick % 300 == 0 { send(address: "/listen") }
    }

    private func send(address: String, arguments: [OSCValue] = []) {
        guard socketDescriptor >= 0 else { return }
        let packet = OSCCodec.encode(address: address, arguments: arguments)
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = UInt16(53000).bigEndian
        target.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(socketDescriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func receiveAvailablePackets() {
        var buffer = [UInt8](repeating: 0, count: 65_535)
        while true {
            let count = recv(socketDescriptor, &buffer, buffer.count, MSG_DONTWAIT)
            guard count > 0 else { return }
            if let message = OSCCodec.decode(Data(buffer.prefix(count))) {
                DispatchQueue.main.async { [weak self] in self?.onMessage?(message) }
            }
        }
    }
}

enum OSCCodec {
    static func encode(address: String, arguments: [OSCValue]) -> Data {
        var data = paddedString(address)
        var tags = ","
        var payload = Data()
        for argument in arguments {
            switch argument {
            case .int(let value):
                tags += "i"
                append(value.bigEndian, to: &payload)
            case .float(let value):
                tags += "f"
                append(value.bitPattern.bigEndian, to: &payload)
            case .double(let value):
                tags += "d"
                append(value.bitPattern.bigEndian, to: &payload)
            case .string(let value):
                tags += "s"
                payload.append(paddedString(value))
            case .bool(let value):
                tags += value ? "T" : "F"
            }
        }
        data.append(paddedString(tags))
        data.append(payload)
        return data
    }

    static func decode(_ data: Data) -> OSCMessage? {
        guard !data.starts(with: Data("#bundle".utf8)) else { return nil }
        var offset = 0
        guard let address = readString(data, offset: &offset),
              let tags = readString(data, offset: &offset), tags.first == "," else { return nil }
        var arguments: [OSCValue] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "i":
                guard let raw: Int32 = readInteger(data, offset: &offset) else { return nil }
                arguments.append(.int(Int32(bigEndian: raw)))
            case "f":
                guard let raw: UInt32 = readInteger(data, offset: &offset) else { return nil }
                arguments.append(.float(Float(bitPattern: UInt32(bigEndian: raw))))
            case "d":
                guard let raw: UInt64 = readInteger(data, offset: &offset) else { return nil }
                arguments.append(.double(Double(bitPattern: UInt64(bigEndian: raw))))
            case "s":
                guard let value = readString(data, offset: &offset) else { return nil }
                arguments.append(.string(value))
            case "T": arguments.append(.bool(true))
            case "F": arguments.append(.bool(false))
            default: return nil
            }
        }
        return OSCMessage(address: address, arguments: arguments)
    }

    private static func paddedString(_ value: String) -> Data {
        var data = Data(value.utf8)
        data.append(0)
        while data.count % 4 != 0 { data.append(0) }
        return data
    }

    private static func readString(_ data: Data, offset: inout Int) -> String? {
        guard offset < data.count,
              let end = data[offset...].firstIndex(of: 0),
              let value = String(data: data[offset..<end], encoding: .utf8) else { return nil }
        offset = (end + 4) & ~3
        return value
    }

    private static func append<T>(_ value: T, to data: inout Data) {
        var value = value
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func readInteger<T>(_ data: Data, offset: inout Int) -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { return nil }
        let value = data[offset..<(offset + size)].withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: T.self)
        }
        offset += size
        return value
    }
}

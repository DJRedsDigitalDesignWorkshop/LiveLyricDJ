import Foundation

/// OSC 1.1 subset used by the Serato Remote protocol.
enum OSCArg {
    case i(Int32)
    case f(Float)
    case s(String)
    case b(Data)

    var typeChar: Character {
        switch self {
        case .i: return "i"
        case .f: return "f"
        case .s: return "s"
        case .b: return "b"
        }
    }
}

struct OSCMessage {
    let address: String
    let args: [OSCArg]

    static func message(_ address: String, _ args: OSCArg...) -> OSCMessage {
        OSCMessage(address: address, args: args)
    }
}

enum OSCError: Error {
    case malformed(String)
}

/// OSC 1.1 encode/decode matching `serato-connect`'s implementation.
/// Type tags: i = int32, f = float32, s = null-terminated string, b = blob.
/// Every field is padded to a 4-byte boundary; blobs are length-prefixed.
enum OSC {
    static func pad4(_ n: Int) -> Int { (n + 3) & ~3 }

    // MARK: - Encoding

    static func encodeString(_ s: String) -> Data {
        var data = Data()
        data.append(Data(s.utf8))
        data.append(0)
        while data.count % 4 != 0 { data.append(0) }
        return data
    }

    static func encode(_ msg: OSCMessage) -> Data {
        var data = Data()
        data.append(encodeString(msg.address))
        data.append(encodeString("," + msg.args.map { $0.typeChar }))
        for arg in msg.args {
            switch arg {
            case .i(let v):
                var value = v.bigEndian
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            case .f(let v):
                var bits = v.bitPattern.bigEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            case .s(let s):
                data.append(encodeString(s))
            case .b(let b):
                var len = UInt32(b.count).bigEndian
                withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
                data.append(b)
                let padded = pad4(b.count)
                for _ in b.count..<padded { data.append(0) }
            }
        }
        return data
    }

    // MARK: - Decoding

    private static func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v = (v << 8) | UInt32(data[offset + i]) }
        return v
    }

    private static func decodeString(_ data: Data, _ offset: Int) throws -> (String, Int) {
        var end = offset
        while end < data.count && data[end] != 0 { end += 1 }
        guard end < data.count else { throw OSCError.malformed("string not null-terminated") }
        let value = String(decoding: data[offset..<end], as: UTF8.self)
        let consumed = end - offset + 1
        return (value, offset + pad4(consumed))
    }

    static func decode(_ data: Data) throws -> OSCMessage {
        let (address, afterAddr) = try decodeString(data, 0)
        if afterAddr >= data.count { return OSCMessage(address: address, args: []) }
        let (tagString, afterTags) = try decodeString(data, afterAddr)
        if tagString.isEmpty { return OSCMessage(address: address, args: []) }
        guard tagString.hasPrefix(",") else {
            throw OSCError.malformed("type-tag missing leading comma")
        }

        var args: [OSCArg] = []
        var cursor = afterTags
        for tag in tagString.dropFirst() {
            switch tag {
            case "i":
                guard cursor + 4 <= data.count else { throw OSCError.malformed("int32 truncated") }
                args.append(.i(Int32(bitPattern: readUInt32BE(data, cursor))))
                cursor += 4
            case "f":
                guard cursor + 4 <= data.count else { throw OSCError.malformed("float32 truncated") }
                args.append(.f(Float(bitPattern: readUInt32BE(data, cursor))))
                cursor += 4
            case "s":
                let (s, next) = try decodeString(data, cursor)
                args.append(.s(s))
                cursor = next
            case "b":
                guard cursor + 4 <= data.count else { throw OSCError.malformed("blob length truncated") }
                let blobLen = Int(readUInt32BE(data, cursor))
                cursor += 4
                guard cursor + blobLen <= data.count else { throw OSCError.malformed("blob data truncated") }
                args.append(.b(Data(data[cursor..<cursor + blobLen])))
                cursor += pad4(blobLen)
            default:
                throw OSCError.malformed("unsupported type tag '\(tag)'")
            }
        }
        return OSCMessage(address: address, args: args)
    }

    /// Decode a packet, which is either a plain message or a `#bundle`
    /// (8-byte marker + 8-byte time-tag + size-prefixed element packets).
    /// Bundles are flattened recursively into their contained messages.
    static func decodePacket(_ data: Data) throws -> [OSCMessage] {
        if data.count >= 8 && String(decoding: data[0..<7], as: UTF8.self) == "#bundle" {
            var messages: [OSCMessage] = []
            var cursor = 16
            while cursor + 4 <= data.count {
                let size = Int(readUInt32BE(data, cursor))
                cursor += 4
                if size == 0 { continue }
                guard cursor + size <= data.count else {
                    throw OSCError.malformed("bundle element exceeds packet")
                }
                messages.append(contentsOf: try decodePacket(Data(data[cursor..<cursor + size])))
                cursor += size
            }
            return messages
        }
        return [try decode(data)]
    }
}
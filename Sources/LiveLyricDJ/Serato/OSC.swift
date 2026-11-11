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
    private static let maxBundleDepth = 16
    private static let bundlePrefix = Data("#bundle".utf8)

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
        let paddedLength = pad4(consumed)
        guard paddedLength <= data.count - offset else {
            throw OSCError.malformed("string padding exceeds packet")
        }
        let paddedEnd = offset + paddedLength
        guard data[(end + 1)..<paddedEnd].allSatisfy({ $0 == 0 }) else {
            throw OSCError.malformed("string padding is not zero-filled")
        }
        return (value, paddedEnd)
    }

    static func decode(_ data: Data) throws -> OSCMessage {
        let (address, afterAddr) = try decodeString(data, 0)
        if afterAddr >= data.count { return OSCMessage(address: address, args: []) }
        let (tagString, afterTags) = try decodeString(data, afterAddr)
        if tagString.isEmpty {
            guard afterTags == data.count else {
                throw OSCError.malformed("unexpected data after empty type-tag string")
            }
            return OSCMessage(address: address, args: [])
        }
        guard tagString.hasPrefix(",") else {
            throw OSCError.malformed("type-tag missing leading comma")
        }

        var args: [OSCArg] = []
        var cursor = afterTags
        for tag in tagString.dropFirst() {
            switch tag {
            case "i":
                guard cursor <= data.count, data.count - cursor >= 4 else {
                    throw OSCError.malformed("int32 truncated")
                }
                args.append(.i(Int32(bitPattern: readUInt32BE(data, cursor))))
                cursor += 4
            case "f":
                guard cursor <= data.count, data.count - cursor >= 4 else {
                    throw OSCError.malformed("float32 truncated")
                }
                args.append(.f(Float(bitPattern: readUInt32BE(data, cursor))))
                cursor += 4
            case "s":
                let (s, next) = try decodeString(data, cursor)
                args.append(.s(s))
                cursor = next
            case "b":
                guard cursor <= data.count, data.count - cursor >= 4 else {
                    throw OSCError.malformed("blob length truncated")
                }
                let blobLen = Int(readUInt32BE(data, cursor))
                cursor += 4
                let paddedBlobLen = pad4(blobLen)
                guard cursor <= data.count, paddedBlobLen <= data.count - cursor else {
                    throw OSCError.malformed("blob data or padding truncated")
                }
                let blobEnd = cursor + blobLen
                let paddedBlobEnd = cursor + paddedBlobLen
                guard data[blobEnd..<paddedBlobEnd].allSatisfy({ $0 == 0 }) else {
                    throw OSCError.malformed("blob padding is not zero-filled")
                }
                args.append(.b(Data(data[cursor..<blobEnd])))
                cursor += paddedBlobLen
            default:
                throw OSCError.malformed("unsupported type tag '\(tag)'")
            }
        }
        guard cursor == data.count else {
            throw OSCError.malformed("unexpected trailing data after OSC message")
        }
        return OSCMessage(address: address, args: args)
    }

    /// Decode a packet, which is either a plain message or a `#bundle`
    /// (8-byte marker + 8-byte time-tag + size-prefixed element packets).
    /// Bundles are flattened recursively into their contained messages.
    static func decodePacket(_ data: Data) throws -> [OSCMessage] {
        try decodePacket(data, bundleDepth: 0)
    }

    private static func decodePacket(_ data: Data, bundleDepth: Int) throws -> [OSCMessage] {
        let hasBundlePrefix = data.count >= bundlePrefix.count
            && data.prefix(bundlePrefix.count).elementsEqual(bundlePrefix)
        guard hasBundlePrefix else { return [try decode(data)] }

        guard data.count >= 8 else { throw OSCError.malformed("bundle marker truncated") }
        guard data[7] == 0 else { throw OSCError.malformed("bundle marker missing null terminator") }
        guard data.count >= 16 else { throw OSCError.malformed("bundle header truncated") }
        guard bundleDepth < maxBundleDepth else {
            throw OSCError.malformed("bundle nesting exceeds maximum depth")
        }

        var messages: [OSCMessage] = []
        var cursor = 16
        while cursor < data.count {
            guard data.count - cursor >= 4 else {
                throw OSCError.malformed("bundle element size truncated")
            }
            let size = Int(readUInt32BE(data, cursor))
            cursor += 4
            guard size > 0 else { throw OSCError.malformed("bundle element has zero size") }
            guard size % 4 == 0 else {
                throw OSCError.malformed("bundle element size is not 4-byte aligned")
            }
            guard cursor <= data.count, size <= data.count - cursor else {
                throw OSCError.malformed("bundle element exceeds packet")
            }
            let end = cursor + size
            messages.append(contentsOf: try decodePacket(
                Data(data[cursor..<end]),
                bundleDepth: bundleDepth + 1
            ))
            cursor = end
        }
        return messages
    }
}

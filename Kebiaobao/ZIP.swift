import Foundation
import Compression

// MARK: - CRC32

private let crcTable: [UInt32] = {
    (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
}()

func crc32(_ data: Data) -> UInt32 {
    var c: UInt32 = 0xFFFFFFFF
    for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
    return c ^ 0xFFFFFFFF
}

// MARK: - 原始 deflate / inflate

private func deflateRaw(_ data: Data) -> Data? {
    guard !data.isEmpty else { return Data() }
    let cap = max(64, data.count + data.count / 2 + 64)
    var out = Data(count: cap)
    let n = out.withUnsafeMutableBytes { dst -> Int in
        data.withUnsafeBytes { src -> Int in
            compression_encode_buffer(
                dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil, COMPRESSION_ZLIB)
        }
    }
    guard n > 0 else { return nil }
    return out.prefix(n)
}

private func inflateRaw(_ data: Data, hint: Int) -> Data? {
    guard !data.isEmpty else { return Data() }
    var cap = max(256, hint)
    for _ in 0..<12 {
        var out = Data(count: cap)
        let n = out.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src -> Int in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        if n > 0 && n < cap { return out.prefix(n) }
        if n > 0 && n == cap { cap *= 2; continue }   // 可能刚好填满，扩大再试
        cap *= 2
    }
    return nil
}

// MARK: - ZIP 写（deflate，失败回退 store）

func zip(_ files: [(String, Data)]) -> Data {
    var out = Data()
    var central = Data()
    var offsets: [Int] = []

    func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    func le32(_ v: Int) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }

    for (name, content) in files {
        let nameData = Data(name.utf8)
        let crc = crc32(content)
        let compressed = deflateRaw(content)
        let method = compressed != nil ? 8 : 0
        let payload = compressed ?? content
        offsets.append(out.count)

        out.append(le32(0x04034b50))
        out.append(le16(20))                 // version needed
        out.append(le16(0x0800))             // flags: UTF-8 名字
        out.append(le16(method))
        out.append(le16(0))                  // mod time
        out.append(le16(0))                  // mod date
        out.append(le32(Int(crc)))
        out.append(le32(payload.count))
        out.append(le32(content.count))
        out.append(le16(nameData.count))
        out.append(le16(0))                  // extra len
        out.append(nameData)
        out.append(payload)

        central.append(le32(0x02014b50))
        central.append(le16(20))             // version made by
        central.append(le16(20))             // version needed
        central.append(le16(0x0800))
        central.append(le16(method))
        central.append(le16(0)); central.append(le16(0))
        central.append(le32(Int(crc)))
        central.append(le32(payload.count))
        central.append(le32(content.count))
        central.append(le16(nameData.count))
        central.append(le16(0))              // extra
        central.append(le16(0))              // comment
        central.append(le16(0))              // disk
        central.append(le16(0))              // internal attrs
        central.append(le32(0))              // external attrs
        central.append(le32(offsets[offsets.count - 1]))
        central.append(nameData)
    }

    let centralStart = out.count
    out.append(central)
    out.append(le32(0x06054b50))
    out.append(le16(0)); out.append(le16(0))
    out.append(le16(files.count)); out.append(le16(files.count))
    out.append(le32(central.count))
    out.append(le32(centralStart))
    out.append(le16(0))
    return out
}

// MARK: - ZIP 读

func unzip(_ data: Data) -> [String: Data]? {
    let bytes = [UInt8](data)
    guard bytes.count > 22 else { return nil }

    func u16(_ o: Int) -> Int { Int(bytes[o]) | (Int(bytes[o + 1]) << 8) }
    func u32(_ o: Int) -> Int {
        Int(bytes[o]) | (Int(bytes[o + 1]) << 8) | (Int(bytes[o + 2]) << 16) | (Int(bytes[o + 3]) << 24)
    }

    // 从尾部找 EOCD
    var eocd = -1
    var i = bytes.count - 22
    while i >= 0 {
        if u32(i) == 0x06054b50 { eocd = i; break }
        i -= 1
    }
    guard eocd >= 0 else { return nil }

    let count = u16(eocd + 10)
    var p = u32(eocd + 16)
    var out: [String: Data] = [:]

    for _ in 0..<count {
        guard p + 46 <= bytes.count, u32(p) == 0x02014b50 else { return nil }
        let method = u16(p + 10)
        let compSize = u32(p + 20)
        let nameLen = u16(p + 28)
        let extraLen = u16(p + 30)
        let commentLen = u16(p + 32)
        let localOff = u32(p + 42)
        guard p + 46 + nameLen <= bytes.count else { return nil }
        let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)

        // 本地头里的 name/extra 长度才是真实偏移
        guard localOff + 30 <= bytes.count, u32(localOff) == 0x04034b50 else { return nil }
        let lNameLen = u16(localOff + 26)
        let lExtraLen = u16(localOff + 28)
        let start = localOff + 30 + lNameLen + lExtraLen
        guard start + compSize <= bytes.count else { return nil }
        let payload = Data(bytes[start..<(start + compSize)])

        if method == 0 {
            out[name] = payload
        } else if method == 8 {
            // 用未压缩大小做 hint
            let raw = u32(p + 24)
            if let d = inflateRaw(payload, hint: max(256, raw)) { out[name] = d }
        }
        p += 46 + nameLen + extraLen + commentLen
    }
    return out
}

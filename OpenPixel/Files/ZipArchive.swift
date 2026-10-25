import Compression
import Foundation

/// Reads the files in a ZIP archive (stored or deflated), enough for Aseprite
/// extensions. Foundation has no ZIP reader on iOS.
struct ZipArchive {
    enum Failure: Error {
        case notAZip
        case damaged
        case unsupported
    }

    private struct Entry {
        let method: Int
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    private let bytes: [UInt8]
    private let entries: [String: Entry]

    /// File paths in the archive, folders left out.
    var paths: [String] { entries.keys.sorted() }

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        // The end of central directory record is in the last 64 KB plus 22 bytes.
        guard bytes.count >= 22 else { throw Failure.notAZip }
        var end = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while end >= lowest, Self.u32(bytes, end) != 0x0605_4B50 { end -= 1 }
        guard end >= lowest else { throw Failure.notAZip }
        let count = Self.u16(bytes, end + 10)
        var offset = Self.u32(bytes, end + 16)
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, Self.u32(bytes, offset) == 0x0201_4B50 else { throw Failure.damaged }
            let nameLength = Self.u16(bytes, offset + 28)
            let extraLength = Self.u16(bytes, offset + 30)
            let commentLength = Self.u16(bytes, offset + 32)
            guard offset + 46 + nameLength <= bytes.count else { throw Failure.damaged }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            if !name.hasSuffix("/") {
                entries[name] = Entry(
                    method: Self.u16(bytes, offset + 10),
                    compressedSize: Self.u32(bytes, offset + 20),
                    size: Self.u32(bytes, offset + 24),
                    localHeaderOffset: Self.u32(bytes, offset + 42)
                )
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// A file's contents by its path in the archive (a leading `./` is ignored).
    func data(at path: String) throws -> Data? {
        var path = path
        while path.hasPrefix("./") { path.removeFirst(2) }
        guard let entry = entries[path] else { return nil }
        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count, Self.u32(bytes, header) == 0x0403_4B50 else { throw Failure.damaged }
        let start = header + 30 + Self.u16(bytes, header + 26) + Self.u16(bytes, header + 28)
        guard start + entry.compressedSize <= bytes.count else { throw Failure.damaged }
        let compressed = bytes[start..<(start + entry.compressedSize)]
        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            guard entry.size > 0 else { return Data() }
            var output = [UInt8](repeating: 0, count: entry.size)
            // ZIP stores raw deflate, which is what COMPRESSION_ZLIB decodes.
            let written = Array(compressed).withUnsafeBufferPointer { src in
                output.withUnsafeMutableBufferPointer { dst in
                    compression_decode_buffer(dst.baseAddress!, entry.size, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.size else { throw Failure.damaged }
            return Data(output)
        default:
            throw Failure.unsupported
        }
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> Int { u16(b, i) | u16(b, i + 2) << 16 }
}

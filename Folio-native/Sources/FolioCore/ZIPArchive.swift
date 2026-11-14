import Foundation
import CZlib

/// Bounded ZIP reader for Android's stored/DEFLATE archives, including data descriptors.
/// Files are returned as data, never extracted using untrusted paths.
public enum ZIPArchive {
    public static let libraryLimit = 512 * 1024 * 1024
    public static let entryLimit = 200 * 1024 * 1024

    public static func safePath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 512 && !path.hasPrefix("/") && !path.contains("\\")
            && !path.contains(":") && !path.unicodeScalars.contains(where: { $0.value < 32 })
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." })
    }

    public static func read(_ data: Data, limit: Int = libraryLimit) throws -> [String: Data] {
        try require(data.count >= 22 && data.count <= libraryLimit + 64 * 1024 * 1024, "Choose a Folio ZIP smaller than 512 MB.")
        func u16(_ offset: Int) throws -> Int {
            try require(offset >= 0 && offset + 2 <= data.count, "Truncated ZIP header.")
            return Int(data[offset]) | Int(data[offset + 1]) << 8
        }
        func u32(_ offset: Int) throws -> Int {
            try require(offset >= 0 && offset + 4 <= data.count, "Truncated ZIP header.")
            return Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
        }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try u32(offset) == 0x06054b50, offset + 22 + (try u16(offset + 20)) == data.count { end = offset; break }
        }
        guard let end else { throw FolioError.invalid("This is not a complete ZIP archive.") }
        let count = try u16(end + 10), directory = try u32(end + 16), directorySize = try u32(end + 12)
        try require(try u16(end + 4) == 0 && u16(end + 6) == 0 && u16(end + 8) == count,
                    "Split ZIP archives are unsupported.")
        try require(count < 65_535 && count <= 50_000 && directory + directorySize == end, "ZIP64 and oversized archives are unsupported.")
        var at = directory, total = 0, seen = Set<String>(), ranges: [Range<Int>] = [], result: [String: Data] = [:]
        for _ in 0..<count {
            try require(at >= 0 && at + 46 <= end && (try u32(at)) == 0x02014b50, "Invalid ZIP directory.")
            let flags = try u16(at + 8), method = try u16(at + 10), crc = try u32(at + 16)
            let packed = try u32(at + 20), size = try u32(at + 24), nameLength = try u16(at + 28)
            let extra = try u16(at + 30), comment = try u16(at + 32), offset = try u32(at + 42)
            let mode = (try u32(at + 38)) >> 16
            try require(at + 46 + nameLength + extra + comment <= end, "Invalid ZIP entry.")
            guard let name = String(data: data.subdata(in: at + 46..<at + 46 + nameLength), encoding: .utf8) else {
                throw FolioError.invalid("ZIP file names must be UTF-8.")
            }
            at += 46 + nameLength + extra + comment
            try require(safePath(name) && seen.insert(name).inserted, "Unsafe or duplicate ZIP path.")
            try require(flags & 0x41 == 0 && (method == 0 || method == 8) && mode & 0xf000 != 0xa000,
                        "Encrypted ZIPs, links, and this compression method are unsupported.")
            total += size
            try require(total <= limit && size <= entryLimit, "The uncompressed archive exceeds the import size limit.")
            try require(offset >= 0 && offset + 30 <= directory && (try u32(offset)) == 0x04034b50, "Invalid ZIP local header.")
            let localName = try u16(offset + 26), localExtra = try u16(offset + 28)
            let start = offset + 30 + localName + localExtra
            try require(start <= directory && start + packed <= directory, "Truncated ZIP content.")
            let localText = String(data: data.subdata(in: offset + 30..<offset + 30 + localName), encoding: .utf8)
            try require(localText == name && (try u16(offset + 6)) == flags && (try u16(offset + 8)) == method, "ZIP headers disagree.")
            ranges.append(offset..<start + packed)
            let compressed = data.subdata(in: start..<start + packed)
            let content: Data
            if method == 0 {
                try require(packed == size, "Invalid stored ZIP entry.")
                content = compressed
            } else { content = try inflateRaw(compressed, size: size) }
            try require(checksum(content) == UInt32(crc), "A ZIP file failed its CRC integrity check.")
            if name.hasSuffix("/") { try require(size == 0, "Invalid ZIP directory entry.") }
            else { result[name] = content }
        }
        try require(at == end, "The ZIP directory has unexpected trailing content.")
        ranges.sort { $0.lowerBound < $1.lowerBound }
        for index in ranges.indices.dropFirst() {
            try require(ranges[index].lowerBound >= ranges[index - 1].upperBound, "ZIP entries overlap.")
        }
        return result
    }

    private static func inflateRaw(_ input: Data, size: Int) throws -> Data {
        var stream = z_stream()
        let started = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        try require(started == Z_OK, "Could not initialize ZIP decompression.")
        defer { inflateEnd(&stream) }
        var output = Data(count: max(1, size))
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(max(1, size))
                return inflate(&stream, Z_FINISH)
            }
        }
        try require(status == Z_STREAM_END && stream.total_out == size && stream.total_in == input.count, "Invalid or oversized compressed ZIP content.")
        output.count = size
        return output
    }

    public static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(CZlib.crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
    }

    /// Stored ZIP output is interoperable with Android and requires no third-party package.
    public static func write(_ entries: [String: Data]) throws -> Data {
        try require(entries.count <= 50_000 && entries.values.reduce(0, { $0 + $1.count }) <= libraryLimit, "The backup exceeds 512 MB. Export smaller notebooks.")
        var output = Data(), central = Data()
        func append16(_ value: Int, to data: inout Data) { for shift in [0, 8] { data.append(UInt8(truncatingIfNeeded: value >> shift)) } }
        func append32(_ value: Int, to data: inout Data) { for shift in [0, 8, 16, 24] { data.append(UInt8(truncatingIfNeeded: value >> shift)) } }
        for name in entries.keys.sorted() {
            let content = entries[name]!, utf8 = Data(name.utf8), crc = Int(checksum(content)), offset = output.count
            try require(safePath(name) && !name.hasSuffix("/") && content.count <= entryLimit, "Invalid backup entry.")
            append32(0x04034b50, to: &output); append16(20, to: &output); append16(0x800, to: &output)
            append16(0, to: &output); append32(0, to: &output); append32(crc, to: &output)
            append32(content.count, to: &output); append32(content.count, to: &output)
            append16(utf8.count, to: &output); append16(0, to: &output); output.append(utf8); output.append(content)
            append32(0x02014b50, to: &central); append16(20, to: &central); append16(20, to: &central)
            append16(0x800, to: &central); append16(0, to: &central); append32(0, to: &central)
            append32(crc, to: &central); append32(content.count, to: &central); append32(content.count, to: &central)
            append16(utf8.count, to: &central); append16(0, to: &central); append16(0, to: &central)
            append16(0, to: &central); append16(0, to: &central); append32(0, to: &central)
            append32(offset, to: &central); central.append(utf8)
        }
        let directory = output.count
        output.append(central); append32(0x06054b50, to: &output); append32(0, to: &output)
        append16(entries.count, to: &output); append16(entries.count, to: &output)
        append32(central.count, to: &output); append32(directory, to: &output); append16(0, to: &output)
        return output
    }
}

import Foundation

/// A minimal ZIP container writer.
///
/// An .xlsx file is a ZIP of XML parts, so writing real spreadsheets without a
/// third-party dependency means writing this. Entries are stored uncompressed
/// (method 0), which is fully valid ZIP — Excel, Numbers and every other reader
/// accept it, at the cost of a larger file. For a focus log that is a good trade:
/// no dependency to audit, no binary to trust.
struct ZipWriter {
    private struct Entry {
        let path: String
        let data: Data
        let crc32: UInt32
        let offset: UInt32
    }

    private var entries: [Entry] = []
    private var payload = Data()
    /// Fixed per archive so the same input produces the same bytes.
    private let modified: Date

    init(modified: Date = Date()) {
        self.modified = modified
    }

    mutating func add(path: String, contents: String) {
        add(path: path, data: Data(contents.utf8))
    }

    mutating func add(path: String, data: Data) {
        let crc = CRC32.checksum(data)
        let offset = UInt32(payload.count)
        let nameBytes = Data(path.utf8)
        let (time, date) = Self.dosTimestamp(modified)

        var header = Data()
        header.append(littleEndian: UInt32(0x0403_4b50))  // local file header
        header.append(littleEndian: UInt16(20))           // version needed
        header.append(littleEndian: UInt16(0))            // flags
        header.append(littleEndian: UInt16(0))            // method: stored
        header.append(littleEndian: time)
        header.append(littleEndian: date)
        header.append(littleEndian: crc)
        header.append(littleEndian: UInt32(data.count))   // compressed size
        header.append(littleEndian: UInt32(data.count))   // uncompressed size
        header.append(littleEndian: UInt16(nameBytes.count))
        header.append(littleEndian: UInt16(0))            // extra field length
        header.append(nameBytes)

        payload.append(header)
        payload.append(data)
        entries.append(Entry(path: path, data: data, crc32: crc, offset: offset))
    }

    func finalize() -> Data {
        var archive = payload
        let directoryOffset = UInt32(archive.count)
        let (time, date) = Self.dosTimestamp(modified)

        for entry in entries {
            let nameBytes = Data(entry.path.utf8)
            var header = Data()
            header.append(littleEndian: UInt32(0x0201_4b50)) // central directory header
            header.append(littleEndian: UInt16(20))          // version made by
            header.append(littleEndian: UInt16(20))          // version needed
            header.append(littleEndian: UInt16(0))           // flags
            header.append(littleEndian: UInt16(0))           // method: stored
            header.append(littleEndian: time)
            header.append(littleEndian: date)
            header.append(littleEndian: entry.crc32)
            header.append(littleEndian: UInt32(entry.data.count))
            header.append(littleEndian: UInt32(entry.data.count))
            header.append(littleEndian: UInt16(nameBytes.count))
            header.append(littleEndian: UInt16(0))           // extra length
            header.append(littleEndian: UInt16(0))           // comment length
            header.append(littleEndian: UInt16(0))           // disk number start
            header.append(littleEndian: UInt16(0))           // internal attributes
            header.append(littleEndian: UInt32(0))           // external attributes
            header.append(littleEndian: entry.offset)
            header.append(nameBytes)
            archive.append(header)
        }

        let directorySize = UInt32(archive.count) - directoryOffset

        var end = Data()
        end.append(littleEndian: UInt32(0x0605_4b50))        // end of central directory
        end.append(littleEndian: UInt16(0))                  // this disk
        end.append(littleEndian: UInt16(0))                  // disk with directory
        end.append(littleEndian: UInt16(entries.count))
        end.append(littleEndian: UInt16(entries.count))
        end.append(littleEndian: directorySize)
        end.append(littleEndian: directoryOffset)
        end.append(littleEndian: UInt16(0))                  // comment length
        archive.append(end)

        return archive
    }

    /// ZIP stores MS-DOS time: 2-second resolution, epoch 1980.
    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let year = max(1980, parts.year ?? 1980)
        let dosDate = UInt16(((year - 1980) << 9) | ((parts.month ?? 1) << 5) | (parts.day ?? 1))
        let dosTime = UInt16(((parts.hour ?? 0) << 11) | ((parts.minute ?? 0) << 5) | ((parts.second ?? 0) / 2))
        return (dosTime, dosDate)
    }
}

// MARK: - Little-endian appends

extension Data {
    mutating func append(littleEndian value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func append(littleEndian value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

// MARK: - CRC32

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1 == 1) ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

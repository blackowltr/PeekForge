import Foundation
import SQLite3

enum StructuredPreview {
    static func directory(_ url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: nil) else {
            return "Klasör okunamadı."
        }
        var lines = ["Klasör: \(url.lastPathComponent)", ""]
        var count = 0
        for case let item as URL in enumerator {
            enumerator.skipDescendants()
            count += 1
            if count > 100 { lines.append("… Daha fazla öğe var"); break }
            let directory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            lines.append((directory ? "📁 " : "   ") + item.lastPathComponent)
        }
        if count == 0 { lines.append("Boş klasör") }
        return lines.joined(separator: "\n")
    }

    static func sqlite(_ url: URL) -> String {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db = database else {
            if database != nil { sqlite3_close(database) }
            return "SQLite veritabanı açılamadı."
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 50)
        var statement: OpaquePointer?
        let query = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name LIMIT 21"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return "Tablo listesi okunamadı." }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cName = sqlite3_column_text(statement, 0) { names.append(String(cString: cName)) }
        }
        sqlite3_finalize(statement)
        if names.isEmpty { return "SQLite veritabanı: tablo bulunamadı." }
        var lines = ["SQLite veritabanı: \(url.lastPathComponent)", "Tablolar (ilk 20): \(names.prefix(20).joined(separator: ", "))", ""]
        if names.count > 20 { lines.append("… Başka tablolar da var\n") }
        for name in names.prefix(3) {
            let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
            let sql = "SELECT * FROM \"\(escaped)\" LIMIT 6"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            lines.append("▸ \(name)")
            let columns = min(Int(sqlite3_column_count(statement)), 8)
            lines.append((0..<columns).compactMap { sqlite3_column_name(statement, Int32($0)).map { String(cString: $0) } }.joined(separator: " | "))
            var rows = 0
            while rows < 5 && sqlite3_step(statement) == SQLITE_ROW {
                let cells = (0..<columns).map { index -> String in
                    let column = Int32(index)
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_NULL: return "NULL"
                    case SQLITE_BLOB: return "[BLOB]"
                    default:
                        let length = sqlite3_column_bytes(statement, column)
                        guard length <= 160, let value = sqlite3_column_text(statement, column) else { return "[uzun değer]" }
                        return String(cString: value).replacingOccurrences(of: "\n", with: " ")
                    }
                }
                lines.append(cells.joined(separator: " | "))
                rows += 1
            }
            if sqlite3_step(statement) == SQLITE_ROW { lines.append("…") }
            lines.append("")
            sqlite3_finalize(statement)
            statement = nil
        }
        return lines.joined(separator: "\n")
    }

    static func zip(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let tailLength = min(size, 65_557)
        try handle.seek(toOffset: size - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard tail.count >= 22 else { return "ZIP arşivi okunamadı." }
        func u16(_ data: Data, _ index: Int) -> Int? {
            guard index >= 0 && index + 2 <= data.count else { return nil }
            return Int(data[index]) | (Int(data[index + 1]) << 8)
        }
        func u32(_ data: Data, _ index: Int) -> Int? {
            guard let low = u16(data, index), let high = u16(data, index + 2) else { return nil }
            return low | (high << 16)
        }
        var eocd: Int?
        for index in stride(from: tail.count - 22, through: 0, by: -1) {
            if u32(tail, index) == 0x06054b50 { eocd = index; break }
        }
        guard let eocd, let offset = u32(tail, eocd + 16), let entries = u16(tail, eocd + 10),
              offset != 0xffffffff, entries != 0xffff, UInt64(offset) < size else {
            return "ZIP listesi okunamadı veya ZIP64 biçimi kullanılıyor."
        }
        try handle.seek(toOffset: UInt64(offset))
        let listing = try handle.read(upToCount: 1_000_000) ?? Data()
        var lines = ["ZIP arşivi: \(url.lastPathComponent)", "Öğe sayısı: \(entries)", ""]
        var cursor = 0
        var shown = 0
        while shown < min(entries, 100), u32(listing, cursor) == 0x02014b50,
              let nameLength = u16(listing, cursor + 28),
              let extraLength = u16(listing, cursor + 30),
              let commentLength = u16(listing, cursor + 32),
              cursor + 46 + nameLength + extraLength + commentLength <= listing.count {
            let nameData = listing[(cursor + 46)..<(cursor + 46 + nameLength)]
            let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? "[ad okunamadı]"
            lines.append(name)
            cursor += 46 + nameLength + extraLength + commentLength
            shown += 1
        }
        if entries > shown { lines.append("… \(entries - shown) öğe daha") }
        return lines.joined(separator: "\n")
    }

    static func tar(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        var offset: UInt64 = 0
        var lines = ["TAR arşivi: \(url.lastPathComponent)", ""]
        var count = 0
        while count < 100 && offset + 512 <= fileSize {
            try handle.seek(toOffset: offset)
            guard let header = try handle.read(upToCount: 512), header.count == 512 else { break }
            if header.allSatisfy({ $0 == 0 }) { break }
            let nameBytes = header.prefix(100).prefix(while: { $0 != 0 })
            let name = String(decoding: nameBytes, as: UTF8.self)
            let sizeBytes = header[124..<136].prefix(while: { $0 != 0 && $0 != 32 })
            guard let size = UInt64(String(decoding: sizeBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces), radix: 8) else { break }
            lines.append((header[156] == 53 ? "📁 " : "   ") + name)
            let blocks = (size + 511) / 512
            guard blocks <= (fileSize - offset - 512) / 512 else { break }
            offset += 512 + blocks * 512
            count += 1
        }
        if count == 100 { lines.append("… İlk 100 öğe gösteriliyor") }
        if count == 0 { lines.append("Öğe bulunamadı veya TAR biçimi desteklenmiyor.") }
        return lines.joined(separator: "\n")
    }

    static func delimited(_ text: String, separator: Character) -> String {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let character = text[cursor]
            cursor = text.index(after: cursor)
            if character == "\"" {
                if quoted && cursor < text.endIndex && text[cursor] == "\"" {
                    if field.count < 120 { field.append("\"") }
                    cursor = text.index(after: cursor)
                } else {
                    quoted.toggle()
                }
            } else if character == separator && !quoted {
                row.append(String(field.prefix(120)))
                field = ""
            } else if character == "\n" && !quoted {
                row.append(String(field.prefix(120)))
                rows.append(row)
                row = []
                field = ""
                if rows.count >= 50 { break }
            } else if field.count < 120 {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        let width = min(rows.map(\.count).max() ?? 0, 12)
        let sizes = (0..<width).map { column in min(24, rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0) }
        return rows.map { values in
            (0..<width).map { column in
                let value = column < values.count ? String(values[column].prefix(sizes[column])) : ""
                return value.padding(toLength: sizes[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n") + (rows.count >= 50 ? "\n… İlk 50 satır gösteriliyor" : "")
    }
}

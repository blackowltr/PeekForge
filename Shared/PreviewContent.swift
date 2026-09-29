import AppKit
import Foundation

enum PreviewContent {
    static let maxBytes = 2_000_000
    static let colorLimit = 200_000

    static func makeView(for url: URL) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainer?.widthTracksTextView = false
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView

        do {
            let preview = try load(url: url)
            let prefix = preview.truncated ? "Önizleme ilk \(preview.limit / 1_000) KB ile sınırlandı.\n\n" : ""
            textView.string = prefix + preview.text
            if !preview.truncated && (url.pathExtension.lowercased() == "json" || url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown") {
                highlight(textView, kind: url.pathExtension.lowercased())
            }
        } catch {
            textView.string = "Dosya açılamadı: \(error.localizedDescription)"
        }
        return scroll
    }

    private static func load(url: URL) throws -> (text: String, truncated: Bool, limit: Int) {
        let ext = url.lastPathComponent.lowercased().hasPrefix(".env") ? "env" : url.pathExtension.lowercased()
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return (StructuredPreview.directory(url), false, 0)
        }
        if ["sqlite", "sqlite3", "db"].contains(ext) {
            return (StructuredPreview.sqlite(url), false, 0)
        }
        if ext == "zip" {
            return (try StructuredPreview.zip(url), false, 0)
        }
        if ext == "tar" {
            return (try StructuredPreview.tar(url), false, 0)
        }
        let limit = ["csv", "tsv"].contains(ext) ? 256_000 : maxBytes
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: limit + 1) ?? Data()
        let truncated = bytes.count > limit
        let content = truncated ? Data(bytes.prefix(limit)) : bytes
        guard !content.contains(0) else { return ("İkili dosya metin olarak önizlenemiyor.", false, limit) }
        let text = String(decoding: content, as: UTF8.self)
        if ext == "csv" || ext == "tsv" {
            return (StructuredPreview.delimited(text, separator: ext == "csv" ? "," : "\t"), truncated, limit)
        }
        if ext == "env" {
            return (maskEnvironment(text), truncated, limit)
        }
        if ext == "json" && !truncated,
           let value = try? JSONSerialization.jsonObject(with: content, options: [.fragmentsAllowed]),
           let formatted = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .fragmentsAllowed]),
           let result = String(data: formatted, encoding: .utf8) {
            return (result, false, limit)
        }
        if ["jsonl", "ndjson"].contains(ext) && !truncated {
            return (formatJSONLines(text), false, limit)
        }
        return (text, truncated, limit)
    }

    private static func maskEnvironment(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { return String(line) }
            return String(line[...separator]) + "••••••••"
        }.joined(separator: "\n")
    }

    private static func formatJSONLines(_ text: String) -> String {
        var lines: [String] = []
        var count = 0
        text.enumerateLines { line, stop in
            count += 1
            if count > 200 {
                lines.append("… İlk 200 kayıt gösteriliyor")
                stop = true
                return
            }
            guard let data = line.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let normalized = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
                  let result = String(data: normalized, encoding: .utf8) else {
                lines.append("\(count)  \(line)")
                return
            }
            lines.append("\(count)  \(result)")
        }
        return lines.joined(separator: "\n")
    }

    private static func highlight(_ textView: NSTextView, kind: String) {
        let text = textView.string
        guard text.utf16.count <= colorLimit, let storage = textView.textStorage else { return }
        let pattern = kind == "json" ? #"\"(?:\\.|[^\"\\])*\"(?=\s*:)|\b(?:true|false|null)\b|-?\b\d+(?:\.\d+)?\b"# : #"(?m)^#{1,6} .+$|\*\*[^*]+\*\*|`[^`]+`"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        storage.beginEditing()
        for match in regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
        }
        storage.endEditing()
    }
}

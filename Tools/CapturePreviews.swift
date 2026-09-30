import AppKit
import Foundation

// README görsellerini uzantının kullandığı gerçek PreviewContent görünümünden üretir.
// Kullanım: swiftc Shared/*.swift Tools/CapturePreviews.swift -o /tmp/capture-previews && /tmp/capture-previews
@main
struct CapturePreviews {
    static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("docs/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let samples: [(String, String, String)] = [
            ("json", "ornek.json", """
            {"uygulama":"PeekForge","surum":"0.4.3","aktif":true,"ozellikler":["JSON önizleme","Finder entegrasyonu","otomatik güncelleme"],"ayarlar":{"tema":"sistem","sinir_mb":2}}
            """),
            ("csv", "ornek.csv", """
            dosya,tur,boyut,durum
            rapor.csv,CSV,24 KB,Hazır
            ayarlar.json,JSON,8 KB,Hazır
            notlar.md,Markdown,12 KB,Hazır
            arşiv.zip,ZIP,1.2 MB,Hazır
            """),
            ("env", ".env", """
            # Yerel geliştirme ayarları
            API_URL=https://example.com/api
            API_TOKEN=ornek-gizli-deger
            DATABASE_PASSWORD=ornek-parola
            DEBUG=true
            """)
        ]
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("peekforge-readme-samples-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        for (name, filename, content) in samples {
            let file = temporary.appendingPathComponent(filename)
            try content.write(to: file, atomically: true, encoding: .utf8)
            let size = NSSize(width: 800, height: 330)
            let preview = PreviewContent.makeView(for: file)
            preview.frame = NSRect(origin: .zero, size: size)
            preview.layoutSubtreeIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "Capture", code: 1) }
            bitmap.size = size
            preview.cacheDisplay(in: preview.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Capture", code: 2) }
            try data.write(to: output.appendingPathComponent("\(name).png"))
        }
    }
}

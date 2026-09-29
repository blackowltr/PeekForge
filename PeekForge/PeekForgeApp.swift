import AppKit

// Görünmez kapsayıcı. Önizlemeyi Finder, PeekForgePreview uzantısıyla sunar.
@main
final class PeekForgeApp: NSObject, NSApplicationDelegate {
    static func main() {
        if CommandLine.arguments.contains("--install-updater") || CommandLine.arguments.contains("--check-updates") {
            Updater.run(arguments: CommandLine.arguments)
            return
        }
        let app = NSApplication.shared
        let delegate = PeekForgeApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try Updater.installAgent() } catch { NSLog("PeekForge updater setup failed: %@", String(describing: error)) }
        NSApp.terminate(nil)
    }
}

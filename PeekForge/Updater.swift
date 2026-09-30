import AppKit
import CryptoKit
import Foundation

// Updates are signed independently of GitHub and verified before extraction.
enum Updater {
    private static let repository = "blackowltr/PeekForge"
    private static let publicKeyBase64 = "MBPwKUEd4fhtTbSVwK5s7o/I80m82cgeYb7F9eCuJZE="
    private static let bundleID = "com.example.PeekForge"
    private static let agentID = "com.peekforge.update"
    private static let maximumArchiveSize = 50_000_000

    static func run(arguments: [String]) {
        if arguments.contains("--install-updater") {
            do { try installAgent() } catch { fputs("PeekForge updater setup: \(error)\n", stderr); exit(1) }
            return
        }
        if arguments.contains("--check-updates") {
            Task {
                do { try await checkAndInstall() }
                catch { fputs("PeekForge update check: \(error)\n", stderr); exit(1) }
                exit(0)
            }
            dispatchMain()
        }
    }

    static func installAgent() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support/PeekForge", isDirectory: true)
        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try fm.createDirectory(at: agents, withIntermediateDirectories: true)
        let target = support.appendingPathComponent("PeekForgeUpdater")
        let temporary = support.appendingPathComponent("PeekForgeUpdater.new")
        if fm.fileExists(atPath: temporary.path) { try fm.removeItem(at: temporary) }
        guard let executable = Bundle.main.executableURL else { throw UpdateError.invalidApplication }
        try fm.copyItem(at: executable, to: temporary)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: temporary, to: target)
        let plist = agents.appendingPathComponent("\(agentID).plist")
        let settings: [String: Any] = [
            "Label": agentID,
            "ProgramArguments": [target.path, "--check-updates"],
            "StartInterval": 86_400,
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)
        let domain = "gui/\(getuid())"
        _ = process("/bin/launchctl", ["bootout", domain, plist.path])
        guard process("/bin/launchctl", ["bootstrap", domain, plist.path]) == 0 else { throw UpdateError.agentRegistration }
    }

    private static func checkAndInstall() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let installed = ProcessInfo.processInfo.environment["PEEKFORGE_TEST_APP_PATH"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent("Applications/PeekForge.app")
        guard let current = Bundle(url: installed), let currentVersion = current.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { throw UpdateError.invalidApplication }
        let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PeekForgeUpdater/1", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (releaseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        if http.statusCode == 404 { return } // No public release yet.
        guard http.statusCode == 200, releaseData.count < 1_000_000 else { throw UpdateError.invalidResponse }
        let release = try JSONDecoder().decode(Release.self, from: releaseData)
        guard release.tag_name.hasPrefix("v") else { throw UpdateError.invalidResponse }
        let version = String(release.tag_name.dropFirst())
        guard isNewer(version, than: currentVersion) else { return }
        guard let zip = release.assets.first(where: { $0.name == "PeekForge-macOS.zip" }),
              let sig = release.assets.first(where: { $0.name == "PeekForge-macOS.sig" }),
              zip.size > 0, zip.size <= maximumArchiveSize,
              safeAssetURL(zip.browser_download_url), safeAssetURL(sig.browser_download_url) else { throw UpdateError.invalidResponse }
        let (archiveURL, _) = try await session.download(from: zip.browser_download_url)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        let downloadedSize = try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard downloadedSize == zip.size, downloadedSize <= maximumArchiveSize else { throw UpdateError.invalidArchive }
        let (signatureData, signatureResponse) = try await session.data(from: sig.browser_download_url)
        guard (signatureResponse as? HTTPURLResponse)?.statusCode == 200,
              signatureData.count < 1_000,
              let signature = Data(base64Encoded: signatureData),
              let publicKeyRaw = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw),
              publicKey.isValidSignature(signature, for: try sha256(archiveURL)) else { throw UpdateError.invalidSignature }
        try install(archiveURL, expectedVersion: version, at: installed)
        _ = process("/usr/bin/qlmanage", ["-r"])
    }

    private static func install(_ archive: URL, expectedVersion: String, at target: URL) throws {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.appendingPathComponent("PeekForgeUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }
        guard process("/usr/bin/ditto", ["-x", "-k", archive.path, workspace.path]) == 0 else { throw UpdateError.invalidArchive }
        let extracted = workspace.appendingPathComponent("PeekForge.app")
        guard let bundle = Bundle(url: extracted),
              bundle.bundleIdentifier == bundleID,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion,
              process("/usr/bin/codesign", ["--verify", "--deep", "--strict", extracted.path]) == 0 else { throw UpdateError.invalidApplication }
        let stage = target.deletingLastPathComponent().appendingPathComponent(".PeekForge.next.app")
        let backup = target.deletingLastPathComponent().appendingPathComponent("PeekForge.previous.app")
        if fm.fileExists(atPath: stage.path) { try fm.removeItem(at: stage) }
        try fm.moveItem(at: extracted, to: stage)
        if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
        do {
            try fm.moveItem(at: target, to: backup)
            do { try fm.moveItem(at: stage, to: target) }
            catch { try? fm.moveItem(at: backup, to: target); throw error }
        } catch {
            // Some managed Mac environments allow writing the app but block renaming it.
            // The signed archive is already verified; keep a full backup before copying.
            if !fm.fileExists(atPath: target.path) { throw error }
            try fm.copyItem(at: target, to: backup)
            guard process("/usr/bin/ditto", [stage.path, target.path]) == 0,
                  process("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path]) == 0 else {
                _ = process("/usr/bin/ditto", [backup.path, target.path])
                throw UpdateError.invalidApplication
            }
            try? fm.removeItem(at: stage)
        }
        // Keep one previous version for recovery; refresh the detached updater binary.
        if let executable = Bundle(url: target)?.executableURL {
            let helper = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PeekForge/PeekForgeUpdater")
            let next = helper.deletingLastPathComponent().appendingPathComponent("PeekForgeUpdater.new")
            try? fm.removeItem(at: next)
            if (try? fm.copyItem(at: executable, to: next)) != nil {
                try? fm.removeItem(at: helper)
                try? fm.moveItem(at: next, to: helper)
            }
        }
    }

    private static func safeAssetURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/\(repository)/releases/download/")
    }

    private static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = installed.split(separator: ".").compactMap { Int($0) }
        guard a.count == 3, b.count == 3 else { return false }
        for index in 0..<3 { if a[index] != b[index] { return a[index] > b[index] } }
        return false
    }

    private static func sha256(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 65_536), !chunk.isEmpty { hash.update(data: chunk) }
        return Data(hash.finalize())
    }

    @discardableResult private static func process(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus }
        catch { return -1 }
    }
}

private struct Release: Decodable {
    let tag_name: String
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browser_download_url: URL
    }
}

private enum UpdateError: Error {
    case invalidApplication, invalidResponse, invalidArchive, invalidSignature, agentRegistration
}

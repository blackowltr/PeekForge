import CryptoKit
import Foundation

@main
struct SignRelease {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else { throw NSError(domain: "usage: SignRelease --generate-key <path> | --sign <key> <zip> <sig>", code: 1) }
        switch args[1] {
        case "--generate-key":
            let key = Curve25519.Signing.PrivateKey()
            let data = key.rawRepresentation.base64EncodedData()
            let url = URL(fileURLWithPath: args[2])
            guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw NSError(domain: "key write failed", code: 1) }
            print(key.publicKey.rawRepresentation.base64EncodedString())
        case "--sign":
            guard args.count == 5 else { throw NSError(domain: "usage: --sign <key> <zip> <sig>", code: 1) }
            let encoded = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            guard let raw = Data(base64Encoded: encoded), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { throw NSError(domain: "invalid key", code: 1) }
            let archive = try FileHandle(forReadingFrom: URL(fileURLWithPath: args[3]))
            defer { try? archive.close() }
            var hash = SHA256()
            while let chunk = try archive.read(upToCount: 65_536), !chunk.isEmpty { hash.update(data: chunk) }
            let signature = try key.signature(for: Data(hash.finalize()))
            try signature.base64EncodedData().write(to: URL(fileURLWithPath: args[4]), options: .atomic)
            print("Signed \(args[3])")
        case "--verify":
            guard args.count == 5, let raw = Data(base64Encoded: args[2]),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
                  let signature = Data(base64Encoded: try Data(contentsOf: URL(fileURLWithPath: args[4]))) else { throw NSError(domain: "invalid public key or signature", code: 1) }
            let archive = try FileHandle(forReadingFrom: URL(fileURLWithPath: args[3]))
            defer { try? archive.close() }
            var hash = SHA256()
            while let chunk = try archive.read(upToCount: 65_536), !chunk.isEmpty { hash.update(data: chunk) }
            guard key.isValidSignature(signature, for: Data(hash.finalize())) else { throw NSError(domain: "signature mismatch", code: 1) }
            print("Signature valid")
        default: throw NSError(domain: "unknown command", code: 1)
        }
    }
}

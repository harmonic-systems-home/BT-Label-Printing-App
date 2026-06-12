// btkeygen — mint complimentary "redeem-by" unlock keys for BTLabel.
//
//   swift run btkeygen newkeypair
//       Generates an Ed25519 keypair. Writes the PRIVATE key to
//       .btlabel-comp-private-key.txt (gitignored — keep it secret) and prints the
//       PUBLIC key to embed in the app (StoreManager.compPublicKeyB64).
//
//   swift run btkeygen sign <YYYY-MM-DD> [privateKeyFile]
//       Prints a key that must be redeemed before <date> (00:00 UTC). Once
//       redeemed before then, it unlocks the app for life.
//
//   swift run btkeygen verify <key> <publicKeyBase64>
//       Prints the redemption deadline (for testing).

import Foundation
import CryptoKit
import PTouchKit

func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }
let args = Array(CommandLine.arguments.dropFirst())
let privFileDefault = ".btlabel-comp-private-key.txt"

func deadline(from dateStr: String) -> Date {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "UTC"); df.locale = Locale(identifier: "en_US_POSIX")
    guard let d = df.date(from: dateStr) else { die("bad date '\(dateStr)' — use YYYY-MM-DD") }
    return d   // 00:00 UTC of that day
}

func loadPrivateKey(_ file: String) -> Curve25519.Signing.PrivateKey {
    guard let b64 = (try? String(contentsOfFile: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
          let data = Data(base64Encoded: b64),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
        die("could not read private key from \(file) — run `btkeygen newkeypair` first")
    }
    return key
}

switch args.first {
case "newkeypair":
    let priv = Curve25519.Signing.PrivateKey()
    do { try priv.rawRepresentation.base64EncodedString().write(toFile: privFileDefault, atomically: true, encoding: .utf8) }
    catch { die("could not write \(privFileDefault): \(error)") }
    print("Wrote private key to \(privFileDefault) (KEEP SECRET — it's gitignored).")
    print("Embed this public key in the app (StoreManager.compPublicKeyB64):")
    print(priv.publicKey.rawRepresentation.base64EncodedString())

case "sign":
    guard args.count >= 2 else { die("usage: btkeygen sign <YYYY-MM-DD> [privateKeyFile]") }
    let priv = loadPrivateKey(args.count >= 3 ? args[2] : privFileDefault)
    do {
        let key = try CompKey.make(deadline: deadline(from: args[1]), privateKey: priv)
        print("Redeem before \(args[1]) (00:00 UTC):")
        print(key)
    } catch { die("signing failed: \(error)") }

case "verify":
    guard args.count >= 3, let pubData = Data(base64Encoded: args[2]),
          let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else {
        die("usage: btkeygen verify <key> <publicKeyBase64>")
    }
    if let d = CompKey.verifiedDeadline(args[1], publicKey: pub) {
        let df = ISO8601DateFormatter()
        print("valid signature; redeem-by \(df.string(from: d)); \(Date() < d ? "still redeemable" : "EXPIRED")")
    } else { die("invalid key") }

default:
    die("usage: btkeygen newkeypair | sign <YYYY-MM-DD> [privKeyFile] | verify <key> <pubB64>")
}

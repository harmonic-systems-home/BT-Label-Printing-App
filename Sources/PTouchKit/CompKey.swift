import Foundation
import CryptoKit

/// A signed "redeem-by" complimentary unlock key.
///
/// A key carries a redemption **deadline** and an Ed25519 signature. The app
/// embeds the public key and verifies offline; the deadline is checked against the
/// current date *at redemption time*. A key redeemed before its deadline unlocks
/// for life; after the deadline it's inert. This lets you hand out time-bounded
/// free unlocks (e.g. "try the GUI, redeem before Aug 1") without minting an
/// everlasting token that could be shared forever.
///
/// Wire format: base64( version(1) ‖ deadlineEpochSeconds(UInt64 BE, 8) ‖ sig(64) ).
public enum CompKey {
    static let version: UInt8 = 1
    private static let payloadLen = 9          // 1 + 8
    private static let signatureLen = 64

    private static func payload(deadline: Date) -> Data {
        var data = Data([version])
        var be = UInt64(deadline.timeIntervalSince1970).bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        return data
    }

    /// Mint a signed key whose redemption deadline is `deadline`.
    public static func make(deadline: Date, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let p = payload(deadline: deadline)
        let sig = try privateKey.signature(for: p)
        return (p + sig).base64EncodedString()
    }

    /// Verify `key` against `publicKey`. Returns the redemption deadline if the
    /// signature is valid (the caller compares it to the current date), else nil.
    public static func verifiedDeadline(_ key: String, publicKey: Curve25519.Signing.PublicKey) -> Date? {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: cleaned), data.count == payloadLen + signatureLen else { return nil }
        let p = data.subdata(in: 0..<payloadLen)
        let sig = data.subdata(in: payloadLen..<payloadLen + signatureLen)
        guard p.first == version, publicKey.isValidSignature(sig, for: p) else { return nil }
        let secs = p.subdata(in: 1..<payloadLen).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Date(timeIntervalSince1970: TimeInterval(secs))
    }
}

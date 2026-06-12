import XCTest
import CryptoKit
@testable import PTouchKit

final class CompKeyTests: XCTestCase {
    func testRoundTrip() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let deadline = Date(timeIntervalSince1970: 1_780_000_000)   // some fixed instant
        let key = try CompKey.make(deadline: deadline, privateKey: priv)
        let got = CompKey.verifiedDeadline(key, publicKey: priv.publicKey)
        XCTAssertNotNil(got)
        XCTAssertEqual(got!.timeIntervalSince1970, deadline.timeIntervalSince1970, accuracy: 1)
    }

    func testTamperedKeyRejected() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let key = try CompKey.make(deadline: Date().addingTimeInterval(86_400), privateKey: priv)
        // Flip one character in the middle of the base64.
        var chars = Array(key); chars[chars.count / 2] = chars[chars.count / 2] == "A" ? "B" : "A"
        XCTAssertNil(CompKey.verifiedDeadline(String(chars), publicKey: priv.publicKey))
    }

    func testWrongPublicKeyRejected() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let other = Curve25519.Signing.PrivateKey()
        let key = try CompKey.make(deadline: Date().addingTimeInterval(86_400), privateKey: priv)
        XCTAssertNil(CompKey.verifiedDeadline(key, publicKey: other.publicKey))
    }

    func testGarbageRejected() {
        let priv = Curve25519.Signing.PrivateKey()
        XCTAssertNil(CompKey.verifiedDeadline("not-a-key", publicKey: priv.publicKey))
        XCTAssertNil(CompKey.verifiedDeadline("", publicKey: priv.publicKey))
    }
}

import Foundation

/// Values that text tokens resolve to for a given label in a print run.
public struct TokenContext: Sendable {
    public var index: Int
    public var count: Int
    public var name: String
    public var phone: String
    public var street: String
    public var email: String
    public var date: String

    public init(index: Int = 1, count: Int = 1, name: String = "", phone: String = "",
                street: String = "", email: String = "", date: String = "") {
        self.index = index; self.count = count; self.name = name; self.phone = phone
        self.street = street; self.email = email; self.date = date
    }
}

/// Expands substitution tokens in label text. Tokens are a slash followed by a
/// keyword (short or long form), not followed by another letter:
///   /i /index   current label number       /c /count   total in the run
///   /n /name    /p /phone   /s /street   /e /email   /d /date
/// e.g. "Box /i of /c" → "Box 3 of 25". Saved labels keep the raw tokens;
/// callers expand for preview and at print time (per copy).
public enum TextTokens {
    private static let regex = try! NSRegularExpression(
        pattern: #"/(index|count|name|phone|street|email|date|i|c|n|p|s|e|d)(?![A-Za-z])"#)

    public static func expand(_ s: String, _ ctx: TokenContext) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        regex.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += value(ns.substring(with: m.range(at: 1)), ctx)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func value(_ keyword: String, _ ctx: TokenContext) -> String {
        switch keyword.first {
        case "i": return String(ctx.index)
        case "c": return String(ctx.count)
        case "n": return ctx.name
        case "p": return ctx.phone
        case "s": return ctx.street
        case "e": return ctx.email
        case "d": return ctx.date
        default:  return ""
        }
    }
}

import Foundation

/// Values that text tokens resolve to for a given label in a print run.
public struct TokenContext: Sendable {
    public var index: Int
    public var count: Int
    public var name: String
    public var phone: String
    public var street: String
    public var email: String
    /// The reference date used by the /d (and /d1…/d5) date tokens.
    public var date: Date

    public init(index: Int = 1, count: Int = 1, name: String = "", phone: String = "",
                street: String = "", email: String = "", date: Date = Date()) {
        self.index = index; self.count = count; self.name = name; self.phone = phone
        self.street = street; self.email = email; self.date = date
    }
}

/// Expands substitution tokens in label text. A token is a slash followed by a
/// keyword (short or long form) and must end at a boundary — whitespace,
/// punctuation, or end of line — so it is *not* matched when followed by another
/// letter or digit (e.g. "/dog" and "/n5" stay literal):
///   /i /index   current label number       /c /count   total in the run
///   /n /name    /p /phone   /s /street   /e /email
///   /d /date    today's date (localized medium). Format variants:
///     /d1 6/14/26 · /d2 06/14/2026 · /d3 2026-06-14 · /d4 14 Jun 2026 · /d5 June 14, 2026
/// e.g. "Box /i of /c" → "Box 3 of 25". Saved labels keep the raw tokens;
/// callers expand for preview and at print time (per copy).
public enum TextTokens {
    private static let regex = try! NSRegularExpression(
        pattern: #"/((?:date|d)[1-9]?|index|count|name|phone|street|email|i|c|n|p|s|e)(?![A-Za-z0-9])"#)

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
        if keyword.first == "d" {
            let selector = keyword.last.flatMap { $0.isNumber ? Int(String($0)) : nil } ?? 0
            return formattedDate(ctx.date, selector: selector)
        }
        switch keyword.first {
        case "i": return String(ctx.index)
        case "c": return String(ctx.count)
        case "n": return ctx.name
        case "p": return ctx.phone
        case "s": return ctx.street
        case "e": return ctx.email
        default:  return ""
        }
    }

    /// Format `date` for /d (selector 0, localized medium) or /d1…/d5.
    private static func formattedDate(_ date: Date, selector: Int) -> String {
        let df = DateFormatter()
        df.locale = .current
        switch selector {
        case 1: df.dateFormat = "M/d/yy"
        case 2: df.dateFormat = "MM/dd/yyyy"
        case 3: df.dateFormat = "yyyy-MM-dd"
        case 4: df.dateFormat = "d MMM yyyy"
        case 5: df.dateFormat = "MMMM d, yyyy"
        default: df.dateStyle = .medium; df.timeStyle = .none
        }
        return df.string(from: date)
    }
}

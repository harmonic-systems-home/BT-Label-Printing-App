import XCTest
@testable import PTouchKit

final class TextTokensTests: XCTestCase {
    // A fixed reference date so format assertions are stable: 2026-06-14.
    private var fixedDate: Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 14
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func ctx() -> TokenContext {
        TokenContext(index: 3, count: 25, name: "Acme", phone: "555-1212",
                     street: "1 Main St", email: "a@b.co", date: fixedDate)
    }

    func testBasicSubstitution() {
        XCTAssertEqual(TextTokens.expand("Box /i of /c", ctx()), "Box 3 of 25")
        XCTAssertEqual(TextTokens.expand("/n /p", ctx()), "Acme 555-1212")
    }

    // A token only applies at a boundary (space, punctuation, end) — not when
    // followed by another letter or digit.
    func testBoundaryRequired() {
        XCTAssertEqual(TextTokens.expand("/index!", ctx()), "3!")
        XCTAssertEqual(TextTokens.expand("/dog", ctx()), "/dog")    // letter follows
        XCTAssertEqual(TextTokens.expand("/n5", ctx()), "/n5")      // digit follows /n
        XCTAssertEqual(TextTokens.expand("/i.", ctx()), "3.")
    }

    func testDateFormats() {
        XCTAssertEqual(TextTokens.expand("/d3", ctx()), "2026-06-14")
        XCTAssertEqual(TextTokens.expand("/d2", ctx()), "06/14/2026")
        XCTAssertEqual(TextTokens.expand("/d1", ctx()), "6/14/26")
        // Unknown selectors aren't tokens at all (the digit breaks the boundary).
        XCTAssertEqual(TextTokens.expand("/d12", ctx()), "/d12")
    }
}

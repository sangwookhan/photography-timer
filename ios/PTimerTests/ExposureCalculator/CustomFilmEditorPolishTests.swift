import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// App-view polish helpers that stay app-hosted: the compact
/// row-duration display formatter (`rowDurationDisplayValue`) and the
/// common-ISO chip list (`customFilmEditorCommonISOs`), both defined in
/// the app's editor views. The pure form-state / formatter / splitter
/// tests moved off-simulator to `CustomFilmEditorFormulaPresentationTests`
/// in PTimerKitTests.
final class CustomFilmEditorPolishTests: XCTestCase {

    /// rowDurationDisplayValue maps each raw input to its rendered
    /// row text and placeholder flag (seconds/minutes/sub-second units,
    /// empty -> placeholder, unparseable -> echo, and the Unlimited
    /// token honoured or echoed per allowsUnlimited). Each input ->
    /// expected is a case row.
    func test_rowDurationDisplayValue_rendersExpectedTextPerInput() {
        struct Case {
            let name: String
            let input: String
            let placeholder: String
            let allowsUnlimited: Bool
            let expectedText: String
            let expectedPlaceholder: Bool?
        }
        let cases: [Case] = [
            Case(name: "seconds", input: "2", placeholder: "1s", allowsUnlimited: false, expectedText: "2s", expectedPlaceholder: false),
            Case(name: "minutes", input: "200", placeholder: "1s", allowsUnlimited: false, expectedText: "3.3m", expectedPlaceholder: false),
            Case(name: "sub-second leading zero", input: "0.5", placeholder: "0s", allowsUnlimited: false, expectedText: "0.50s", expectedPlaceholder: nil),
            Case(name: "empty -> placeholder", input: "", placeholder: "1s", allowsUnlimited: false, expectedText: "1s", expectedPlaceholder: true),
            Case(name: "unparseable echoes raw text", input: "abc", placeholder: "1s", allowsUnlimited: false, expectedText: "abc", expectedPlaceholder: false),
            Case(name: "unlimited token when allowed", input: "Unlimited", placeholder: "Unlimited", allowsUnlimited: true, expectedText: "Unlimited", expectedPlaceholder: false),
            Case(name: "anchor row echoes unlimited (not allowed)", input: "Unlimited", placeholder: "1s", allowsUnlimited: false, expectedText: "Unlimited", expectedPlaceholder: nil),
        ]
        for c in cases {
            let value = rowDurationDisplayValue(c.input, placeholder: c.placeholder, allowsUnlimited: c.allowsUnlimited)
            XCTAssertEqual(value.text, c.expectedText, "[\(c.name)] text")
            if let expectedPlaceholder = c.expectedPlaceholder {
                XCTAssertEqual(value.isPlaceholder, expectedPlaceholder, "[\(c.name)] placeholder")
            }
        }
    }

    // MARK: - ISO chip list

    func test_commonISOs_includes320_atStablePosition() {
        // The user noticed ISO 320 could not be chosen from chips.
        // Pin the order so a future expansion does not silently
        // regress the layout.
        XCTAssertEqual(
            customFilmEditorCommonISOs,
            [
                "6", "12", "20", "25", "50", "64", "80", "100", "125",
                "160", "200", "250", "320", "400", "500", "640", "800",
                "1000", "1250", "1600", "3200",
            ]
        )
        XCTAssertTrue(customFilmEditorCommonISOs.contains("320"))
    }
}

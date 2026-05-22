import XCTest
@testable import PTimer

final class SecondaryGuidancePresentationTests: XCTestCase {
    func test5MFormatsAsNeutralColorCorrection() {
        let rows = ReciprocitySecondaryGuidanceFormatter.format([
            .colorFilter(ColorFilterRecommendation(filterName: "5M", note: nil))
        ])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .colorCorrection)
        XCTAssertEqual(rows[0].title, "Color correction")
        XCTAssertEqual(rows[0].valueText, "5M")
        XCTAssertEqual(rows[0].severity, .neutral)
    }

    func testDecimal7Point5MNotationIsPreservedVerbatim() {
        let rows = ReciprocitySecondaryGuidanceFormatter.format([
            .colorFilter(ColorFilterRecommendation(filterName: "7.5M", note: nil))
        ])

        XCTAssertEqual(rows.map(\.valueText), ["7.5M"])
    }

    func testGreenChannel2Point5GNotationIsPreservedVerbatim() {
        let rows = ReciprocitySecondaryGuidanceFormatter.format([
            .colorFilter(ColorFilterRecommendation(filterName: "2.5G", note: nil))
        ])

        XCTAssertEqual(rows.map(\.valueText), ["2.5G"])
    }

    func testKodakCC10RNotationIsPreservedVerbatim() {
        let rows = ReciprocitySecondaryGuidanceFormatter.format([
            .colorFilter(ColorFilterRecommendation(filterName: "CC10R", note: nil))
        ])

        XCTAssertEqual(rows.map(\.valueText), ["CC10R"])
    }

    func testNegativeTenPercentDevelopmentFormatsAsDevelopmentAdjustment() {
        let rows = ReciprocitySecondaryGuidanceFormatter.format([
            .development(DevelopmentAdjustment(instruction: "-10% development", note: nil))
        ])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .developmentAdjustment)
        XCTAssertEqual(rows[0].valueText, "-10% development")
        XCTAssertNotEqual(rows[0].kind, .colorCorrection)
    }

    func testNotRecommendedWarningMapsToStopSeverity() {
        let rows = ReciprocitySecondaryGuidanceFormatter.format([
            .warning(ReciprocityWarning(severity: .notRecommended, message: "64 sec is not recommended."))
        ])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .warning)
        XCTAssertNil(rows[0].valueText)
        XCTAssertEqual(rows[0].severity, .stop)
        XCTAssertEqual(rows[0].detailText, "64 sec is not recommended.")
    }

    func testFreeTextNoteRemainsNoteWithoutInventedNumericValue() {
        let text = "additional yellow / cyan correction"
        let rows = ReciprocitySecondaryGuidanceFormatter.format([
            .note(ReciprocityNote(text: text))
        ])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .note)
        XCTAssertNil(rows[0].valueText)
        XCTAssertEqual(rows[0].detailText, text)
        XCTAssertEqual(rows[0].severity, .caution)
    }

    func testEmptyAndExposureOnlyInputsProduceNoSecondaryRows() {
        let emptyRows = ReciprocitySecondaryGuidanceFormatter.format([])
        let exposureOnlyRows = ReciprocitySecondaryGuidanceFormatter.format([
            .exposure(.correctedTime(CorrectedTimeMapping(correctedSeconds: 64)))
        ])

        XCTAssertTrue(emptyRows.isEmpty)
        XCTAssertTrue(exposureOnlyRows.isEmpty)
    }

    func testMixedSecondaryGuidancePreservesInputOrderAndKinds() {
        let adjustments: [ReciprocityAdjustment] = [
            .colorFilter(ColorFilterRecommendation(filterName: "5M", note: nil)),
            .warning(ReciprocityWarning(severity: .notRecommended, message: "64 sec is not recommended.")),
            .development(DevelopmentAdjustment(instruction: "-10% development", note: nil)),
            .note(ReciprocityNote(text: "test under your conditions")),
        ]

        let rows = ReciprocitySecondaryGuidanceFormatter.format(adjustments)

        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.kind), [.colorCorrection, .warning, .developmentAdjustment, .note])
    }
}

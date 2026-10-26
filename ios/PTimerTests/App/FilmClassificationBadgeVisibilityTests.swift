// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimer

final class FilmClassificationBadgeVisibilityTests: XCTestCase {
    func testBadgeWaitsThreeSecondsBeforeFadeBegins() {
        XCTAssertEqual(FilmClassificationBadgeVisibility.visibleDuration, .seconds(3))
        XCTAssertFalse(FilmClassificationBadgeVisibility.shouldBeginFade(after: .milliseconds(2_999)))
        XCTAssertTrue(FilmClassificationBadgeVisibility.shouldBeginFade(after: .seconds(3)))
        XCTAssertTrue(FilmClassificationBadgeVisibility.shouldBeginFade(after: .milliseconds(3_001)))
    }

    func testOnlyReturningToMainCountsAsAReentryEvent() {
        XCTAssertTrue(FilmClassificationBadgeVisibility.isMainReturn(wasCovered: true, isCovered: false))
        XCTAssertFalse(FilmClassificationBadgeVisibility.isMainReturn(wasCovered: false, isCovered: false))
        XCTAssertFalse(FilmClassificationBadgeVisibility.isMainReturn(wasCovered: true, isCovered: true))
    }

    func testNewRevealInvalidatesOlderHideEvent() {
        var visibility = FilmClassificationBadgeVisibility()

        let firstGeneration = visibility.reveal(isActiveFilm: true)
        let secondGeneration = visibility.reveal(isActiveFilm: true)
        visibility.hide(ifGeneration: firstGeneration)

        XCTAssertTrue(visibility.isVisible)
        XCTAssertGreaterThan(secondGeneration, firstGeneration)

        visibility.hide(ifGeneration: secondGeneration)
        XCTAssertFalse(visibility.isVisible)
    }

    func testNoFilmClearsImmediatelyAndInvalidatesPendingHide() {
        var visibility = FilmClassificationBadgeVisibility()
        let pendingGeneration = visibility.reveal(isActiveFilm: true)

        _ = visibility.reveal(isActiveFilm: false)
        visibility.hide(ifGeneration: pendingGeneration)

        XCTAssertFalse(visibility.isVisible)
    }

    func testKoreanFilmColorValueUsesFilmSpecificTranslation() {
        guard
            let appBundle = Bundle(identifier: "com.sangwook.PTimer.dev"),
            let koreanBundleURL = appBundle.url(forResource: "ko", withExtension: "lproj"),
            let koreanBundle = Bundle(url: koreanBundleURL)
        else {
            XCTFail("The app's Korean localization bundle must be available to app-hosted tests.")
            return
        }
        XCTAssertEqual(
            koreanBundle.localizedString(forKey: "film-color-value", value: nil, table: "Localizable"),
            "컬러"
        )
    }
}

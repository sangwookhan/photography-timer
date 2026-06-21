// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore

/// Structural guard on the `UnofficialPracticalProfiles` registry —
/// the supplementary, non-launch profiles described in DomainSchema
/// §13.3. These profiles are bundled outside the launch catalog file
/// and serve as secondary alternatives to the official primary
/// profile on a film identity.
///
/// Invariants enforced here:
///
/// - `authority == .unofficial` — these profiles do not claim
///   manufacturer endorsement.
/// - The profile carries at least one formula rule (the practical
///   approximation is closed-form).
/// - No limited-guidance rule (a limited-guidance rule belongs only
///   on the official threshold + limited-guidance shape).
/// - The compiler-enforced absence of `.table` is verified by the
///   exhaustive switch (the domain no longer carries a `.table`
///   case).
/// - The profile is not registered in `LaunchPresetFilmCatalog.films`
///   under either id or canonical stock name reuse.
final class UnofficialPracticalProfilesShapeTests: XCTestCase {

    // MARK: - Registry coverage

    /// The registry resolves the Kodak Portra 400 unofficial practical
    /// profile by film id. The registry is intentionally narrow today;
    /// this test pins the single shipped registration so future
    /// changes to the lookup table are deliberate.
    func testRegistryResolvesTheUnofficialPracticalProfile() {
        let profile = UnofficialPracticalProfiles.profile(forFilmID: "kodak-portra-400")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.id, "kodak-portra-400-unofficial-practical")
    }

    func testRegistryReturnsNilForUnknownFilmID() {
        XCTAssertNil(UnofficialPracticalProfiles.profile(forFilmID: "ilford-hp5-plus-400"))
        XCTAssertNil(UnofficialPracticalProfiles.profile(forFilmID: "nonexistent-film"))
    }

    // MARK: - Shape invariants

    func testUnofficialPracticalProfileCarriesUnofficialAuthority() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        XCTAssertEqual(profile.source.authority, .unofficial)
    }

    func testUnofficialPracticalProfileSourceKindIsThirdPartyPublication() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        XCTAssertEqual(profile.source.kind, .thirdPartyPublication)
    }

    func testUnofficialPracticalProfileCarriesFormulaRule() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        let hasFormula = profile.rules.contains { rule in
            if case .formula = rule { return true }
            return false
        }
        XCTAssertTrue(hasFormula)
    }

    func testUnofficialPracticalProfileHasNoLimitedGuidanceRule() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        let hasLimitedGuidance = profile.rules.contains { rule in
            if case .limitedGuidance = rule { return true }
            return false
        }
        XCTAssertFalse(hasLimitedGuidance)
    }

    /// Exhaustive switch over the surviving rule variants. The
    /// structural guarantee that `.table` is gone is enforced by the
    /// compiler — adding a `.table` case back to `ReciprocityRule`
    /// breaks this file's compile.
    func testUnofficialPracticalProfileContainsOnlyKnownRuleVariants() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        for rule in profile.rules {
            switch rule {
            case .threshold, .formula, .limitedGuidance, .tableInterpolation:
                continue
            }
        }
    }

    func testUnofficialPracticalProfileUsesEmptyPublisherAsSourcePendingMarker() {
        // DomainSchema §4: launch (official) profiles require a
        // non-empty publisher; supplementary unofficial profiles use
        // an empty `publisher` as the documented "source pending
        // verification" marker so the presenter suppresses the Sources
        // section and conveys the disclosure through the
        // unofficial-authority subtitle plus the profile's caveat
        // note.
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        XCTAssertEqual(profile.source.publisher, "")
        XCTAssertNil(profile.source.citation)
        XCTAssertNil(profile.source.title)
    }

    // MARK: - Launch catalog isolation

    /// Unofficial practical profiles must not appear in the launch
    /// catalog file. They are bundled separately so the launch shape
    /// allow-list (DomainSchema §13) stays restricted to the two
    /// official shapes.
    @MainActor
    func testUnofficialPracticalProfileIsNotPartOfLaunchCatalog() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        let launchProfileIDs = LaunchPresetFilmCatalog.films.flatMap { film in
            film.profiles.map(\.id)
        }
        XCTAssertFalse(
            launchProfileIDs.contains(profile.id),
            "Unofficial practical profile '\(profile.id)' must not be shipped through the launch catalog."
        )
    }
}

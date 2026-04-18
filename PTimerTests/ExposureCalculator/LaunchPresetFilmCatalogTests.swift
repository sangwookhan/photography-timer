import XCTest
@testable import PTimer

final class LaunchPresetFilmCatalogTests: XCTestCase {
    func testLaunchPresetFilmCatalogRespectsPTIMER86LaunchPolicyConstraints() {
        XCTAssertFalse(LaunchPresetFilmCatalog.films.isEmpty)

        for film in LaunchPresetFilmCatalog.films {
            XCTAssertEqual(film.kind, .preset)
            XCTAssertEqual(film.productionStatus, .current)
            XCTAssertEqual(film.profiles.count, 1, "Launch flow should use one primary profile per film identity.")
            XCTAssertFalse(film.canonicalStockName.isEmpty)

            let profile = film.profiles[0]
            XCTAssertEqual(profile.source.kind, .manufacturerPublished)
            XCTAssertEqual(profile.source.authority, .official)
        }
    }

    func testLaunchPresetFilmCatalogUsesCanonicalFilmIdentitiesWithoutDuplicateIDs() {
        let identifiers = LaunchPresetFilmCatalog.films.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }
}

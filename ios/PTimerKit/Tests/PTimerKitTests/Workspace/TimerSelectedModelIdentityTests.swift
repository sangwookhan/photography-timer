// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-171: a timer started from a multi-model film must retain
/// enough selected-reciprocity-model identity to distinguish the
/// chosen calculation model after start, restore, and clone.
///
/// The carrier is `selectedModelLabel`, captured at start by
/// `TimerStartComposer`: non-nil only for a non-default model whose
/// identity the authority qualifier cannot carry (official alternates
/// like Tri-X's "App formula", source-named unofficial tables like
/// "Ohzart"). `nil` means the film's default model, so default-path
/// and pre-PTIMER-171 timers render exactly as before.
@MainActor
final class TimerSelectedModelIdentityTests: XCTestCase {

    // MARK: - Composer derivation

    func testOfficialAlternateModelsCaptureDistinguishingLabels() throws {
        // Tri-X 400's three official models: default graph/table (no
        // label — it is the default), the 3-row official table
        // ("Official table" selector label), and the app-derived
        // formula (profile-name fallback).
        let film = try film("kodak-tri-x-400")

        XCTAssertNil(
            compose(film: film, override: nil).selectedModelLabel,
            "The default model needs no label — nil keeps default timers unchanged."
        )

        let officialTable = try alternate(filmID: film.id, profileID: "kodak-tri-x-official-table")
        XCTAssertEqual(
            compose(film: film, override: officialTable).selectedModelLabel,
            "Official table",
            "A source-named selectorLabel wins when present."
        )

        let appFormula = try alternate(filmID: film.id, profileID: "kodak-tri-x-app-formula")
        let appPayload = compose(film: film, override: appFormula)
        XCTAssertEqual(
            appPayload.selectedModelLabel,
            "App formula",
            "An official alternate without a selectorLabel falls back to its profile name."
        )
        XCTAssertNil(
            appPayload.filmProfileQualifier,
            "Official alternates carry no authority qualifier — the model label is the only distinguisher."
        )
    }

    func testOhzartCommunityTableKeepsSourceNamedLabel() throws {
        let film = try film("foma-fomapan-100")
        let ohzart = try alternate(
            filmID: film.id,
            profileID: "foma-fomapan-100-ohzart-community-table"
        )
        let payload = compose(film: film, override: ohzart)
        XCTAssertEqual(
            payload.selectedModelLabel,
            "Ohzart",
            "The community table keeps its source name, not only a generic qualifier."
        )
        XCTAssertEqual(
            payload.filmProfileQualifier,
            "Unofficial",
            "The authority qualifier still travels with the timer unchanged."
        )
    }

    func testUnofficialOverrideWithoutSelectorLabelKeepsQualifierOnly() throws {
        // Portra 400's unofficial practical approximation has no
        // selectorLabel; its official-sounding profile name must not
        // displace the Unofficial caution, so the label stays nil.
        let film = try film("kodak-portra-400")
        let practical = try alternate(
            filmID: film.id,
            profileID: "kodak-portra-400-unofficial-practical"
        )
        let payload = compose(film: film, override: practical)
        XCTAssertNil(payload.selectedModelLabel)
        XCTAssertEqual(payload.filmProfileQualifier, "Unofficial")
    }

    func testCustomProfileIdentityIsUnchanged() throws {
        // Custom films have a single user-defined profile and no
        // override; their identity keeps flowing through the Custom
        // qualifier + customProfileSummary, with no model label.
        let customProfile = ReciprocityProfile(
            id: "custom.test-formula",
            name: "My night formula",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(exponent: 1.3, noCorrectionThroughSeconds: 1)
                )),
            ]
        )
        let customFilm = FilmIdentity(
            id: "custom.film",
            kind: .custom,
            canonicalStockName: "My Film",
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [customProfile]
        )
        let payload = compose(film: customFilm, override: nil)
        XCTAssertNil(payload.selectedModelLabel)
        XCTAssertEqual(payload.filmProfileQualifier, "Custom")
        XCTAssertNotNil(payload.customProfileSummary)
    }

    // MARK: - Timer card rendering

    func testFilmDescriptorPrefersModelLabelOverQualifier() {
        let ohzart = identitySnapshot(
            film: "Fomapan 100 Classic",
            qualifier: "Unofficial",
            modelLabel: "Ohzart"
        )
        XCTAssertEqual(
            TimerCardIdentityPresenter.filmDescriptor(for: ohzart),
            "Fomapan 100 Classic · Ohzart",
            "A source-named model label is strictly more specific than the generic qualifier."
        )

        let appFormula = identitySnapshot(
            film: "Tri-X 400",
            qualifier: nil,
            modelLabel: "App formula"
        )
        XCTAssertEqual(
            TimerCardIdentityPresenter.filmDescriptor(for: appFormula),
            "Tri-X 400 · App formula"
        )
    }

    func testFilmDescriptorWithoutModelLabelRendersAsBefore() {
        XCTAssertEqual(
            TimerCardIdentityPresenter.filmDescriptor(
                for: identitySnapshot(film: "Portra 400", qualifier: "Unofficial", modelLabel: nil)
            ),
            "Portra 400 · Unofficial"
        )
        XCTAssertEqual(
            TimerCardIdentityPresenter.filmDescriptor(
                for: identitySnapshot(film: "Tri-X 400", qualifier: nil, modelLabel: nil)
            ),
            "Tri-X 400"
        )
    }

    // MARK: - Persistence

    func testPersistedSnapshotRoundTripsModelLabel() throws {
        let snapshot = PersistentTimerMetadataSnapshot(
            id: UUID(),
            order: 3,
            name: "Tri-X 400 - 20m",
            basisSummary: "Base 1/30s · 6 stops",
            filmDisplayName: "Tri-X 400",
            selectedModelLabel: "App formula"
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: data)
        XCTAssertEqual(decoded.selectedModelLabel, "App formula")
    }

    func testLegacySnapshotWithoutModelLabelDecodesNil() throws {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "order": 1,
          "name": "Legacy - 30s",
          "basisSummary": "Base 1/30s · 6 stops",
          "filmDisplayName": "Fomapan 100 Classic",
          "filmProfileQualifier": "Unofficial"
        }
        """
        let decoded = try JSONDecoder().decode(
            PersistentTimerMetadataSnapshot.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertNil(decoded.selectedModelLabel, "Pre-PTIMER-171 snapshots must decode unchanged.")
        XCTAssertEqual(decoded.filmProfileQualifier, "Unofficial")
    }

    // MARK: - Workspace start / restore / clone

    func testStartPersistsAndPublishesModelLabel() throws {
        let store = SpyMetadataStore()
        let model = makeModel(store: store)

        let id = model.startTimer(
            duration: 60,
            name: "Tri-X 400 - 1m",
            basisSummary: "Base 1/30s · 6 stops",
            filmDisplayName: "Tri-X 400",
            exposureSource: .filmCorrectedExposure,
            selectedModelLabel: "App formula"
        )
        XCTAssertNotNil(id)

        let item = try XCTUnwrap(model.timers.first { $0.id == id })
        XCTAssertEqual(item.selectedModelLabel, "App formula")
        XCTAssertEqual(
            item.identitySnapshot?.selectedModelLabel,
            "App formula",
            "The identity snapshot must expose the label to presentation surfaces."
        )

        let persisted = try XCTUnwrap(store.savedSnapshots.last?.timers.first { $0.id == id })
        XCTAssertEqual(persisted.selectedModelLabel, "App formula")
    }

    func testRestoredMetadataCarriesModelLabel() throws {
        let timerID = UUID()
        let store = SpyMetadataStore(
            initialSnapshot: PersistentTimerMetadataCollection(
                nextTimerOrder: 2,
                timers: [
                    PersistentTimerMetadataSnapshot(
                        id: timerID,
                        order: 1,
                        name: "Fomapan 100 Classic - 2m",
                        basisSummary: "Base 1s · 2 stops",
                        filmDisplayName: "Fomapan 100 Classic",
                        filmProfileQualifier: "Unofficial",
                        exposureSourceRaw: ExposureTimerSource.filmCorrectedExposure.rawValue,
                        selectedModelLabel: "Ohzart"
                    ),
                ]
            )
        )
        // Mirror the relaunch flow: the runtime already holds the
        // timer STATE under the same id before the workspace model
        // comes up (in production the real TimerManager restores its
        // own state snapshot first); the model then binds the restored
        // metadata to that state during its initial sync.
        let manager = RuntimeBackedTimerManaging(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        _ = manager.start(id: timerID, duration: 120)
        let model = TimerWorkspaceModel(
            timerManager: manager,
            metadataPersistenceStore: store,
            defaultName: { duration in "Timer - \(duration)s" }
        )

        let item = try XCTUnwrap(model.timers.first { $0.id == timerID })
        XCTAssertEqual(item.selectedModelLabel, "Ohzart")
        XCTAssertEqual(item.filmProfileQualifier, "Unofficial")
        XCTAssertEqual(item.name, "Fomapan 100 Classic - 2m")
    }

    func testCloneInheritsModelLabel() throws {
        let source = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Tri-X 400 - 1m",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 60,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: Date(timeIntervalSince1970: 120),
            filmDisplayName: "Tri-X 400",
            exposureSource: .filmCorrectedExposure,
            selectedModelLabel: "App formula"
        )
        let store = SpyMetadataStore()
        let model = makeModel(store: store)

        let cloneID = try XCTUnwrap(model.startTimer(cloning: source))
        let clone = try XCTUnwrap(model.timers.first { $0.id == cloneID })
        XCTAssertEqual(
            clone.selectedModelLabel,
            "App formula",
            "Clone must not silently switch the model identity."
        )
    }

    // MARK: - Helpers

    private func compose(
        film: FilmIdentity,
        override: ReciprocityProfile?
    ) -> TimerStartComposer.Payload {
        TimerStartComposer(formatShutter: { "\($0)s" }).compose(
            TimerStartComposer.Input(
                targetDuration: 60,
                result: nil,
                filmModeResult: nil,
                source: .filmAdjustedShutter,
                selectedPresetFilm: film,
                selectedProfileOverride: override,
                activeCameraSlot: nil,
                targetShutterSeconds: nil
            )
        )
    }

    private func identitySnapshot(
        film: String,
        qualifier: String?,
        modelLabel: String?
    ) -> ExposureTimerIdentitySnapshot {
        ExposureTimerIdentitySnapshot(
            cameraSlot: nil,
            filmDisplayName: film,
            filmProfileQualifier: qualifier,
            exposureSource: .filmCorrectedExposure,
            selectedModelLabel: modelLabel
        )
    }

    private func makeModel(store: SpyMetadataStore) -> TimerWorkspaceModel {
        TimerWorkspaceModel(
            timerManager: RuntimeBackedTimerManaging(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            metadataPersistenceStore: store,
            defaultName: { duration in "Timer - \(duration)s" }
        )
    }

    private func film(
        _ filmID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FilmIdentity {
        try XCTUnwrap(
            LaunchPresetFilmCatalogV2.films.first { $0.id == filmID },
            "\(filmID) must remain in the launch catalog.",
            file: file,
            line: line
        )
    }

    private func alternate(
        filmID: String,
        profileID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ReciprocityProfile {
        try XCTUnwrap(
            AlternateReciprocityModels.alternates(forFilmID: filmID)
                .first { $0.id == profileID },
            "\(profileID) must be registered as an alternate.",
            file: file,
            line: line
        )
    }
}

private final class SpyMetadataStore: TimerMetadataPersistenceStoring {
    private let initialSnapshot: PersistentTimerMetadataCollection?
    private(set) var savedSnapshots: [PersistentTimerMetadataCollection] = []

    init(initialSnapshot: PersistentTimerMetadataCollection? = nil) {
        self.initialSnapshot = initialSnapshot
    }

    func loadSnapshot() -> PersistentTimerMetadataCollection? {
        initialSnapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection) {
        savedSnapshots.append(snapshot)
    }

    func clearSnapshot() {}
}

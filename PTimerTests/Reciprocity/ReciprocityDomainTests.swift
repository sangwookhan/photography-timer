import XCTest
@testable import PTimer

final class ReciprocityDomainTests: XCTestCase {
    func testFormulaBasedOfficialFilmCanExpressExponentProfile() throws {
        let film = makeHP5PlusFilm()

        XCTAssertEqual(film.kind, .preset)
        XCTAssertEqual(film.productionStatus, .current)
        XCTAssertEqual(film.manufacturer, "ILFORD / HARMAN")
        XCTAssertEqual(film.brandLabel, "ILFORD HP5 PLUS")
        XCTAssertEqual(film.aliases, ["HP5+", "HP5 Plus 400"])
        XCTAssertEqual(film.profiles.count, 1)
        XCTAssertEqual(film.profiles[0].rules.count, 2)

        guard case let .threshold(thresholdRule) = try XCTUnwrap(film.profiles.first?.rules.first) else {
            return XCTFail("Expected a threshold rule.")
        }

        XCTAssertEqual(
            thresholdRule.noCorrectionRange,
            ReciprocityTimeRange(minimumSeconds: 0, maximumSeconds: 1)
        )

        guard case let .formula(rule) = try XCTUnwrap(film.profiles.first?.rules.last) else {
            return XCTFail("Expected a formula rule.")
        }

        XCTAssertEqual(rule.formula.kind, .exponentPower)
        XCTAssertNil(rule.formula.coefficient)
        XCTAssertEqual(rule.formula.exponent, 1.31, accuracy: 0.0001)
        XCTAssertEqual(rule.formula.equation, "Tc = Tm^P")
        XCTAssertEqual(film.profiles[0].source.kind, .manufacturerPublished)
        XCTAssertEqual(film.profiles[0].source.authority, .official)
    }

    func testTableBasedOfficialFilmCanExpressDevelopmentAdjustment() throws {
        let film = makeTriXFilm()

        XCTAssertEqual(film.profiles.count, 1)

        guard case let .table(rule) = try XCTUnwrap(film.profiles.first?.rules.first) else {
            return XCTFail("Expected a table rule.")
        }

        XCTAssertEqual(rule.entries.count, 3)

        guard case let .exposure(firstStopAdjustment) = rule.entries[0].adjustments[0] else {
            return XCTFail("Expected exposure stop adjustment for first table entry.")
        }

        guard case let .stopDelta(firstStopDelta) = firstStopAdjustment else {
            return XCTFail("Expected first stop delta adjustment.")
        }

        XCTAssertEqual(firstStopDelta.stopDelta, 1, accuracy: 0.0001)

        guard case let .exposure(firstCorrectedTimeAdjustment) = rule.entries[0].adjustments[1] else {
            return XCTFail("Expected corrected time adjustment for first table entry.")
        }

        guard case let .correctedTime(firstMapping) = firstCorrectedTimeAdjustment else {
            return XCTFail("Expected first corrected time mapping.")
        }

        XCTAssertEqual(firstMapping.meteredSeconds, 1)
        XCTAssertEqual(firstMapping.correctedSeconds, 2, accuracy: 0.0001)

        guard case let .development(firstDevelopment) = rule.entries[0].adjustments[2] else {
            return XCTFail("Expected first development adjustment.")
        }

        XCTAssertEqual(firstDevelopment.instruction, "-10% development")

        guard case let .exposure(exposureAdjustment) = rule.entries[1].adjustments[1] else {
            return XCTFail("Expected corrected time adjustment for second table entry.")
        }

        guard case let .correctedTime(mapping) = exposureAdjustment else {
            return XCTFail("Expected corrected time mapping.")
        }

        XCTAssertEqual(mapping.meteredSeconds, 10)
        XCTAssertEqual(mapping.correctedSeconds, 50, accuracy: 0.0001)

        guard case let .exposure(secondStopAdjustment) = rule.entries[1].adjustments[0] else {
            return XCTFail("Expected second exposure stop adjustment.")
        }

        guard case let .stopDelta(secondStopDelta) = secondStopAdjustment else {
            return XCTFail("Expected second stop delta adjustment.")
        }

        XCTAssertEqual(secondStopDelta.stopDelta, 2, accuracy: 0.0001)

        guard case let .development(secondDevelopment) = rule.entries[1].adjustments[2] else {
            return XCTFail("Expected second development adjustment.")
        }

        XCTAssertEqual(secondDevelopment.instruction, "-20% development")

        guard case let .exposure(stopAdjustment) = rule.entries[2].adjustments[0] else {
            return XCTFail("Expected third exposure stop adjustment.")
        }

        guard case let .stopDelta(stopDelta) = stopAdjustment else {
            return XCTFail("Expected third stop delta adjustment.")
        }

        XCTAssertEqual(stopDelta.stopDelta, 3, accuracy: 0.0001)

        guard case let .exposure(thirdCorrectedTimeAdjustment) = rule.entries[2].adjustments[1] else {
            return XCTFail("Expected corrected time adjustment for third table entry.")
        }

        guard case let .correctedTime(thirdMapping) = thirdCorrectedTimeAdjustment else {
            return XCTFail("Expected third corrected time mapping.")
        }

        XCTAssertEqual(thirdMapping.meteredSeconds, 100)
        XCTAssertEqual(thirdMapping.correctedSeconds, 1200, accuracy: 0.0001)

        guard case let .development(development) = rule.entries[2].adjustments[2] else {
            return XCTFail("Expected third development adjustment.")
        }

        XCTAssertEqual(development.instruction, "-30% development")
    }

    func testTableBasedOfficialFilmCanExpressColorFilterGuidanceAndNotRecommendedRange() throws {
        let film = makeVelviaFilm()

        XCTAssertEqual(film.profiles.count, 1)
        XCTAssertEqual(film.profiles[0].rules.count, 2)

        guard case let .threshold(thresholdRule) = film.profiles[0].rules[0] else {
            return XCTFail("Expected first rule to be threshold-based.")
        }

        XCTAssertEqual(
            thresholdRule.noCorrectionRange,
            ReciprocityTimeRange(minimumSeconds: 1.0 / 4000.0, maximumSeconds: 1)
        )

        guard case let .table(tableRule) = film.profiles[0].rules[1] else {
            return XCTFail("Expected second rule to be table-based.")
        }

        XCTAssertEqual(tableRule.entries.count, 5)

        try assertVelviaEntry(
            tableRule.entries[0],
            meteredSeconds: 4,
            stopDelta: 1.0 / 3.0,
            filterName: "5M"
        )
        try assertVelviaEntry(
            tableRule.entries[1],
            meteredSeconds: 8,
            stopDelta: 0.5,
            filterName: "7.5M"
        )
        try assertVelviaEntry(
            tableRule.entries[2],
            meteredSeconds: 16,
            stopDelta: 2.0 / 3.0,
            filterName: "10M"
        )
        try assertVelviaEntry(
            tableRule.entries[3],
            meteredSeconds: 32,
            stopDelta: 1,
            filterName: "12.5M"
        )

        guard case let .warning(warning) = tableRule.entries[4].adjustments[0] else {
            return XCTFail("Expected warning payload for 64 second entry.")
        }

        guard case let .exactSeconds(notRecommendedSeconds) = tableRule.entries[4].meteredExposure else {
            return XCTFail("Expected explicit 64 second entry.")
        }

        XCTAssertEqual(notRecommendedSeconds, 64, accuracy: 0.0001)
        XCTAssertEqual(warning.severity, .notRecommended)
        XCTAssertEqual(warning.message, "64 sec is not recommended.")
    }

    func testThresholdOnlyOfficialGuidanceDoesNotCollapseIntoUnknown() throws {
        let film = makePortraFilm()

        XCTAssertEqual(film.kind, .preset)
        XCTAssertEqual(film.productionStatus, .current)
        XCTAssertEqual(film.profiles.count, 2)

        guard case let .threshold(officialRule) = film.profiles[0].rules[0] else {
            return XCTFail("Expected threshold rule.")
        }

        XCTAssertEqual(
            officialRule.noCorrectionRange,
            ReciprocityTimeRange(minimumSeconds: 1.0 / 10_000.0, maximumSeconds: 1)
        )
        XCTAssertTrue(officialRule.adjustments.isEmpty)
        XCTAssertEqual(film.profiles[0].source.authority, .official)

        guard case let .advisory(advisoryRule) = film.profiles[0].rules[1] else {
            return XCTFail("Expected advisory rule.")
        }

        XCTAssertEqual(advisoryRule.appliesWhenMetered, ReciprocityTimeRange(minimumSeconds: 1))
        XCTAssertEqual(film.profiles[0].source.kind, .manufacturerPublished)

        guard case let .note(note) = advisoryRule.adjustments[0] else {
            return XCTFail("Expected advisory note payload.")
        }

        XCTAssertEqual(note.text, "Longer exposures: test under your conditions.")
    }

    func testCustomUserDefinedUnknownFilmProfileIsSupported() throws {
        let film = makeCustomUnknownFilm()

        XCTAssertEqual(film.kind, .custom)
        XCTAssertNil(film.manufacturer)
        XCTAssertEqual(film.productionStatus, .unknown)
        XCTAssertEqual(film.userMetadata?.displayNameOverride, "Mystery ISO 100")
        XCTAssertEqual(film.profiles[0].source.kind, .userDefined)
        XCTAssertEqual(film.profiles[0].source.authority, .userDefined)

        guard case let .table(rule) = film.profiles[0].rules[0] else {
            return XCTFail("Expected table rule for custom film.")
        }

        XCTAssertEqual(rule.entries.count, 2)
    }

    func testDiscontinuedFilmCanCarryArchivalOfficialProfile() throws {
        let film = makeAgfaArchivalFilm()

        XCTAssertEqual(film.productionStatus, .discontinued)
        XCTAssertEqual(film.profiles[0].source.kind, .manufacturerArchive)
        XCTAssertEqual(film.profiles[0].source.authority, .official)
        XCTAssertEqual(film.profiles[0].source.confidence, .medium)
        XCTAssertEqual(film.manufacturer, "Agfa")
        XCTAssertEqual(film.canonicalStockName, "Agfapan APX 100")

        guard case let .table(rule) = film.profiles[0].rules[0] else {
            return XCTFail("Expected archival table rule.")
        }

        XCTAssertEqual(rule.entries.count, 3)
    }

    func testOneFilmIdentityCanCarryMultipleProfilesFromDifferentSources() throws {
        let film = makePortraFilm()

        XCTAssertEqual(film.profiles.count, 2)
        XCTAssertEqual(film.profiles[0].source.kind, .manufacturerPublished)
        XCTAssertEqual(film.profiles[0].source.authority, .official)
        XCTAssertEqual(film.profiles[1].source.kind, .thirdPartyPublication)
        XCTAssertEqual(film.profiles[1].source.authority, .unofficial)

        guard case let .table(unofficialRule) = film.profiles[1].rules[0] else {
            return XCTFail("Expected unofficial secondary profile to remain table-based.")
        }

        XCTAssertEqual(unofficialRule.entries.count, 2)
    }

    func testRoundTripEncodingPreservesRuleKindsAndProvenance() throws {
        let films = [
            makeHP5PlusFilm(),
            makeTriXFilm(),
            makeVelviaFilm(),
            makePortraFilm(),
            makeCustomUnknownFilm(),
            makeAgfaArchivalFilm()
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(films)
        let decoded = try JSONDecoder().decode([FilmIdentity].self, from: data)

        XCTAssertEqual(decoded, films)
        XCTAssertEqual(decoded[0].profiles[0].rules[0].kind, .threshold)
        XCTAssertEqual(decoded[0].profiles[0].rules[1].kind, .formula)
        XCTAssertEqual(decoded[1].profiles[0].rules[0].kind, .table)
        XCTAssertEqual(decoded[3].profiles[0].rules[0].kind, .threshold)
        XCTAssertEqual(decoded[3].profiles[0].source.authority, .official)
        XCTAssertEqual(decoded[3].profiles[1].source.authority, .unofficial)
        XCTAssertEqual(decoded[5].productionStatus, .discontinued)
    }

    func testTableBasedRepresentativeDataDocumentsExplicitBoundaryOnly() throws {
        let film = makeTriXFilm()

        guard case let .table(rule) = try XCTUnwrap(film.profiles.first?.rules.first) else {
            return XCTFail("Expected TRI-X representative data to remain table-based.")
        }

        let explicitMeteredSeconds = try rule.entries.map { entry in
            guard case let .exactSeconds(seconds) = entry.meteredExposure else {
                throw NSError(domain: "ReciprocityDomainTests", code: 1)
            }

            return seconds
        }

        XCTAssertEqual(explicitMeteredSeconds, [1, 10, 100])
        XCTAssertEqual(explicitMeteredSeconds.max(), 100)
        XCTAssertFalse(explicitMeteredSeconds.contains(500))
        XCTAssertFalse(explicitMeteredSeconds.contains(999))
    }

    private func assertVelviaEntry(
        _ entry: ReciprocityTableEntry,
        meteredSeconds: Double,
        stopDelta: Double,
        filterName: String
    ) throws {
        guard case let .exactSeconds(actualMeteredSeconds) = entry.meteredExposure else {
            return XCTFail("Expected explicit metered exposure.")
        }

        XCTAssertEqual(actualMeteredSeconds, meteredSeconds, accuracy: 0.0001)

        guard case let .exposure(exposureAdjustment) = entry.adjustments[0] else {
            return XCTFail("Expected exposure adjustment.")
        }

        guard case let .stopDelta(actualStopDelta) = exposureAdjustment else {
            return XCTFail("Expected stop delta adjustment.")
        }

        XCTAssertEqual(actualStopDelta.stopDelta, stopDelta, accuracy: 0.0001)

        guard case let .colorFilter(actualFilter) = entry.adjustments[1] else {
            return XCTFail("Expected color filter adjustment.")
        }

        XCTAssertEqual(actualFilter.filterName, filterName)
    }

    private func makeHP5PlusFilm() -> FilmIdentity {
        FilmIdentity(
            id: "ilford-hp5-plus-400",
            kind: .preset,
            canonicalStockName: "HP5 Plus",
            manufacturer: "ILFORD / HARMAN",
            brandLabel: "ILFORD HP5 PLUS",
            aliases: ["HP5+", "HP5 Plus 400"],
            iso: 400,
            productionStatus: .current,
            profiles: [
                ReciprocityProfile(
                    id: "ilford-hp5-plus-official-formula",
                    name: "Official formula",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerPublished,
                        authority: .official,
                        confidence: .high,
                        publisher: "Ilford Photo",
                        title: "Reciprocity characteristics",
                        citation: "Technical information sheet",
                        sourceVersion: "2026"
                    ),
                    rules: [
                        .threshold(
                            ThresholdReciprocityRule(
                                noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 0, maximumSeconds: 1),
                                notes: ["No compensation required at 1 second or less."]
                            )
                        ),
                        .formula(
                            FormulaReciprocityRule(
                                meteredRange: ReciprocityTimeRange(minimumSeconds: 1.000_001),
                                formula: ReciprocityFormula(
                                    exponent: 1.31,
                                    equation: "Tc = Tm^P"
                                ),
                                notes: ["Exponent P = 1.31."]
                            )
                        )
                    ]
                )
            ],
            userMetadata: nil
        )
    }

    private func makeTriXFilm() -> FilmIdentity {
        FilmIdentity(
            id: "kodak-tri-x-400",
            kind: .preset,
            canonicalStockName: "Tri-X 400",
            manufacturer: "Kodak",
            brandLabel: "KODAK PROFESSIONAL TRI-X 400",
            aliases: ["TRI-X", "TX 400"],
            iso: 400,
            productionStatus: .current,
            profiles: [
                ReciprocityProfile(
                    id: "kodak-tri-x-official-table",
                    name: "Official table",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerPublished,
                        authority: .official,
                        confidence: .high,
                        publisher: "Kodak",
                        title: "Reciprocity data",
                        citation: "Data sheet"
                    ),
                    rules: [
                        .table(
                            TableReciprocityRule(
                                entries: [
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(1),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1))),
                                            .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 1, correctedSeconds: 2))),
                                            .development(DevelopmentAdjustment(
                                                instruction: "-10% development",
                                                note: nil
                                            ))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(10),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 2))),
                                            .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 10, correctedSeconds: 50))),
                                            .development(DevelopmentAdjustment(
                                                instruction: "-20% development",
                                                note: nil
                                            ))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(100),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 3))),
                                            .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 100, correctedSeconds: 1200))),
                                            .development(DevelopmentAdjustment(
                                                instruction: "-30% development",
                                                note: nil
                                            ))
                                        ]
                                    )
                                ],
                                notes: ["Table data stays table-shaped rather than converted to a formula."]
                            )
                        )
                    ]
                )
            ],
            userMetadata: nil
        )
    }

    private func makeVelviaFilm() -> FilmIdentity {
        FilmIdentity(
            id: "fujifilm-velvia-50",
            kind: .preset,
            canonicalStockName: "Velvia 50",
            manufacturer: "Fujifilm",
            brandLabel: "FUJICHROME Velvia 50",
            aliases: ["RVP 50", "Velvia"],
            iso: 50,
            productionStatus: .current,
            profiles: [
                ReciprocityProfile(
                    id: "fujifilm-velvia-official-table",
                    name: "Official table and color guidance",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerPublished,
                        authority: .official,
                        confidence: .high,
                        publisher: "Fujifilm",
                        title: "Long exposure guide"
                    ),
                    rules: [
                        .threshold(
                            ThresholdReciprocityRule(
                                noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 1.0 / 4000.0, maximumSeconds: 1)
                            )
                        ),
                        .table(
                            TableReciprocityRule(
                                entries: [
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(4),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1.0 / 3.0))),
                                            .colorFilter(ColorFilterRecommendation(filterName: "5M", note: nil))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(8),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 0.5))),
                                            .colorFilter(ColorFilterRecommendation(filterName: "7.5M", note: nil))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(16),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 2.0 / 3.0))),
                                            .colorFilter(ColorFilterRecommendation(filterName: "10M", note: nil))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(32),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1))),
                                            .colorFilter(ColorFilterRecommendation(filterName: "12.5M", note: nil))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(64),
                                        adjustments: [
                                            .warning(ReciprocityWarning(
                                                severity: .notRecommended,
                                                message: "64 sec is not recommended."
                                            ))
                                        ]
                                    )
                                ]
                            )
                        )
                    ]
                )
            ],
            userMetadata: nil
        )
    }

    private func makePortraFilm() -> FilmIdentity {
        FilmIdentity(
            id: "kodak-portra-400",
            kind: .preset,
            canonicalStockName: "Portra 400",
            manufacturer: "Kodak",
            brandLabel: "KODAK PROFESSIONAL PORTRA 400",
            aliases: ["PORTRA 400"],
            iso: 400,
            productionStatus: .current,
            profiles: [
                ReciprocityProfile(
                    id: "kodak-portra-official-threshold",
                    name: "Official threshold guidance",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerPublished,
                        authority: .official,
                        confidence: .high,
                        publisher: "Kodak",
                        title: "Reciprocity statement"
                    ),
                    rules: [
                        .threshold(
                            ThresholdReciprocityRule(
                                noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 1.0 / 10_000.0, maximumSeconds: 1),
                                notes: ["No correction required in the official range."]
                            )
                        ),
                        .advisory(
                            AdvisoryReciprocityRule(
                                appliesWhenMetered: ReciprocityTimeRange(minimumSeconds: 1),
                                adjustments: [
                                    .note(ReciprocityNote(
                                        text: "Longer exposures: test under your conditions."
                                    ))
                                ]
                            )
                        )
                    ]
                ),
                ReciprocityProfile(
                    id: "kodak-portra-secondary-table",
                    name: "Secondary reference table",
                    source: ReciprocitySourceProvenance(
                        kind: .thirdPartyPublication,
                        authority: .unofficial,
                        confidence: .medium,
                        publisher: "Independent reciprocity notes",
                        title: "Field-tested secondary profile"
                    ),
                    rules: [
                        .table(
                            TableReciprocityRule(
                                entries: [
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(2),
                                        adjustments: [
                                            .exposure(.multiplier(MultiplierAdjustment(factor: 1.5)))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(8),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 0.5)))
                                        ]
                                    )
                                ]
                            )
                        )
                    ]
                )
            ],
            userMetadata: nil
        )
    }

    private func makeCustomUnknownFilm() -> FilmIdentity {
        FilmIdentity(
            id: "custom-mystery-iso-100",
            kind: .custom,
            canonicalStockName: "Unknown ISO 100 Film",
            manufacturer: nil,
            brandLabel: nil,
            aliases: ["Mystery Roll"],
            iso: 100,
            productionStatus: .unknown,
            profiles: [
                ReciprocityProfile(
                    id: "custom-user-profile",
                    name: "User-defined table",
                    source: ReciprocitySourceProvenance(
                        kind: .userDefined,
                        authority: .userDefined,
                        confidence: .unknown,
                        publisher: "Local User"
                    ),
                    rules: [
                        .table(
                            TableReciprocityRule(
                                entries: [
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(1),
                                        adjustments: [
                                            .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 1, correctedSeconds: 1.5)))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .range(ReciprocityTimeRange(minimumSeconds: 5, maximumSeconds: 10)),
                                        adjustments: [
                                            .exposure(.multiplier(MultiplierAdjustment(factor: 1.8))),
                                            .note(ReciprocityNote(text: "User-entered estimate."))
                                        ]
                                    )
                                ]
                            )
                        )
                    ],
                    userMetadata: UserEditableMetadata(
                        displayNameOverride: "Mystery ISO 100",
                        tags: ["custom", "estimate"],
                        notes: ["Created during film testing."]
                    )
                )
            ],
            userMetadata: UserEditableMetadata(
                displayNameOverride: "Mystery ISO 100",
                tags: ["user-film"],
                notes: []
            )
        )
    }

    private func makeAgfaArchivalFilm() -> FilmIdentity {
        FilmIdentity(
            id: "agfa-agfapan-apx-100",
            kind: .preset,
            canonicalStockName: "Agfapan APX 100",
            manufacturer: "Agfa",
            brandLabel: "AGFAPAN APX 100",
            aliases: ["APX 100"],
            iso: 100,
            productionStatus: .discontinued,
            profiles: [
                ReciprocityProfile(
                    id: "agfa-archival-official",
                    name: "Archival official profile",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerArchive,
                        authority: .official,
                        confidence: .medium,
                        publisher: "Agfa archive",
                        title: "Archived reciprocity data",
                        sourceVersion: "legacy"
                    ),
                    rules: [
                        .table(
                            TableReciprocityRule(
                                entries: [
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(1),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 1))),
                                            .development(DevelopmentAdjustment(instruction: "-10% development", note: nil))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(10),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 2))),
                                            .development(DevelopmentAdjustment(instruction: "-25% development", note: nil))
                                        ]
                                    ),
                                    ReciprocityTableEntry(
                                        meteredExposure: .exactSeconds(100),
                                        adjustments: [
                                            .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 3))),
                                            .development(DevelopmentAdjustment(instruction: "-35% development", note: nil))
                                        ]
                                    )
                                ],
                                notes: ["Archival official reciprocity table."]
                            )
                        )
                    ]
                )
            ],
            userMetadata: nil
        )
    }
}

// Tests for the unofficial practical secondary profile for Portra 400.
final class Portra400SecondaryProfileTests: XCTestCase {
    private let evaluator = ReciprocityCalculationPolicyEvaluator()
    private let filmID = "kodak-portra-400"
    private let officialProfileID = "kodak-portra-400-official-threshold"
    private let unofficialProfileID = "kodak-portra-400-unofficial-practical"

    func testPortra400LaunchCatalogHasExactlyOneOfficialPrimaryProfile() {
        let portra = LaunchPresetFilmCatalog.films.first(where: { $0.id == filmID })

        XCTAssertNotNil(portra, "Portra 400 must exist in the launch catalog.")
        XCTAssertEqual(portra?.profiles.count, 1, "Launch catalog must have exactly one profile per film.")
        XCTAssertEqual(portra?.profiles.first?.id, officialProfileID)
        XCTAssertEqual(portra?.profiles.first?.source.authority, .official)
        XCTAssertEqual(portra?.profiles.first?.source.kind, .manufacturerPublished)
    }

    func testPortra400UnofficialPracticalProfileHasUnofficialProvenance() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical

        XCTAssertEqual(profile.source.authority, .unofficial)
        XCTAssertEqual(profile.source.kind, .thirdPartyPublication)
        XCTAssertEqual(profile.source.confidence, .low)
    }

    func testPortra400UnofficialProfileIsNotLabeledOfficial() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical

        XCTAssertNotEqual(profile.source.authority, .official)
        XCTAssertNotEqual(profile.source.confidence, .high)
        XCTAssertNotEqual(profile.source.kind, .manufacturerPublished)
    }

    func testPortra400OfficialAndUnofficialProfilesHaveDistinctIdentifiers() {
        let officialProfile = LaunchPresetFilmCatalog.films
            .first(where: { $0.id == filmID })?
            .profiles.first
        let unofficialProfile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical

        XCTAssertNotNil(officialProfile)
        XCTAssertNotEqual(officialProfile?.id, unofficialProfile.id)
        XCTAssertEqual(officialProfile?.id, officialProfileID)
        XCTAssertEqual(unofficialProfile.id, unofficialProfileID)
    }

    func testPortra400OfficialBehaviorUnchanged_ThresholdNoCorrectionBelowOneSecond() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.portraOfficialProfile(),
            meteredExposureSeconds: 0.5
        )

        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertTrue(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
    }

    func testPortra400OfficialBehaviorUnchanged_AdvisoryOnlyBeyondOfficialRange() {
        let result = evaluator.evaluate(
            profile: ReciprocityPolicyScenarioFactory.portraOfficialProfile(),
            meteredExposureSeconds: 4
        )

        XCTAssertNil(result.correctedExposureSeconds)
        XCTAssertFalse(result.hasCalculatedExposureTime)
        XCTAssertEqual(result.metadata.basis, .advisoryOnlyBeyondOfficialRange)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondLastRepresentativePoint)
    }

    func testPortra400FilmIdentityCanRepresentBothProfilesAtDomainLevel() throws {
        let officialProfile = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first(where: { $0.id == filmID })?.profiles.first,
            "Official Portra 400 profile must exist in the launch catalog."
        )

        let withBothProfiles = FilmIdentity(
            id: filmID,
            kind: .preset,
            canonicalStockName: "Portra 400",
            manufacturer: "Kodak",
            brandLabel: "KODAK PROFESSIONAL PORTRA 400",
            aliases: ["PORTRA 400"],
            iso: 400,
            productionStatus: .current,
            profiles: [officialProfile, UnofficialPracticalProfiles.kodakPortra400UnofficialPractical],
            userMetadata: nil
        )

        XCTAssertEqual(withBothProfiles.profiles.count, 2)
        XCTAssertEqual(withBothProfiles.profiles[0].id, officialProfileID)
        XCTAssertEqual(withBothProfiles.profiles[0].source.authority, .official)
        XCTAssertEqual(withBothProfiles.profiles[1].id, unofficialProfileID)
        XCTAssertEqual(withBothProfiles.profiles[1].source.authority, .unofficial)
    }

    func testPortra400UnofficialProfileHasFormulaRuleWithExponent1_34() {
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical

        let formulaRule = profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(r) = rule else { return nil }
            return r
        }.first

        XCTAssertNotNil(formulaRule, "Unofficial profile must contain a formula rule.")
        XCTAssertEqual(formulaRule?.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule?.formula.exponent ?? 0, 1.34, accuracy: 0.0001)
    }

    func testPortra400UnofficialProfileEvaluatesQuantifiedResultBeyondOfficialRange() {
        let result = evaluator.evaluate(
            profile: UnofficialPracticalProfiles.kodakPortra400UnofficialPractical,
            meteredExposureSeconds: 10
        )

        XCTAssertTrue(result.hasCalculatedExposureTime, "Unofficial formula profile must produce a quantified result.")
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, pow(10, 1.34), accuracy: 0.001)
        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        XCTAssertNotEqual(result.metadata.sourceAuthorityImpact, .currentOfficial)
    }
}

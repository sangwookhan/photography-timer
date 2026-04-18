import Foundation

enum LaunchPresetFilmCatalog {
    static let films: [FilmIdentity] = [
        triX400,
        portra400,
        velvia50,
        hp5Plus
    ]

    private static let triX400 = FilmIdentity(
        id: "kodak-tri-x-400",
        kind: .preset,
        canonicalStockName: "Tri-X 400",
        manufacturer: "Kodak",
        brandLabel: "KODAK PROFESSIONAL TRI-X 400",
        aliases: ["TRI-X", "TX 400"],
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
                                        .development(DevelopmentAdjustment(instruction: "-10% development", note: nil))
                                    ]
                                ),
                                ReciprocityTableEntry(
                                    meteredExposure: .exactSeconds(10),
                                    adjustments: [
                                        .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 2))),
                                        .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 10, correctedSeconds: 50))),
                                        .development(DevelopmentAdjustment(instruction: "-20% development", note: nil))
                                    ]
                                ),
                                ReciprocityTableEntry(
                                    meteredExposure: .exactSeconds(100),
                                    adjustments: [
                                        .exposure(.stopDelta(StopDeltaAdjustment(stopDelta: 3))),
                                        .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: 100, correctedSeconds: 1_200))),
                                        .development(DevelopmentAdjustment(instruction: "-30% development", note: nil))
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

    private static let portra400 = FilmIdentity(
        id: "kodak-portra-400",
        kind: .preset,
        canonicalStockName: "Portra 400",
        manufacturer: "Kodak",
        brandLabel: "KODAK PROFESSIONAL PORTRA 400",
        aliases: ["PORTRA 400"],
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
                                .note(ReciprocityNote(text: "Longer exposures: test under your conditions."))
                            ]
                        )
                    )
                ]
            )
        ],
        userMetadata: nil
    )

    private static let velvia50 = FilmIdentity(
        id: "fujifilm-velvia-50",
        kind: .preset,
        canonicalStockName: "Velvia 50",
        manufacturer: "Fujifilm",
        brandLabel: "FUJICHROME Velvia 50",
        aliases: ["RVP 50", "Velvia"],
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
                                        .warning(
                                            ReciprocityWarning(
                                                severity: .notRecommended,
                                                message: "64 sec is not recommended."
                                            )
                                        )
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

    private static let hp5Plus = FilmIdentity(
        id: "ilford-hp5-plus-400",
        kind: .preset,
        canonicalStockName: "HP5 Plus",
        manufacturer: "ILFORD / HARMAN",
        brandLabel: "ILFORD HP5 PLUS",
        aliases: ["HP5+", "HP5 Plus 400"],
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

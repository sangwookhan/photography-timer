// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

// Faithful port of iOS PTimerCore AlternateReciprocityModels + the
// UnofficialPracticalProfiles registry. Data transcription of the alternate
// models that live OUTSIDE the launch catalog, selectable via the model
// selector. Small builder helpers keep the domain constructors readable.

private fun exact(seconds: Double) =
    MeteredExposureSelector(kind = MeteredExposureSelectorKind.exactSeconds, exactSeconds = seconds)

private fun correctedTimeAdj(metered: Double?, corrected: Double, approximate: Boolean = false) =
    ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.exposure,
        exposure = ExposureAdjustment(
            kind = ExposureAdjustmentKind.correctedTime,
            correctedTime = CorrectedTimeMapping(metered, corrected, approximate),
        ),
    )

private fun multiplierAdj(factor: Double) =
    ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.exposure,
        exposure = ExposureAdjustment(
            kind = ExposureAdjustmentKind.multiplier,
            multiplier = MultiplierAdjustment(factor),
        ),
    )

private fun stopDeltaAdj(stopDelta: Double) =
    ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.exposure,
        exposure = ExposureAdjustment(
            kind = ExposureAdjustmentKind.stopDelta,
            stopDelta = StopDeltaAdjustment(stopDelta),
        ),
    )

private fun developmentAdj(instruction: String) =
    ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.development,
        development = DevelopmentAdjustment(instruction = instruction),
    )

private fun tableRule(
    anchors: List<TableAnchor>,
    notes: List<String>,
    noCorrectionThroughSeconds: Double,
    sourceRangeThroughSeconds: Double,
) = ReciprocityRule(
    kind = ReciprocityRuleKind.tableInterpolation,
    tableInterpolation = TableInterpolationReciprocityRule(
        anchors = anchors,
        notes = notes,
        noCorrectionThroughSeconds = noCorrectionThroughSeconds,
        sourceRangeThroughSeconds = sourceRangeThroughSeconds,
    ),
)

private fun formulaRule(formula: ReciprocityFormula, notes: List<String>) = ReciprocityRule(
    kind = ReciprocityRuleKind.formula,
    formula = FormulaReciprocityRule(formula = formula, notes = notes),
)

/**
 * Unofficial practical profiles defined separately from the launch preset
 * catalog (which enforces exactly one official profile per film).
 */
object UnofficialPracticalProfiles {

    fun profile(forFilmID: String): ReciprocityProfile? = when (forFilmID) {
        "kodak-portra-400" -> kodakPortra400UnofficialPractical
        else -> null
    }

    val kodakPortra400UnofficialPractical = ReciprocityProfile(
        id = "kodak-portra-400-unofficial-practical",
        name = "Unofficial practical approximation",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.thirdPartyPublication,
            authority = ReciprocityAuthority.unofficial,
            confidence = ReciprocityConfidence.low,
            publisher = "",
        ),
        rules = listOf(
            formulaRule(
                ReciprocityFormula(
                    formulaFamily = FormulaFamily.modifiedSchwarzschild,
                    exponent = 1.34,
                    noCorrectionThroughSeconds = 0.999_999,
                ),
                notes = emptyList(),
            ),
        ),
        notes = listOf(
            "Unofficial practical approximation. Not a Kodak-published profile.",
            "Formula: Tc = Tm^1.34. Source pending verification.",
        ),
    )
}

/**
 * Registry of alternate reciprocity profiles/models selectable through the
 * model selector via a profile override, never as duplicate top-level film
 * rows.
 */
object AlternateReciprocityModels {

    /** Alternate models for a film stock, in display order. */
    fun alternates(forFilmID: String): List<ReciprocityProfile> = when (forFilmID) {
        "kodak-portra-400" -> listOf(UnofficialPracticalProfiles.kodakPortra400UnofficialPractical)
        "foma-fomapan-100" -> listOf(fomapan100OhzartCommunityTable, fomapan100AppDerivedFormula)
        "kodak-tri-x-400" -> listOf(triX400OfficialTable, triX400AppDerivedFormula)
        "kodak-tmax-100" -> listOf(tmax100AppDerivedFormula)
        "adox-chs-100-ii" -> listOf(chs100AppDerivedFormula)
        else -> emptyList()
    }

    /** Picker display order: primary then alternates, except Tri-X 400. */
    fun modelPickerOrder(primary: ReciprocityProfile, forFilmID: String): List<ReciprocityProfile> {
        val alternates = alternates(forFilmID)
        val officialTable = alternates.firstOrNull { it.id == triX400OfficialTable.id }
        if (forFilmID != "kodak-tri-x-400" || officialTable == null) {
            return listOf(primary) + alternates
        }
        return listOf(officialTable, primary) + alternates.filter { it.id != officialTable.id }
    }

    /** True for explicitly app-derived alternate models. */
    fun isAppDerivedModel(id: String): Boolean =
        id == fomapan100AppDerivedFormula.id ||
            id == triX400AppDerivedFormula.id ||
            id == tmax100AppDerivedFormula.id ||
            id == chs100AppDerivedFormula.id

    /** Resolves an alternate profile by id (used by session restore). */
    fun profile(withID: String): ReciprocityProfile? {
        val all = listOf(
            UnofficialPracticalProfiles.kodakPortra400UnofficialPractical,
            fomapan100OhzartCommunityTable,
            fomapan100AppDerivedFormula,
            triX400OfficialTable,
            triX400AppDerivedFormula,
            tmax100AppDerivedFormula,
            chs100AppDerivedFormula,
        )
        return all.firstOrNull { it.id == withID }
    }

    // MARK: - Fomapan 100 (Ohzart community table + app-derived formula)

    private fun ohzartAnchorEvidence(metered: Double, corrected: Double) = ReciprocitySourceEvidenceRow(
        meteredExposure = exact(metered),
        adjustments = listOf(correctedTimeAdj(metered, corrected)),
    )

    private val ohzartCommunityAnchorEvidence = listOf(
        ohzartAnchorEvidence(1.0, 1.9),
        ohzartAnchorEvidence(2.0, 5.0),
        ohzartAnchorEvidence(4.0, 13.0),
        ohzartAnchorEvidence(8.0, 35.0),
        ohzartAnchorEvidence(15.0, 90.0),
        ohzartAnchorEvidence(30.0, 265.0),
        ohzartAnchorEvidence(60.0, 795.0),
    )

    val fomapan100OhzartCommunityTable = ReciprocityProfile(
        id = "foma-fomapan-100-ohzart-community-table",
        name = "Ohzart community table",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.thirdPartyPublication,
            authority = ReciprocityAuthority.unofficial,
            confidence = ReciprocityConfidence.medium,
            publisher = "Ohzart",
            title = "Reciprocity practical table",
            citation = "https://ohzart1.tistory.com/78",
        ),
        rules = listOf(
            tableRule(
                anchors = listOf(
                    TableAnchor(1.0, 1.9),
                    TableAnchor(2.0, 5.0),
                    TableAnchor(4.0, 13.0),
                    TableAnchor(8.0, 35.0),
                    TableAnchor(15.0, 90.0),
                    TableAnchor(30.0, 265.0),
                    TableAnchor(60.0, 795.0),
                ),
                notes = listOf(
                    "Ohzart community practical table for Fomapan 100, reproduced by log-log interpolation between the published anchors. Practical / community guidance, not FOMA-published data.",
                ),
                noCorrectionThroughSeconds = 0.5,
                sourceRangeThroughSeconds = 60.0,
            ),
        ),
        notes = listOf("Unofficial practical community table (Ohzart). Not FOMA-published data."),
        sourceEvidence = ohzartCommunityAnchorEvidence,
        modelBasis = ReciprocityProfileModelBasis(
            sourceModel = ReciprocitySourceModel.practicalCommunityGuidance,
            calculationModel = ReciprocityCalculationModel.tableLogLogInterpolation,
        ),
        selectorLabel = "Ohzart",
    )

    private fun fomapanAnchorEvidence(metered: Double, multiplier: Double, corrected: Double, note: String) =
        ReciprocitySourceEvidenceRow(
            meteredExposure = exact(metered),
            adjustments = listOf(multiplierAdj(multiplier), correctedTimeAdj(metered, corrected)),
            notes = listOf(note),
        )

    private val fomapanOfficialAnchorEvidence = listOf(
        fomapanAnchorEvidence(1.0, 2.0, 2.0, "1 sec → ×2 (corrected 2 sec)."),
        fomapanAnchorEvidence(10.0, 8.0, 80.0, "10 sec → ×8 (corrected 80 sec)."),
        fomapanAnchorEvidence(100.0, 16.0, 1600.0, "100 sec → ×16 (corrected 1600 sec)."),
    )

    val fomapan100AppDerivedFormula = ReciprocityProfile(
        id = "foma-fomapan-100-app-formula",
        name = "App-derived formula",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.manufacturerPublished,
            authority = ReciprocityAuthority.official,
            confidence = ReciprocityConfidence.high,
            publisher = "FOMA BOHEMIA",
            title = "FOMAPAN 100 CLASSIC — Technical sheet",
            citation = "Foma technical sheet",
        ),
        rules = listOf(
            formulaRule(
                ReciprocityFormula(
                    formulaFamily = FormulaFamily.modifiedSchwarzschild,
                    coefficientSeconds = 2.2457,
                    exponent = 1.4515,
                    noCorrectionThroughSeconds = 0.5,
                    sourceRangeThroughSeconds = 100.0,
                ),
                notes = listOf(
                    "App-derived: Tc = 2.2457 × Tm^1.4515, a free log-log fit through FOMA's published 1/10/100 sec anchors. Not manufacturer-published guidance; the official table model is the default.",
                ),
            ),
        ),
        sourceEvidence = fomapanOfficialAnchorEvidence,
        modelBasis = ReciprocityProfileModelBasis(
            sourceModel = ReciprocitySourceModel.manufacturerTable,
            calculationModel = ReciprocityCalculationModel.guardedFormula,
        ),
    )

    // MARK: - Kodak Tri-X 400 (official table + app-derived formula)

    private fun triX400AnchorEvidence(
        metered: Double,
        stopDelta: Double,
        corrected: Double,
        development: String,
        note: String,
    ) = ReciprocitySourceEvidenceRow(
        meteredExposure = exact(metered),
        adjustments = listOf(
            stopDeltaAdj(stopDelta),
            correctedTimeAdj(metered, corrected),
            developmentAdj(development),
        ),
        notes = listOf(note),
    )

    private val triX400OfficialAnchorEvidence = listOf(
        triX400AnchorEvidence(1.0, 1.0, 2.0, "-10% development", "1 sec → +1 stop, corrected 2 sec, develop -10%."),
        triX400AnchorEvidence(10.0, 2.0, 50.0, "-20% development", "10 sec → +2 stops, corrected 50 sec, develop -20%."),
        triX400AnchorEvidence(100.0, 3.0, 1200.0, "-30% development", "100 sec → +3 stops, corrected 1200 sec, develop -30%."),
    )

    val triX400OfficialTable = ReciprocityProfile(
        id = "kodak-tri-x-official-table",
        name = "Official Kodak table",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.manufacturerPublished,
            authority = ReciprocityAuthority.official,
            confidence = ReciprocityConfidence.high,
            publisher = "Kodak",
            title = "KODAK PROFESSIONAL TRI-X 400 Film — Technical Data",
            citation = "Publication F-4017",
        ),
        rules = listOf(
            tableRule(
                anchors = listOf(
                    TableAnchor(1.0, 2.0),
                    TableAnchor(10.0, 50.0),
                    TableAnchor(100.0, 1200.0),
                ),
                notes = listOf(
                    "Published Kodak E-31 table rows only (1 sec → 2 sec, 10 sec → 50 sec, 100 sec → 1200 sec). No adjustment through 1/10 sec; log-log interpolation between the published anchors. Inputs above 100 sec are flagged beyond the published source range.",
                ),
                noCorrectionThroughSeconds = 0.1,
                sourceRangeThroughSeconds = 100.0,
            ),
        ),
        sourceEvidence = triX400OfficialAnchorEvidence,
        modelBasis = ReciprocityProfileModelBasis(
            sourceModel = ReciprocitySourceModel.manufacturerTable,
            calculationModel = ReciprocityCalculationModel.tableLogLogInterpolation,
        ),
        selectorLabel = "Official table",
    )

    val triX400AppDerivedFormula = ReciprocityProfile(
        id = "kodak-tri-x-app-formula",
        name = "App formula",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.manufacturerPublished,
            authority = ReciprocityAuthority.official,
            confidence = ReciprocityConfidence.high,
            publisher = "Kodak",
            title = "KODAK PROFESSIONAL TRI-X 400 Film — Technical Data",
            citation = "Publication F-4017",
        ),
        rules = listOf(
            formulaRule(
                ReciprocityFormula(
                    formulaFamily = FormulaFamily.modifiedSchwarzschild,
                    coefficientSeconds = 2.0,
                    exponent = 1.3891,
                    noCorrectionThroughSeconds = 0.1,
                    sourceRangeThroughSeconds = 100.0,
                ),
                notes = listOf(
                    "App-derived: Tc = 2 × Tm^1.3891, fitted to Kodak's published 1/10/100 sec table rows (no correction through 1/10 sec). Not a Kodak-published formula; the official graph/table model is the default.",
                ),
            ),
        ),
        sourceEvidence = triX400OfficialAnchorEvidence,
        modelBasis = ReciprocityProfileModelBasis(
            sourceModel = ReciprocitySourceModel.manufacturerGraphTable,
            calculationModel = ReciprocityCalculationModel.guardedFormula,
        ),
    )

    // MARK: - Kodak T-MAX 100 app-derived formula

    private val tmax100OfficialAnchorEvidence = listOf(
        ReciprocitySourceEvidenceRow(
            meteredExposure = exact(1.0),
            adjustments = listOf(
                stopDeltaAdj(1.0 / 3.0),
                correctedTimeAdj(1.0, 1.2599210498948732, approximate = true),
            ),
            notes = listOf("1 sec → +1/3 stop (≈1.26 sec derived time-equivalent)."),
        ),
        ReciprocitySourceEvidenceRow(
            meteredExposure = exact(10.0),
            adjustments = listOf(stopDeltaAdj(0.5), correctedTimeAdj(10.0, 15.0)),
            notes = listOf("10 sec → +1/2 stop, corrected 15 sec."),
        ),
        ReciprocitySourceEvidenceRow(
            meteredExposure = exact(100.0),
            adjustments = listOf(stopDeltaAdj(1.0), correctedTimeAdj(100.0, 200.0)),
            notes = listOf("100 sec → +1 stop, corrected 200 sec."),
        ),
    )

    val tmax100AppDerivedFormula = ReciprocityProfile(
        id = "kodak-tmax-100-app-formula",
        name = "App formula",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.manufacturerPublished,
            authority = ReciprocityAuthority.official,
            confidence = ReciprocityConfidence.high,
            publisher = "Kodak",
            title = "KODAK PROFESSIONAL T-MAX 100 Film — Technical Data",
            citation = "Publication F-4016",
        ),
        rules = listOf(
            formulaRule(
                ReciprocityFormula(
                    formulaFamily = FormulaFamily.modifiedSchwarzschild,
                    coefficientSeconds = 1.2364,
                    exponent = 1.1003,
                    noCorrectionThroughSeconds = 0.1,
                    sourceRangeThroughSeconds = 100.0,
                ),
                notes = listOf(
                    "App-derived: Tc = 1.2364 × Tm^1.1003, fitted to Kodak's published 1/10/100 sec table rows (no correction through 1/10 sec). Not a Kodak-published formula; the official table model is the default.",
                ),
            ),
        ),
        sourceEvidence = tmax100OfficialAnchorEvidence,
        modelBasis = ReciprocityProfileModelBasis(
            sourceModel = ReciprocitySourceModel.manufacturerTable,
            calculationModel = ReciprocityCalculationModel.guardedFormula,
        ),
    )

    // MARK: - ADOX CHS 100 II app-derived formula

    private fun chs100AnchorEvidence(metered: Double, multiplier: Double, corrected: Double, note: String) =
        ReciprocitySourceEvidenceRow(
            meteredExposure = exact(metered),
            adjustments = listOf(multiplierAdj(multiplier), correctedTimeAdj(metered, corrected)),
            notes = listOf(note),
        )

    private val chs100OfficialAnchorEvidence = listOf(
        chs100AnchorEvidence(2.0, 1.5, 3.0, "2 sec → ×1.5 (corrected 3 sec)."),
        chs100AnchorEvidence(4.0, 2.0, 8.0, "4 sec → ×2 (corrected 8 sec)."),
        chs100AnchorEvidence(8.0, 2.5, 20.0, "8 sec → ×2.5 (corrected 20 sec)."),
        chs100AnchorEvidence(15.0, 3.0, 45.0, "15 sec → ×3 (corrected 45 sec)."),
    )

    val chs100AppDerivedFormula = ReciprocityProfile(
        id = "adox-chs-100-ii-app-formula",
        name = "App formula",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.manufacturerPublished,
            authority = ReciprocityAuthority.official,
            confidence = ReciprocityConfidence.high,
            publisher = "ADOX",
            title = "ADOX CHS 100 II S/W Film — Technische Beschreibung, 11. Juli 2024",
            citation = "ADOX CHS 100 II technical sheet (11 July 2024)",
        ),
        rules = listOf(
            formulaRule(
                ReciprocityFormula(
                    formulaFamily = FormulaFamily.modifiedSchwarzschild,
                    coefficientSeconds = 1.2102,
                    exponent = 1.3423,
                    noCorrectionThroughSeconds = 1.0,
                    sourceRangeThroughSeconds = 15.0,
                ),
                notes = listOf(
                    "App-derived: Tc = 1.2102 × Tm^1.3423, fitted to ADOX's published 2/4/8/15 sec table rows (no correction through 1 sec). Not an ADOX-published formula; the official table model is the default.",
                ),
            ),
        ),
        sourceEvidence = chs100OfficialAnchorEvidence,
        modelBasis = ReciprocityProfileModelBasis(
            sourceModel = ReciprocitySourceModel.manufacturerTable,
            calculationModel = ReciprocityCalculationModel.guardedFormula,
        ),
    )
}

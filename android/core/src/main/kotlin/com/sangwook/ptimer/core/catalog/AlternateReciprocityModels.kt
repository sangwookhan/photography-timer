package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.ReciprocityFormula
import com.sangwook.ptimer.core.reciprocity.TableAnchor

/**
 * Registry of non-default, selectable reciprocity models for the handful of
 * PRESET films that ship with alternates (an app-derived guarded formula
 * and/or a community/official table). Preset-only — custom films never get
 * preset alternates. Mirrors iOS `AlternateReciprocityModels`.
 *
 * The selected model's label is captured into timer identity
 * (`selectedModelLabel`) by the app layer.
 */
object AlternateReciprocityModels {

    fun alternates(forFilmId: String): List<ReciprocityProfile> = when (forFilmId) {
        "kodak-portra-400" -> listOf(portra400UnofficialPractical)
        "foma-fomapan-100" -> listOf(fomapan100AppDerivedFormula, fomapan100OhzartCommunityTable)
        "kodak-tri-x-400" -> listOf(triX400OfficialTable, triX400AppDerivedFormula)
        "kodak-tmax-100" -> listOf(tmax100AppDerivedFormula)
        "adox-chs-100-ii" -> listOf(chs100AppDerivedFormula)
        else -> emptyList()
    }

    fun isAppDerivedModel(id: String): Boolean = id in setOf(
        fomapan100AppDerivedFormula.id, triX400AppDerivedFormula.id,
        tmax100AppDerivedFormula.id, chs100AppDerivedFormula.id,
    )

    fun profile(withId: String): ReciprocityProfile? =
        listOf(
            "kodak-portra-400", "foma-fomapan-100", "kodak-tri-x-400",
            "kodak-tmax-100", "adox-chs-100-ii",
        ).flatMap { alternates(it) }.firstOrNull { it.id == withId }

    // MARK: - alternate profiles

    private fun unofficial(publisher: String) = SourceProvenance(
        kind = "thirdPartyPublication", authority = "unofficial", confidence = "medium", publisher = publisher,
    )

    private fun formulaProfile(
        id: String, name: String, formula: ReciprocityFormula, source: SourceProvenance,
    ) = ReciprocityProfile(
        id = id, name = name, source = source, selectorLabel = name,
        rules = listOf(RawRule(kind = "formula", formula = FormulaRulePayload(formula))),
    )

    private fun tableProfile(
        id: String, name: String, anchors: List<TableAnchor>,
        noCorrectionThroughSeconds: Double, sourceRangeThroughSeconds: Double, source: SourceProvenance,
    ) = ReciprocityProfile(
        id = id, name = name, source = source, selectorLabel = name,
        rules = listOf(
            RawRule(
                kind = "tableInterpolation",
                tableInterpolation = TableRulePayload(anchors, noCorrectionThroughSeconds, sourceRangeThroughSeconds),
            ),
        ),
    )

    private val portra400UnofficialPractical = formulaProfile(
        id = "kodak-portra-400-unofficial-practical", name = "Unofficial practical",
        formula = ReciprocityFormula(coefficientSeconds = 1.0, exponent = 1.34, noCorrectionThroughSeconds = 0.999_999),
        source = unofficial("Community practical guidance"),
    )

    private val fomapan100AppDerivedFormula = formulaProfile(
        id = "foma-fomapan-100-app-formula", name = "App-derived formula",
        formula = ReciprocityFormula(coefficientSeconds = 2.2457, exponent = 1.4515, noCorrectionThroughSeconds = 0.5, sourceRangeThroughSeconds = 100.0),
        source = unofficial("PTimer app-derived fit"),
    )

    private val fomapan100OhzartCommunityTable = tableProfile(
        id = "foma-fomapan-100-ohzart-community-table", name = "Community table",
        anchors = listOf(
            TableAnchor(1.0, 1.9), TableAnchor(2.0, 5.0), TableAnchor(4.0, 13.0),
            TableAnchor(8.0, 35.0), TableAnchor(15.0, 90.0), TableAnchor(30.0, 265.0), TableAnchor(60.0, 795.0),
        ),
        noCorrectionThroughSeconds = 0.5, sourceRangeThroughSeconds = 60.0, source = unofficial("Ohzart community table"),
    )

    private val triX400OfficialTable = tableProfile(
        id = "kodak-tri-x-official-table", name = "Official table",
        anchors = listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 50.0), TableAnchor(100.0, 1200.0)),
        noCorrectionThroughSeconds = 0.1, sourceRangeThroughSeconds = 100.0,
        source = SourceProvenance(kind = "manufacturerPublished", authority = "official", confidence = "high", publisher = "Kodak"),
    )

    private val triX400AppDerivedFormula = formulaProfile(
        id = "kodak-tri-x-app-formula", name = "App-derived formula",
        formula = ReciprocityFormula(coefficientSeconds = 2.0, exponent = 1.3891, noCorrectionThroughSeconds = 0.1, sourceRangeThroughSeconds = 100.0),
        source = unofficial("PTimer app-derived fit"),
    )

    private val tmax100AppDerivedFormula = formulaProfile(
        id = "kodak-tmax-100-app-formula", name = "App-derived formula",
        formula = ReciprocityFormula(coefficientSeconds = 1.2364, exponent = 1.1003, noCorrectionThroughSeconds = 0.1, sourceRangeThroughSeconds = 100.0),
        source = unofficial("PTimer app-derived fit"),
    )

    private val chs100AppDerivedFormula = formulaProfile(
        id = "adox-chs-100-ii-app-formula", name = "App-derived formula",
        formula = ReciprocityFormula(coefficientSeconds = 1.2102, exponent = 1.3423, noCorrectionThroughSeconds = 1.0, sourceRangeThroughSeconds = 15.0),
        source = unofficial("PTimer app-derived fit"),
    )
}

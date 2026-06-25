package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.FilmProductionStatus
import com.sangwook.ptimer.core.reciprocity.FormulaFamily
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationModel
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfileModelBasis
import com.sangwook.ptimer.core.reciprocity.ReciprocityRuleKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceModel
import com.sangwook.ptimer.core.reciprocity.hasValidParameters
import kotlinx.serialization.json.Json
import kotlin.math.abs

// Faithful port of iOS PTimerCore LaunchPresetFilmCatalog + loader. Loads the
// bundled JSON (same file as iOS, copied to :core resources) and enforces the
// post-PTIMER-160 launch allow-list at load time.

/** Error reasons for catalog loading / validation. */
sealed class CatalogLoadError(val description: String) {
    object MissingBundledResource : CatalogLoadError("Bundled launch preset film catalog resource was not found.")
    class MalformedResource(reason: String) : CatalogLoadError("Bundled launch preset film catalog resource is malformed: $reason")
    object EmptyCatalog : CatalogLoadError("Bundled launch preset film catalog is empty.")
    object InvalidFilmIdentifier : CatalogLoadError("A film has an empty identifier.")
    class DuplicateFilmIdentifier(id: String) : CatalogLoadError("Duplicate film identifier '$id'.")
    class InvalidCanonicalStockName(filmID: String) : CatalogLoadError("Empty canonical stock name for film '$filmID'.")
    class DuplicateCanonicalStockName(name: String) : CatalogLoadError("Duplicate canonical stock name '$name'.")
    class InvalidFilmKind(filmID: String) : CatalogLoadError("Film '$filmID' is not a preset film.")
    class InvalidProductionStatus(filmID: String) : CatalogLoadError("Film '$filmID' is not marked current-production.")
    class InvalidPrimaryProfileCount(filmID: String, count: Int) :
        CatalogLoadError("Film '$filmID' has $count profiles; launch scope requires exactly one primary profile.")
    class InvalidPrimaryProfileSource(filmID: String) :
        CatalogLoadError("Film '$filmID' does not use a current official manufacturer primary profile.")
    class InvalidFilmISO(filmID: String, iso: Int) :
        CatalogLoadError("Film '$filmID' has non-positive ISO $iso.")
    class InvalidRuleShape(filmID: String, reason: String) :
        CatalogLoadError("Film '$filmID' has an unsupported reciprocity rule shape: $reason.")
}

class CatalogLoadException(val error: CatalogLoadError) : Exception(error.description)

object LaunchPresetFilmCatalog {
    const val RESOURCE_NAME: String = "LaunchPresetFilmCatalog.json"

    /** The validated bundled catalog. Loads lazily on first access. */
    val films: List<FilmIdentity> by lazy { LaunchPresetFilmCatalogLoader().loadBundledCatalog() }
}

class LaunchPresetFilmCatalogLoader {

    private val json = Json { ignoreUnknownKeys = true }

    fun loadBundledCatalog(resourceName: String = LaunchPresetFilmCatalog.RESOURCE_NAME): List<FilmIdentity> {
        val stream = javaClass.classLoader?.getResourceAsStream(resourceName)
            ?: throw CatalogLoadException(CatalogLoadError.MissingBundledResource)
        val text = stream.bufferedReader().use { it.readText() }
        return loadCatalog(text)
    }

    fun loadCatalog(jsonText: String): List<FilmIdentity> {
        val films: List<FilmIdentity> = try {
            json.decodeFromString(jsonText)
        } catch (e: Exception) {
            throw CatalogLoadException(CatalogLoadError.MalformedResource(e.message ?: "decode failed"))
        }
        validateLaunchCatalog(films)
        return films
    }

    private fun validateLaunchCatalog(films: List<FilmIdentity>) {
        if (films.isEmpty()) throw CatalogLoadException(CatalogLoadError.EmptyCatalog)

        val seenIds = HashSet<String>()
        val seenNames = HashSet<String>()

        for (film in films) {
            val filmID = film.id.trim()
            if (filmID.isEmpty()) throw CatalogLoadException(CatalogLoadError.InvalidFilmIdentifier)
            if (!seenIds.add(filmID)) throw CatalogLoadException(CatalogLoadError.DuplicateFilmIdentifier(filmID))

            val name = film.canonicalStockName.trim()
            if (name.isEmpty()) throw CatalogLoadException(CatalogLoadError.InvalidCanonicalStockName(filmID))
            if (!seenNames.add(name)) throw CatalogLoadException(CatalogLoadError.DuplicateCanonicalStockName(name))

            if (film.kind != FilmIdentityKind.preset) {
                throw CatalogLoadException(CatalogLoadError.InvalidFilmKind(filmID))
            }
            if (film.productionStatus != FilmProductionStatus.current) {
                throw CatalogLoadException(CatalogLoadError.InvalidProductionStatus(filmID))
            }
            if (film.iso <= 0) throw CatalogLoadException(CatalogLoadError.InvalidFilmISO(filmID, film.iso))

            if (film.profiles.size != 1) {
                throw CatalogLoadException(CatalogLoadError.InvalidPrimaryProfileCount(filmID, film.profiles.size))
            }
            val profile = film.profiles.first()

            if (!isOfficialManufacturerPrimary(profile) && !isPromotedUnofficialPracticalPrimary(profile, filmID)) {
                throw CatalogLoadException(CatalogLoadError.InvalidPrimaryProfileSource(filmID))
            }

            validateProfileShape(profile, filmID)
        }
    }

    private fun isOfficialManufacturerPrimary(profile: ReciprocityProfile): Boolean =
        profile.source.kind == ReciprocitySourceKind.manufacturerPublished &&
            profile.source.authority == ReciprocityAuthority.official

    private fun isEffectivelyEqual(lhs: Double, rhs: Double): Boolean = abs(lhs - rhs) < 1e-9

    private fun isPromotedUnofficialPracticalPrimary(profile: ReciprocityProfile, filmID: String): Boolean {
        if (filmID != "rollei-retro-400s") return false
        if (profile.id != "rollei-retro-400s-unofficial-practical") return false
        if (profile.source.kind != ReciprocitySourceKind.thirdPartyPublication) return false
        if (profile.source.authority != ReciprocityAuthority.unofficial) return false
        if (profile.source.confidence != com.sangwook.ptimer.core.reciprocity.ReciprocityConfidence.medium) return false
        if (profile.source.publisher.contains("Lafitte").not()) return false
        if (profile.source.title.isNullOrEmpty()) return false
        if (profile.source.citation.isNullOrEmpty()) return false
        if (profile.modelBasis != ReciprocityProfileModelBasis(
                sourceModel = ReciprocitySourceModel.practicalCommunityGuidance,
                calculationModel = ReciprocityCalculationModel.guardedFormula,
            )
        ) {
            return false
        }
        if (profile.rules.size != 1) return false
        val rule = profile.rules[0]
        val formulaRule = rule.formula ?: return false
        if (formulaRule.additionalAdjustments.isNotEmpty()) return false
        val f = formulaRule.formula
        if (f.formulaFamily != FormulaFamily.modifiedSchwarzschild) return false
        if (!isEffectivelyEqual(f.coefficientSeconds, 1.0)) return false
        if (!isEffectivelyEqual(f.referenceMeteredTimeSeconds, 1.0)) return false
        if (!isEffectivelyEqual(f.exponent, 1.62)) return false
        if (!isEffectivelyEqual(f.offsetSeconds, 0.0)) return false
        if (!isEffectivelyEqual(f.noCorrectionThroughSeconds, 1.0)) return false
        if (!isEffectivelyEqual(f.sourceRangeThroughSeconds ?: Double.NaN, 15.0)) return false

        val evidence = profile.sourceEvidence.mapNotNull { row ->
            val metered = row.meteredExposure.exactSeconds ?: return@mapNotNull null
            val corrected = row.adjustments.firstNotNullOfOrNull { adj ->
                adj.exposure?.correctedTime?.correctedSeconds
            } ?: return@mapNotNull null
            metered to corrected
        }
        val expected = listOf(5.0 to 13.5, 10.0 to 41.0, 15.0 to 80.0)
        if (evidence.size != expected.size) return false
        return evidence.zip(expected).all { (actual, exp) ->
            isEffectivelyEqual(actual.first, exp.first) && isEffectivelyEqual(actual.second, exp.second)
        }
    }

    private fun validateProfileShape(profile: ReciprocityProfile, filmID: String) {
        if (profile.rules.isEmpty()) {
            throw CatalogLoadException(CatalogLoadError.InvalidRuleShape(filmID, "rule list is empty"))
        }

        val hasThreshold = profile.rules.any { it.kind == ReciprocityRuleKind.threshold }
        val hasFormula = profile.rules.any { it.kind == ReciprocityRuleKind.formula }
        val hasLimitedGuidance = profile.rules.any { it.kind == ReciprocityRuleKind.limitedGuidance }
        val hasTableInterpolation = profile.rules.any { it.kind == ReciprocityRuleKind.tableInterpolation }

        if (hasTableInterpolation) {
            if (hasFormula || hasLimitedGuidance || hasThreshold) {
                throw CatalogLoadException(
                    CatalogLoadError.InvalidRuleShape(
                        filmID,
                        "table-interpolation profiles must not carry a companion formula, threshold, or limited-guidance rule",
                    ),
                )
            }
            validateTableInterpolationParameters(profile, filmID)
            validateExplicitModelBasis(profile, filmID, hasFormula, hasLimitedGuidance, hasTableInterpolation)
            return
        }

        if (hasFormula && hasLimitedGuidance) {
            throw CatalogLoadException(
                CatalogLoadError.InvalidRuleShape(filmID, "formula and limited-guidance rules cannot coexist"),
            )
        }

        if (hasFormula) {
            if (hasThreshold) {
                throw CatalogLoadException(
                    CatalogLoadError.InvalidRuleShape(
                        filmID,
                        "formula profiles must not carry a companion threshold rule (the formula owns its no-correction guard)",
                    ),
                )
            }
            validateFormulaParameters(profile, filmID)
            validateExplicitModelBasis(profile, filmID, hasFormula, hasLimitedGuidance)
            return
        }

        if (!hasLimitedGuidance) {
            throw CatalogLoadException(
                CatalogLoadError.InvalidRuleShape(
                    filmID,
                    "profile must declare either a formula rule or a threshold + limited-guidance pair",
                ),
            )
        }
        if (!hasThreshold) {
            throw CatalogLoadException(
                CatalogLoadError.InvalidRuleShape(filmID, "limited-guidance profiles must be paired with a threshold rule"),
            )
        }
        if (profile.sourceEvidence.isNotEmpty()) {
            throw CatalogLoadException(
                CatalogLoadError.InvalidRuleShape(filmID, "limited-guidance profiles cannot carry sourceEvidence rows"),
            )
        }
        validateExplicitModelBasis(profile, filmID, hasFormula, hasLimitedGuidance)
    }

    private fun validateExplicitModelBasis(
        profile: ReciprocityProfile,
        filmID: String,
        hasFormula: Boolean,
        hasLimitedGuidance: Boolean,
        hasTableInterpolation: Boolean = false,
    ) {
        val basis = profile.modelBasis ?: return

        when (basis.calculationModel) {
            ReciprocityCalculationModel.guardedFormula -> if (!hasFormula) {
                throw CatalogLoadException(
                    CatalogLoadError.InvalidRuleShape(filmID, "modelBasis.calculationModel = guardedFormula requires a formula rule"),
                )
            }
            ReciprocityCalculationModel.tableLogLogInterpolation -> if (!hasTableInterpolation) {
                throw CatalogLoadException(
                    CatalogLoadError.InvalidRuleShape(filmID, "modelBasis.calculationModel = tableLogLogInterpolation requires a table-interpolation rule"),
                )
            }
            ReciprocityCalculationModel.limitedGuidance -> if (!hasLimitedGuidance) {
                throw CatalogLoadException(
                    CatalogLoadError.InvalidRuleShape(filmID, "modelBasis.calculationModel = limitedGuidance requires a limited-guidance rule"),
                )
            }
            ReciprocityCalculationModel.unsupported -> throw CatalogLoadException(
                CatalogLoadError.InvalidRuleShape(filmID, "modelBasis.calculationModel = unsupported is not implemented for launch preset modelBasis yet"),
            )
            ReciprocityCalculationModel.tableLookup -> throw CatalogLoadException(
                CatalogLoadError.InvalidRuleShape(filmID, "modelBasis.calculationModel = tableLookup is not yet implemented"),
            )
        }

        when (basis.sourceModel) {
            ReciprocitySourceModel.manufacturerFormula,
            ReciprocitySourceModel.manufacturerTable,
            ReciprocitySourceModel.manufacturerGraphTable,
            ReciprocitySourceModel.manufacturerRangeGuidance,
            ReciprocitySourceModel.manufacturerLimitedGuidance -> Unit
            ReciprocitySourceModel.practicalCommunityGuidance ->
                if (!isPromotedUnofficialPracticalPrimary(profile, filmID)) {
                    throw CatalogLoadException(
                        CatalogLoadError.InvalidRuleShape(filmID, "modelBasis.sourceModel = practicalCommunityGuidance is not allowed for the official manufacturer launch catalog"),
                    )
                }
            ReciprocitySourceModel.userDefined -> throw CatalogLoadException(
                CatalogLoadError.InvalidRuleShape(filmID, "modelBasis.sourceModel = userDefined is not allowed for the official manufacturer launch catalog"),
            )
            ReciprocitySourceModel.unknown -> throw CatalogLoadException(
                CatalogLoadError.InvalidRuleShape(filmID, "modelBasis.sourceModel = unknown is not allowed for the launch catalog; omit modelBasis to rely on the inferred fallback"),
            )
        }
    }

    private fun validateFormulaParameters(profile: ReciprocityProfile, filmID: String) {
        for (rule in profile.rules) {
            val formulaRule = rule.formula ?: continue
            if (!formulaRule.formula.hasValidParameters) {
                throw CatalogLoadException(
                    CatalogLoadError.InvalidRuleShape(
                        filmID,
                        "formula parameters violate the safe-formula contract (finite, positive coefficient and reference, non-negative no-correction boundary, source-range above no-correction)",
                    ),
                )
            }
        }
    }

    private fun validateTableInterpolationParameters(profile: ReciprocityProfile, filmID: String) {
        for (rule in profile.rules) {
            val tableRule = rule.tableInterpolation ?: continue
            if (!tableRule.hasValidParameters) {
                throw CatalogLoadException(
                    CatalogLoadError.InvalidRuleShape(
                        filmID,
                        "table-interpolation anchors violate the safe-table contract (at least two ascending positive anchors, each corrected ≥ metered, no-correction below the first anchor, source range at the last anchor)",
                    ),
                )
            }
        }
    }
}

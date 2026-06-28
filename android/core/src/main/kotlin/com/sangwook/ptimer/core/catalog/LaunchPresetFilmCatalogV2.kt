// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.ColorFilterRecommendation
import com.sangwook.ptimer.core.reciprocity.CorrectedTimeMapping
import com.sangwook.ptimer.core.reciprocity.DevelopmentAdjustment
import com.sangwook.ptimer.core.reciprocity.ExposureAdjustment
import com.sangwook.ptimer.core.reciprocity.ExposureAdjustmentKind
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.FilmProductionStatus
import com.sangwook.ptimer.core.reciprocity.FormulaFamily
import com.sangwook.ptimer.core.reciprocity.FormulaReciprocityRule
import com.sangwook.ptimer.core.reciprocity.LimitedGuidanceReciprocityRule
import com.sangwook.ptimer.core.reciprocity.MeteredExposureSelector
import com.sangwook.ptimer.core.reciprocity.MeteredExposureSelectorKind
import com.sangwook.ptimer.core.reciprocity.MultiplierAdjustment
import com.sangwook.ptimer.core.reciprocity.ReciprocityAdjustment
import com.sangwook.ptimer.core.reciprocity.ReciprocityAdjustmentKind
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationModel
import com.sangwook.ptimer.core.reciprocity.ReciprocityConfidence
import com.sangwook.ptimer.core.reciprocity.ReciprocityFormula
import com.sangwook.ptimer.core.reciprocity.ReciprocityNote
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfileModelBasis
import com.sangwook.ptimer.core.reciprocity.ReciprocityRule
import com.sangwook.ptimer.core.reciprocity.ReciprocityRuleKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceEvidenceRow
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceKind
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceModel
import com.sangwook.ptimer.core.reciprocity.ReciprocitySourceProvenance
import com.sangwook.ptimer.core.reciprocity.ReciprocityTimeRange
import com.sangwook.ptimer.core.reciprocity.ReciprocityWarning
import com.sangwook.ptimer.core.reciprocity.ReciprocityWarningSeverity
import com.sangwook.ptimer.core.reciprocity.StopDeltaAdjustment
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import com.sangwook.ptimer.core.reciprocity.TableInterpolationReciprocityRule
import com.sangwook.ptimer.core.reciprocity.ThresholdReciprocityRule
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

sealed class CatalogV2LoadError(val description: String) {
    data class MissingBundledResource(val resourceName: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 resource '$resourceName' was not found.")

    data class MalformedResource(val reason: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 resource is malformed: $reason")

    data object EmptyCatalog : CatalogV2LoadError("Bundled launch preset film catalog v2 is empty.")

    data class InvalidSchema(val schema: String, val schemaVersion: Int) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 has unsupported schema '$schema' version $schemaVersion.")

    data object InvalidSourceIdentifier :
        CatalogV2LoadError("Bundled launch preset film catalog v2 contains a source with an empty identifier.")

    data class DuplicateSourceIdentifier(val id: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 contains a duplicate source identifier '$id'.")

    data object InvalidFilmIdentifier :
        CatalogV2LoadError("Bundled launch preset film catalog v2 contains a film with an empty identifier.")

    data class DuplicateFilmIdentifier(val id: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 contains a duplicate film identifier '$id'.")

    data class InvalidCanonicalStockName(val filmID: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 contains an empty canonical stock name for film '$filmID'.")

    data class InvalidProfileIdentifier(val filmID: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 film '$filmID' contains a profile with an empty identifier.")

    data class DuplicateProfileIdentifier(val id: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 contains a duplicate profile identifier '$id'.")

    data class UnresolvedSourceReference(val filmID: String, val profileID: String, val sourceID: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 film '$filmID' profile '$profileID' references missing source '$sourceID'.")

    data class InvalidPrimaryProfileCount(val filmID: String, val count: Int) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 film '$filmID' has $count primary profiles; launch scope requires exactly one.")

    data class InvalidFilmISO(val filmID: String, val iso: Int) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 film '$filmID' has non-positive ISO $iso; launch scope requires a positive box-speed ISO.")

    data class InvalidRuleShape(val filmID: String, val profileID: String, val reason: String) :
        CatalogV2LoadError("Bundled launch preset film catalog v2 film '$filmID' profile '$profileID' has an unsupported reciprocity rule shape: $reason.")
}

class CatalogV2LoadException(val error: CatalogV2LoadError) : Exception(error.description)

object LaunchPresetFilmCatalogV2 {
    const val RESOURCE_NAME: String = "LaunchPresetFilmCatalog.v2.json"

    val films: List<FilmIdentity> by lazy { LaunchPresetFilmCatalogV2Loader().loadBundledCatalog() }
}

class LaunchPresetFilmCatalogV2Loader {

    private val json = Json { ignoreUnknownKeys = true }

    fun loadBundledCatalog(resourceName: String = LaunchPresetFilmCatalogV2.RESOURCE_NAME): List<FilmIdentity> {
        val stream = javaClass.classLoader?.getResourceAsStream(resourceName)
            ?: throw CatalogV2LoadException(CatalogV2LoadError.MissingBundledResource(resourceName))
        val text = stream.bufferedReader().use { it.readText() }
        return loadCatalog(text)
    }

    fun loadCatalog(jsonText: String): List<FilmIdentity> {
        val document = try {
            val root = json.parseToJsonElement(jsonText)
            rejectExplicitNulls(root)
            rejectCalculationKind(root)
            decodeDocument(root)
        } catch (e: CatalogV2LoadException) {
            throw e
        } catch (e: Exception) {
            throw CatalogV2LoadException(CatalogV2LoadError.MalformedResource(e.message ?: "decode failed"))
        }

        validateLaunchCatalog(document)
        return document.films.map { adaptFilm(it, document.sources) }
    }

    private fun decodeDocument(root: JsonElement): CatalogV2Document {
        val document = json.decodeFromJsonElement<CatalogV2DocumentShape>(root)
        return CatalogV2Document(
            schema = document.schema,
            schemaVersion = document.schemaVersion,
            catalogVersion = document.catalogVersion,
            license = document.license,
            copyright = document.copyright,
            sources = document.sources,
            films = document.films.map { film ->
                film.copy(
                    profiles = film.profiles.map { profile ->
                        profile.withCalculation(decodeCalculation(profile.model, profile.calculation))
                    },
                )
            },
        )
    }

    private fun decodeCalculation(model: CatalogV2ProfileModel, calculation: JsonObject): CatalogV2Calculation =
        try {
            when (model) {
                CatalogV2ProfileModel.table ->
                    CatalogV2Calculation.Table(json.decodeFromJsonElement(calculation))
                CatalogV2ProfileModel.formula ->
                    CatalogV2Calculation.Formula(json.decodeFromJsonElement(calculation))
                CatalogV2ProfileModel.limitedGuidance ->
                    CatalogV2Calculation.LimitedGuidance(json.decodeFromJsonElement(calculation))
            }
        } catch (e: SerializationException) {
            throw CatalogV2LoadException(CatalogV2LoadError.MalformedResource(e.message ?: "decode failed"))
        }

    private fun rejectExplicitNulls(element: JsonElement) {
        when (element) {
            JsonNull -> throw CatalogV2LoadException(
                CatalogV2LoadError.MalformedResource("Explicit null is not accepted in catalog v2 optional fields."),
            )
            is JsonArray -> element.forEach(::rejectExplicitNulls)
            is JsonObject -> element.values.forEach(::rejectExplicitNulls)
            else -> Unit
        }
    }

    private fun rejectCalculationKind(root: JsonElement) {
        val films = root.jsonObject["films"]?.jsonArray ?: return
        for (film in films) {
            val profiles = film.jsonObject["profiles"]?.jsonArray ?: continue
            for (profile in profiles) {
                val calculation = profile.jsonObject["calculation"] as? JsonObject ?: continue
                if (calculation.containsKey("kind")) {
                    throw CatalogV2LoadException(
                        CatalogV2LoadError.MalformedResource(
                            "Catalog v2 uses profile.model as the only calculation discriminator.",
                        ),
                    )
                }
            }
        }
    }

    private fun validateLaunchCatalog(document: CatalogV2Document) {
        if (document.schema != "ptimer.catalog.v2" || document.schemaVersion != 2) {
            throw CatalogV2LoadException(CatalogV2LoadError.InvalidSchema(document.schema, document.schemaVersion))
        }
        if (document.films.isEmpty()) throw CatalogV2LoadException(CatalogV2LoadError.EmptyCatalog)

        val sourceIDs = HashSet<String>()
        for (sourceID in document.sources.keys) {
            val trimmedID = sourceID.trim()
            if (trimmedID.isEmpty()) throw CatalogV2LoadException(CatalogV2LoadError.InvalidSourceIdentifier)
            if (!sourceIDs.add(trimmedID)) throw CatalogV2LoadException(CatalogV2LoadError.DuplicateSourceIdentifier(trimmedID))
        }

        val filmIDs = HashSet<String>()
        val profileIDs = HashSet<String>()
        for (film in document.films) {
            val filmID = film.id.trim()
            if (filmID.isEmpty()) throw CatalogV2LoadException(CatalogV2LoadError.InvalidFilmIdentifier)
            if (!filmIDs.add(filmID)) throw CatalogV2LoadException(CatalogV2LoadError.DuplicateFilmIdentifier(filmID))
            if (film.iso <= 0) throw CatalogV2LoadException(CatalogV2LoadError.InvalidFilmISO(filmID, film.iso))
            if (film.canonicalStockName.trim().isEmpty()) {
                throw CatalogV2LoadException(CatalogV2LoadError.InvalidCanonicalStockName(filmID))
            }

            if (film.kind == CatalogV2FilmKind.preset) {
                val primaryCount = film.profiles.count { it.role == CatalogV2ProfileRole.primary }
                if (primaryCount != 1) {
                    throw CatalogV2LoadException(CatalogV2LoadError.InvalidPrimaryProfileCount(filmID, primaryCount))
                }
            }

            for (profile in film.profiles) {
                val profileID = profile.id.trim()
                if (profileID.isEmpty()) {
                    throw CatalogV2LoadException(CatalogV2LoadError.InvalidProfileIdentifier(filmID))
                }
                if (!profileIDs.add(profileID)) {
                    throw CatalogV2LoadException(CatalogV2LoadError.DuplicateProfileIdentifier(profileID))
                }
                val sourceEntry = document.sources[profile.sourceId]
                if (sourceEntry == null || !sourceIDs.contains(profile.sourceId)) {
                    throw CatalogV2LoadException(
                        CatalogV2LoadError.UnresolvedSourceReference(filmID, profileID, profile.sourceId),
                    )
                }
                validateCalculationShape(profile, sourceEntry, filmID)
            }
        }
    }

    private fun validateCalculationShape(
        profile: CatalogV2Profile,
        source: CatalogV2SourceRegistryEntry,
        filmID: String,
    ) {
        validateCarrierShape(profile, filmID)

        when (val calculation = profile.typedCalculation) {
            is CatalogV2Calculation.Table -> {
                if (profile.model != CatalogV2ProfileModel.table) {
                    throw invalidShape(filmID, profile.id, "calculation block does not match profile model")
                }
                validateTableCalculation(calculation.value, profile, filmID)
            }
            is CatalogV2Calculation.Formula -> {
                if (profile.model != CatalogV2ProfileModel.formula) {
                    throw invalidShape(filmID, profile.id, "calculation block does not match profile model")
                }
                validateFormulaCalculation(calculation.value, profile, filmID)
            }
            is CatalogV2Calculation.LimitedGuidance -> {
                if (profile.model != CatalogV2ProfileModel.limitedGuidance) {
                    throw invalidShape(filmID, profile.id, "calculation block does not match profile model")
                }
                validateLimitedGuidanceCalculation(calculation.value, profile, filmID)
            }
            null -> throw invalidShape(filmID, profile.id, "calculation block does not match profile model")
        }

        validatePromotedUnofficialPrimary(profile, source, filmID)
    }

    private fun validateCarrierShape(profile: CatalogV2Profile, filmID: String) {
        when (profile.model) {
            CatalogV2ProfileModel.table -> {
                if (profile.referencePoints != null || profile.referenceRanges != null) {
                    throw invalidShape(
                        filmID,
                        profile.id,
                        "table profiles must not carry formula reference carriers",
                    )
                }
            }
            CatalogV2ProfileModel.formula -> {
                if (profile.evidence != null) {
                    throw invalidShape(filmID, profile.id, "formula profiles must not carry table evidence")
                }
            }
            CatalogV2ProfileModel.limitedGuidance -> {
                if (profile.evidence != null ||
                    profile.referencePoints != null ||
                    profile.referenceRanges != null
                ) {
                    throw invalidShape(
                        filmID,
                        profile.id,
                        "limited-guidance profiles must not carry source-evidence carriers",
                    )
                }
            }
        }
    }

    private fun validatePromotedUnofficialPrimary(
        profile: CatalogV2Profile,
        source: CatalogV2SourceRegistryEntry,
        filmID: String,
    ) {
        if (profile.role != CatalogV2ProfileRole.primary ||
            (profile.authority != CatalogV2ProfileAuthority.community &&
                profile.authority != CatalogV2ProfileAuthority.unofficial)
        ) {
            return
        }

        if (source.authority == CatalogV2SourceAuthority.official ||
            source.sourceType == CatalogV2SourceType.manufacturerPublished ||
            source.sourceType == CatalogV2SourceType.manufacturerArchive
        ) {
            throw invalidShape(
                filmID,
                profile.id,
                "promoted unofficial primary profiles require non-official, non-manufacturer provenance",
            )
        }
        if (source.confidence == CatalogV2Confidence.high) {
            throw invalidShape(
                filmID,
                profile.id,
                "promoted unofficial primary profiles must not use high-confidence sources",
            )
        }
        if (profile.basis != CatalogV2ProfileBasis.practicalCommunityGuidance) {
            throw invalidShape(
                filmID,
                profile.id,
                "promoted unofficial primary profiles require practical community guidance basis",
            )
        }
        if (profile.model != CatalogV2ProfileModel.formula) {
            throw invalidShape(
                filmID,
                profile.id,
                "promoted unofficial primary profiles require formula calculation",
            )
        }
        if (profile.referencePoints.orEmpty().isEmpty()) {
            throw invalidShape(
                filmID,
                profile.id,
                "promoted unofficial primary profiles require at least one reference point",
            )
        }
    }

    private fun validateTableCalculation(
        calculation: CatalogV2TableCalculation,
        profile: CatalogV2Profile,
        filmID: String,
    ) {
        if (calculation.anchors.isEmpty()) {
            throw invalidShape(filmID, profile.id, "table profiles require at least one anchor")
        }
        if (!calculation.noCorrectionThroughSeconds.isFinite() || calculation.noCorrectionThroughSeconds < 0) {
            throw invalidShape(filmID, profile.id, "table no-correction boundary must be finite and non-negative")
        }
        if (!calculation.sourceRangeThroughSeconds.isFinite() ||
            calculation.sourceRangeThroughSeconds <= calculation.noCorrectionThroughSeconds
        ) {
            throw invalidShape(filmID, profile.id, "table source range must be finite and above the no-correction boundary")
        }

        var previousMetered: Double? = null
        val seenMetered = HashSet<Double>()
        for (anchor in calculation.anchors) {
            if (!anchor.meteredSeconds.isFinite() || anchor.meteredSeconds <= 0) {
                throw invalidShape(filmID, profile.id, "table anchors require positive finite metered seconds")
            }
            if (!anchor.correctedSeconds.isFinite() || anchor.correctedSeconds < anchor.meteredSeconds) {
                throw invalidShape(
                    filmID,
                    profile.id,
                    "table anchors require corrected seconds greater than or equal to metered seconds",
                )
            }
            if (previousMetered != null && anchor.meteredSeconds <= previousMetered) {
                throw invalidShape(filmID, profile.id, "table anchors must be strictly ascending by metered seconds")
            }
            if (!seenMetered.add(anchor.meteredSeconds)) {
                throw invalidShape(filmID, profile.id, "table anchors must not duplicate metered seconds")
            }
            previousMetered = anchor.meteredSeconds
        }

        if (calculation.noCorrectionThroughSeconds >= calculation.anchors.first().meteredSeconds) {
            throw invalidShape(filmID, profile.id, "table no-correction boundary must be below the first anchor")
        }
        if (calculation.sourceRangeThroughSeconds < calculation.anchors.last().meteredSeconds) {
            throw invalidShape(filmID, profile.id, "table source range must cover the last anchor")
        }

        for (evidence in profile.evidence.orEmpty()) {
            if (evidence.anchor < 0 || evidence.anchor >= calculation.anchors.size) {
                throw invalidShape(filmID, profile.id, "table evidence anchor index is out of range")
            }
        }
    }

    private fun validateFormulaCalculation(
        calculation: CatalogV2FormulaCalculation,
        profile: CatalogV2Profile,
        filmID: String,
    ) {
        val coefficient = calculation.coefficient ?: 1.0
        val referenceMeteredSeconds = calculation.referenceMeteredSeconds ?: 1.0
        val offsetSeconds = calculation.offsetSeconds ?: 0.0

        if (!calculation.exponent.isFinite() || calculation.exponent <= 0) {
            throw invalidShape(filmID, profile.id, "formula exponent must be positive and finite")
        }
        if (!coefficient.isFinite() || coefficient <= 0) {
            throw invalidShape(filmID, profile.id, "formula coefficient must be positive and finite")
        }
        if (!referenceMeteredSeconds.isFinite() || referenceMeteredSeconds <= 0) {
            throw invalidShape(filmID, profile.id, "formula reference metered seconds must be positive and finite")
        }
        if (!offsetSeconds.isFinite() ||
            !calculation.noCorrectionThroughSeconds.isFinite() ||
            calculation.noCorrectionThroughSeconds < 0
        ) {
            throw invalidShape(filmID, profile.id, "formula no-correction boundary and offset must be finite")
        }
        calculation.sourceRangeThroughSeconds?.let { sourceRange ->
            if (!sourceRange.isFinite() || sourceRange <= calculation.noCorrectionThroughSeconds) {
                throw invalidShape(filmID, profile.id, "formula source range must be above the no-correction boundary")
            }
        }

        for (point in profile.referencePoints.orEmpty()) {
            if (!point.meteredSeconds.isFinite() || point.meteredSeconds <= 0) {
                throw invalidShape(filmID, profile.id, "reference points require positive finite metered seconds")
            }
            point.correctedSeconds?.let { correctedSeconds ->
                if (!correctedSeconds.isFinite() || correctedSeconds < point.meteredSeconds) {
                    throw invalidShape(
                        filmID,
                        profile.id,
                        "reference points require corrected seconds greater than or equal to metered seconds",
                    )
                }
            }
        }

        validateReferenceRanges(profile.referenceRanges.orEmpty(), profile, filmID)
    }

    private fun validateLimitedGuidanceCalculation(
        calculation: CatalogV2LimitedGuidanceCalculation,
        profile: CatalogV2Profile,
        filmID: String,
    ) {
        if (calculation.noCorrectionRange.size != 2) {
            throw invalidShape(filmID, profile.id, "limited-guidance noCorrectionRange must contain exactly two values")
        }
        val minimum = calculation.noCorrectionRange[0]
        val maximum = calculation.noCorrectionRange[1]
        if (!minimum.isFinite() || !maximum.isFinite() || minimum >= maximum) {
            throw invalidShape(filmID, profile.id, "limited-guidance noCorrectionRange minimum must be below maximum")
        }

        var previousFromSeconds: Double? = null
        for (guidance in calculation.guidance) {
            if (!guidance.fromSeconds.isFinite() || guidance.fromSeconds < maximum) {
                throw invalidShape(
                    filmID,
                    profile.id,
                    "limited-guidance rows must start at or beyond the no-correction range maximum",
                )
            }
            if (previousFromSeconds != null && guidance.fromSeconds < previousFromSeconds) {
                throw invalidShape(filmID, profile.id, "limited-guidance rows must be sorted")
            }
            previousFromSeconds = guidance.fromSeconds
        }
        validateReferenceRanges(profile.referenceRanges.orEmpty(), profile, filmID)
    }

    private fun validateReferenceRanges(
        ranges: List<CatalogV2ReferenceRange>,
        profile: CatalogV2Profile,
        filmID: String,
    ) {
        for (range in ranges) {
            if (!range.fromSeconds.isFinite() ||
                !range.throughSeconds.isFinite() ||
                range.fromSeconds >= range.throughSeconds
            ) {
                throw invalidShape(filmID, profile.id, "reference ranges require finite fromSeconds below throughSeconds")
            }
        }
    }

    private fun invalidShape(
        filmID: String,
        profileID: String,
        reason: String,
    ): CatalogV2LoadException =
        CatalogV2LoadException(CatalogV2LoadError.InvalidRuleShape(filmID, profileID, reason))

    private fun adaptFilm(
        film: CatalogV2Film,
        sources: Map<String, CatalogV2SourceRegistryEntry>,
    ): FilmIdentity =
        FilmIdentity(
            id = film.id,
            kind = enumValueOrUnknown(film.kind.name, FilmIdentityKind.unknown),
            canonicalStockName = film.canonicalStockName,
            manufacturer = film.manufacturer,
            brandLabel = film.brandLabel,
            aliases = film.aliases,
            iso = film.iso,
            productionStatus = enumValueOrUnknown(film.productionStatus.name, FilmProductionStatus.unknown),
            profiles = film.profiles.map { adaptProfile(it, sources) },
            userMetadata = null,
        )

    private fun adaptProfile(
        profile: CatalogV2Profile,
        sources: Map<String, CatalogV2SourceRegistryEntry>,
    ): ReciprocityProfile {
        val sourceEntry = sources[profile.sourceId]
            ?: error("Catalog v2 validation must resolve every sourceId before adaptation.")

        return ReciprocityProfile(
            id = profile.id,
            name = profile.label,
            source = adaptSource(sourceEntry),
            rules = adaptRules(profile),
            notes = profile.notes.orEmpty(),
            userMetadata = null,
            sourceEvidence = adaptSourceEvidence(profile),
            modelBasis = adaptModelBasis(profile),
            selectorLabel = profile.selectorLabel,
        )
    }

    private fun adaptSource(source: CatalogV2SourceRegistryEntry): ReciprocitySourceProvenance =
        ReciprocitySourceProvenance(
            kind = enumValueOrUnknown(source.sourceType.name, ReciprocitySourceKind.unknown),
            authority = enumValueOrUnknown(source.authority.name, ReciprocityAuthority.unknown),
            confidence = enumValueOrUnknown(source.confidence.name, ReciprocityConfidence.unknown),
            publisher = source.publisher,
            title = source.title,
            citation = source.citation,
            sourceVersion = source.version,
        )

    private fun adaptModelBasis(profile: CatalogV2Profile): ReciprocityProfileModelBasis? {
        val basis = profile.basis ?: return null
        return ReciprocityProfileModelBasis(
            sourceModel = enumValueOrUnknown(basis.name, ReciprocitySourceModel.unknown),
            calculationModel = when (profile.model) {
                CatalogV2ProfileModel.table -> ReciprocityCalculationModel.tableLogLogInterpolation
                CatalogV2ProfileModel.formula -> ReciprocityCalculationModel.guardedFormula
                CatalogV2ProfileModel.limitedGuidance -> ReciprocityCalculationModel.limitedGuidance
            },
        )
    }

    private fun adaptRules(profile: CatalogV2Profile): List<ReciprocityRule> =
        when (val calculation = profile.typedCalculation) {
            is CatalogV2Calculation.Table -> listOf(
                ReciprocityRule(
                    kind = ReciprocityRuleKind.tableInterpolation,
                    tableInterpolation = TableInterpolationReciprocityRule(
                        anchors = calculation.value.anchors.map {
                            TableAnchor(it.meteredSeconds, it.correctedSeconds)
                        },
                        additionalAdjustments = emptyList(),
                        notes = calculation.value.notes.orEmpty(),
                        noCorrectionThroughSeconds = calculation.value.noCorrectionThroughSeconds,
                        sourceRangeThroughSeconds = calculation.value.sourceRangeThroughSeconds,
                    ),
                ),
            )
            is CatalogV2Calculation.Formula -> listOf(
                ReciprocityRule(
                    kind = ReciprocityRuleKind.formula,
                    formula = FormulaReciprocityRule(
                        formula = ReciprocityFormula(
                            formulaFamily = enumValueOrUnknown(
                                calculation.value.family.name,
                                FormulaFamily.modifiedSchwarzschild,
                            ),
                            coefficientSeconds = calculation.value.coefficient ?: 1.0,
                            referenceMeteredTimeSeconds = calculation.value.referenceMeteredSeconds ?: 1.0,
                            exponent = calculation.value.exponent,
                            offsetSeconds = calculation.value.offsetSeconds ?: 0.0,
                            noCorrectionThroughSeconds = calculation.value.noCorrectionThroughSeconds,
                            sourceRangeThroughSeconds = calculation.value.sourceRangeThroughSeconds,
                        ),
                        additionalAdjustments = emptyList(),
                        notes = calculation.value.notes.orEmpty(),
                    ),
                ),
            )
            is CatalogV2Calculation.LimitedGuidance -> {
                val noCorrectionRange = ReciprocityTimeRange(
                    minimumSeconds = calculation.value.noCorrectionRange[0],
                    maximumSeconds = calculation.value.noCorrectionRange[1],
                )
                val guidanceAdjustments = calculation.value.guidance.flatMap { row ->
                    listOfNotNull(
                        row.colorFilter?.let {
                            ReciprocityAdjustment(
                                kind = ReciprocityAdjustmentKind.colorFilter,
                                colorFilter = ColorFilterRecommendation(
                                    filterName = it.filterName,
                                    note = it.note,
                                ),
                            )
                        },
                        ReciprocityAdjustment(
                            kind = ReciprocityAdjustmentKind.note,
                            note = ReciprocityNote(row.message),
                        ),
                    )
                }
                listOf(
                    ReciprocityRule(
                        kind = ReciprocityRuleKind.threshold,
                        threshold = ThresholdReciprocityRule(
                            noCorrectionRange = noCorrectionRange,
                            adjustments = emptyList(),
                            notes = calculation.value.notes.orEmpty(),
                        ),
                    ),
                    ReciprocityRule(
                        kind = ReciprocityRuleKind.limitedGuidance,
                        limitedGuidance = LimitedGuidanceReciprocityRule(
                            appliesWhenMetered = calculation.value.guidance.firstOrNull()?.let {
                                ReciprocityTimeRange(minimumSeconds = it.fromSeconds)
                            },
                            adjustments = guidanceAdjustments,
                            notes = emptyList(),
                        ),
                    ),
                )
            }
            null -> error("Catalog v2 validation must type every calculation before adaptation.")
        }

    private fun adaptSourceEvidence(profile: CatalogV2Profile): List<ReciprocitySourceEvidenceRow> {
        val rows = mutableListOf<ReciprocitySourceEvidenceRow>()

        val tableCalculation = (profile.typedCalculation as? CatalogV2Calculation.Table)?.value
        if (tableCalculation != null) {
            rows += profile.evidence.orEmpty().map { evidence ->
                val anchor = tableCalculation.anchors[evidence.anchor]
                val correctedTime = CorrectedTimeMapping(
                    meteredSeconds = anchor.meteredSeconds,
                    correctedSeconds = anchor.correctedSeconds,
                    isApproximate = evidence.approx == true,
                )

                ReciprocitySourceEvidenceRow(
                    meteredExposure = MeteredExposureSelector(
                        kind = MeteredExposureSelectorKind.exactSeconds,
                        exactSeconds = anchor.meteredSeconds,
                    ),
                    adjustments = adaptAdjustments(evidence, correctedTime),
                    notes = evidence.rowNotes.orEmpty(),
                    isSourceEvidenceOnly = evidence.evidenceOnly == true,
                )
            }
        }

        rows += profile.referencePoints.orEmpty().map { point ->
            val correctedTime = point.correctedSeconds?.let { correctedSeconds ->
                CorrectedTimeMapping(
                    meteredSeconds = point.meteredSeconds,
                    correctedSeconds = correctedSeconds,
                    isApproximate = point.approx == true,
                )
            }

            ReciprocitySourceEvidenceRow(
                meteredExposure = MeteredExposureSelector(
                    kind = MeteredExposureSelectorKind.exactSeconds,
                    exactSeconds = point.meteredSeconds,
                ),
                adjustments = adaptAdjustments(point, correctedTime),
                notes = point.rowNotes.orEmpty(),
                isSourceEvidenceOnly = point.evidenceOnly == true,
            )
        }

        rows += profile.referenceRanges.orEmpty().map { range ->
            ReciprocitySourceEvidenceRow(
                meteredExposure = MeteredExposureSelector(
                    kind = MeteredExposureSelectorKind.range,
                    range = ReciprocityTimeRange(range.fromSeconds, range.throughSeconds),
                ),
                adjustments = adaptAdjustments(range, correctedTime = null),
                notes = range.rowNotes.orEmpty(),
                isSourceEvidenceOnly = false,
            )
        }

        return rows
    }

    private fun adaptAdjustments(
        row: CatalogV2EvidenceFields,
        correctedTime: CorrectedTimeMapping?,
    ): List<ReciprocityAdjustment> {
        val adjustments = mutableListOf<ReciprocityAdjustment>()
        row.stopDelta?.let {
            adjustments += ReciprocityAdjustment(
                kind = ReciprocityAdjustmentKind.exposure,
                exposure = ExposureAdjustment(
                    kind = ExposureAdjustmentKind.stopDelta,
                    stopDelta = StopDeltaAdjustment(it),
                ),
            )
        }
        row.multiplier?.let {
            adjustments += ReciprocityAdjustment(
                kind = ReciprocityAdjustmentKind.exposure,
                exposure = ExposureAdjustment(
                    kind = ExposureAdjustmentKind.multiplier,
                    multiplier = MultiplierAdjustment(it),
                ),
            )
        }
        correctedTime?.let {
            adjustments += ReciprocityAdjustment(
                kind = ReciprocityAdjustmentKind.exposure,
                exposure = ExposureAdjustment(
                    kind = ExposureAdjustmentKind.correctedTime,
                    correctedTime = it,
                ),
            )
        }
        row.colorFilter?.let {
            adjustments += ReciprocityAdjustment(
                kind = ReciprocityAdjustmentKind.colorFilter,
                colorFilter = ColorFilterRecommendation(it),
            )
        }
        row.development?.let {
            adjustments += ReciprocityAdjustment(
                kind = ReciprocityAdjustmentKind.development,
                development = DevelopmentAdjustment(it),
            )
        }
        row.warning?.let {
            adjustments += ReciprocityAdjustment(
                kind = ReciprocityAdjustmentKind.warning,
                warning = ReciprocityWarning(
                    severity = enumValueOrUnknown(it.severity.name, ReciprocityWarningSeverity.caution),
                    message = it.message,
                ),
            )
        }
        row.note?.let {
            adjustments += ReciprocityAdjustment(
                kind = ReciprocityAdjustmentKind.note,
                note = ReciprocityNote(it),
            )
        }
        return adjustments
    }

    private inline fun <reified T : Enum<T>> enumValueOrUnknown(name: String, unknown: T): T =
        enumValues<T>().firstOrNull { it.name == name } ?: unknown
}

@Serializable
private data class CatalogV2DocumentShape(
    val schema: String,
    val schemaVersion: Int,
    val catalogVersion: String,
    val license: String,
    val copyright: String,
    val sources: Map<String, CatalogV2SourceRegistryEntry>,
    val films: List<CatalogV2Film>,
)

private data class CatalogV2Document(
    val schema: String,
    val schemaVersion: Int,
    val catalogVersion: String,
    val license: String,
    val copyright: String,
    val sources: Map<String, CatalogV2SourceRegistryEntry>,
    val films: List<CatalogV2Film>,
)

@Serializable
private data class CatalogV2SourceRegistryEntry(
    val publisher: String,
    val title: String? = null,
    val citation: String? = null,
    val sourceType: CatalogV2SourceType,
    val authority: CatalogV2SourceAuthority,
    val confidence: CatalogV2Confidence,
    val version: String? = null,
    val links: CatalogV2SourceLinks? = null,
)

@Serializable
private data class CatalogV2SourceLinks(
    val landingPageUrl: String? = null,
    val downloadUrl: String? = null,
    val archiveUrl: String? = null,
    val accessedDate: String? = null,
)

@Serializable
private data class CatalogV2Film(
    val id: String,
    val canonicalStockName: String,
    val manufacturer: String,
    val brandLabel: String,
    val aliases: List<String>,
    val iso: Int,
    val kind: CatalogV2FilmKind,
    val productionStatus: CatalogV2ProductionStatus,
    val profiles: List<CatalogV2Profile>,
)

@Serializable
private data class CatalogV2Profile(
    val id: String,
    val label: String,
    val selectorLabel: String? = null,
    val role: CatalogV2ProfileRole,
    val authority: CatalogV2ProfileAuthority,
    val basis: CatalogV2ProfileBasis? = null,
    val sourceId: String,
    val model: CatalogV2ProfileModel,
    val calculation: JsonObject,
    val evidence: List<CatalogV2TableEvidence>? = null,
    val referencePoints: List<CatalogV2ReferencePoint>? = null,
    val referenceRanges: List<CatalogV2ReferenceRange>? = null,
    val notes: List<String>? = null,
    @kotlinx.serialization.Transient val typedCalculation: CatalogV2Calculation? = null,
) {
    fun withCalculation(value: CatalogV2Calculation): CatalogV2Profile = copy(typedCalculation = value)
}

private sealed interface CatalogV2Calculation {
    data class Table(val value: CatalogV2TableCalculation) : CatalogV2Calculation
    data class Formula(val value: CatalogV2FormulaCalculation) : CatalogV2Calculation
    data class LimitedGuidance(val value: CatalogV2LimitedGuidanceCalculation) : CatalogV2Calculation
}

@Serializable
private data class CatalogV2TableCalculation(
    val interpolation: CatalogV2TableInterpolation,
    val noCorrectionThroughSeconds: Double,
    val sourceRangeThroughSeconds: Double,
    val anchors: List<CatalogV2TableAnchor>,
    val notes: List<String>? = null,
)

@Serializable
private data class CatalogV2FormulaCalculation(
    val family: CatalogV2FormulaFamily,
    val coefficient: Double? = null,
    val referenceMeteredSeconds: Double? = null,
    val exponent: Double,
    val offsetSeconds: Double? = null,
    val noCorrectionThroughSeconds: Double,
    val sourceRangeThroughSeconds: Double? = null,
    val notes: List<String>? = null,
)

@Serializable
private data class CatalogV2LimitedGuidanceCalculation(
    val noCorrectionRange: List<Double>,
    val guidance: List<CatalogV2GuidanceRow>,
    val notes: List<String>? = null,
)

@Serializable
private data class CatalogV2TableAnchor(
    val meteredSeconds: Double,
    val correctedSeconds: Double,
)

@Serializable
private data class CatalogV2GuidanceRow(
    val fromSeconds: Double,
    val colorFilter: CatalogV2GuidanceColorFilter? = null,
    val message: String,
)

@Serializable
private data class CatalogV2GuidanceColorFilter(
    val filterName: String,
    val note: String? = null,
)

private interface CatalogV2EvidenceFields {
    val stopDelta: Double?
    val multiplier: Double?
    val colorFilter: String?
    val development: String?
    val warning: CatalogV2Warning?
    val note: String?
    val rowNotes: List<String>?
}

@Serializable
private data class CatalogV2TableEvidence(
    val anchor: Int,
    override val stopDelta: Double? = null,
    override val multiplier: Double? = null,
    override val colorFilter: String? = null,
    override val development: String? = null,
    override val warning: CatalogV2Warning? = null,
    override val note: String? = null,
    override val rowNotes: List<String>? = null,
    val approx: Boolean? = null,
    val evidenceOnly: Boolean? = null,
) : CatalogV2EvidenceFields

@Serializable
private data class CatalogV2ReferencePoint(
    val meteredSeconds: Double,
    val correctedSeconds: Double? = null,
    override val stopDelta: Double? = null,
    override val multiplier: Double? = null,
    override val colorFilter: String? = null,
    override val development: String? = null,
    override val warning: CatalogV2Warning? = null,
    override val note: String? = null,
    override val rowNotes: List<String>? = null,
    val approx: Boolean? = null,
    val evidenceOnly: Boolean? = null,
) : CatalogV2EvidenceFields

@Serializable
private data class CatalogV2ReferenceRange(
    val fromSeconds: Double,
    val throughSeconds: Double,
    override val stopDelta: Double? = null,
    override val multiplier: Double? = null,
    override val colorFilter: String? = null,
    override val development: String? = null,
    override val warning: CatalogV2Warning? = null,
    override val note: String? = null,
    override val rowNotes: List<String>? = null,
) : CatalogV2EvidenceFields

@Serializable
private data class CatalogV2Warning(
    val severity: CatalogV2WarningSeverity,
    val message: String,
)

@Serializable
private enum class CatalogV2SourceType {
    manufacturerPublished,
    manufacturerArchive,
    thirdPartyPublication,
    userDefined,
    unknown,
}

@Serializable
private enum class CatalogV2SourceAuthority { official, unofficial, userDefined, unknown }

@Serializable
private enum class CatalogV2Confidence { high, medium, low, unknown }

@Serializable
private enum class CatalogV2FilmKind { preset, custom, unknown }

@Serializable
private enum class CatalogV2ProductionStatus { current, discontinued, unknown }

@Serializable
private enum class CatalogV2ProfileRole { primary, alternate, derived }

@Serializable
private enum class CatalogV2ProfileAuthority { official, appDerived, community, unofficial, userDefined }

@Serializable
private enum class CatalogV2ProfileBasis {
    manufacturerFormula,
    manufacturerTable,
    manufacturerGraphTable,
    manufacturerRangeGuidance,
    manufacturerLimitedGuidance,
    practicalCommunityGuidance,
}

@Serializable
private enum class CatalogV2ProfileModel { formula, table, limitedGuidance }

@Serializable
private enum class CatalogV2TableInterpolation { logLog }

@Serializable
private enum class CatalogV2FormulaFamily { modifiedSchwarzschild }

@Serializable
private enum class CatalogV2WarningSeverity { caution, notRecommended }

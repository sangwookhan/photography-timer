package com.sangwook.ptimer.core.catalog

import kotlinx.serialization.json.Json

/** Shared lenient JSON config for catalog + persistence decoding. */
internal val CatalogJson: Json = Json {
    ignoreUnknownKeys = true
    isLenient = true
}

/** Thrown when the bundled catalog is missing, malformed, or fails validation. */
class CatalogLoadException(message: String) : Exception(message)

/**
 * Loads and validates the bundled launch preset film catalog from a JVM
 * classpath resource. Mirrors iOS `LaunchPresetFilmCatalogLoader`: fails
 * clearly on missing/malformed/invalid data, preserves catalog order, and
 * returns typed film identities. Validation asserts the catalog's three
 * real profile shapes (formula / tableInterpolation / threshold+
 * limitedGuidance) rather than the older two-shape fixture rule.
 */
object LaunchPresetFilmCatalogLoader {

    private const val RESOURCE = "/com/sangwook/ptimer/core/catalog/LaunchPresetFilmCatalog.json"

    /** Source kinds whose film is allowed to be a non-manufacturer promoted primary. */
    private val PROMOTED_PRIMARY_IDS = setOf("rollei-retro-400s")

    fun loadBundledCatalog(): List<FilmIdentity> {
        val stream = LaunchPresetFilmCatalogLoader::class.java.getResourceAsStream(RESOURCE)
            ?: throw CatalogLoadException("Bundled catalog resource not found at $RESOURCE")
        val text = stream.bufferedReader().use { it.readText() }
        return loadCatalog(text)
    }

    fun loadCatalog(json: String): List<FilmIdentity> {
        val films = try {
            CatalogJson.decodeFromString<List<FilmIdentity>>(json)
        } catch (e: Exception) {
            throw CatalogLoadException("Catalog JSON is malformed: ${e.message}")
        }
        validate(films)
        return films
    }

    private fun validate(films: List<FilmIdentity>) {
        if (films.isEmpty()) throw CatalogLoadException("Catalog is empty.")

        val ids = films.map { it.id }
        if (ids.size != ids.toSet().size) throw CatalogLoadException("Duplicate film id in catalog.")
        val names = films.map { it.canonicalStockName }
        if (names.size != names.toSet().size) throw CatalogLoadException("Duplicate canonicalStockName in catalog.")

        for (film in films) {
            if (film.kind != "preset") throw CatalogLoadException("Film ${film.id} is not a preset.")
            if (film.productionStatus != "current") throw CatalogLoadException("Film ${film.id} is not current.")
            if (film.iso <= 0) throw CatalogLoadException("Film ${film.id} has non-positive ISO.")
            if (film.profiles.size != 1) throw CatalogLoadException("Film ${film.id} must have exactly one profile.")

            val profile = film.profiles.first()
            validateProfileShape(film.id, profile)
            validatePrimarySource(film.id, profile)
        }
    }

    private fun validateProfileShape(filmId: String, profile: ReciprocityProfile) {
        val typed = profile.typedRules
        if (typed.isEmpty()) throw CatalogLoadException("Film $filmId profile has no recognized rules.")

        val kinds = typed.map { it::class.simpleName }.toSet()
        val formulaOnly = typed.size == 1 && typed.first() is ReciprocityRule.Formula
        val tableOnly = typed.size == 1 && typed.first() is ReciprocityRule.Table
        val thresholdLimited = typed.size == 2 &&
            typed.any { it is ReciprocityRule.Threshold } &&
            typed.any { it is ReciprocityRule.LimitedGuidance }

        if (!(formulaOnly || tableOnly || thresholdLimited)) {
            throw CatalogLoadException("Film $filmId profile shape not allowed: $kinds")
        }

        // Validate parameters of the calculation rules.
        typed.forEach { rule ->
            when (rule) {
                is ReciprocityRule.Formula ->
                    if (!rule.formula.hasValidParameters) {
                        throw CatalogLoadException("Film $filmId formula parameters are invalid.")
                    }
                is ReciprocityRule.Table ->
                    if (!rule.rule.hasValidParameters) {
                        throw CatalogLoadException("Film $filmId table parameters are invalid.")
                    }
                else -> Unit
            }
        }
    }

    private fun validatePrimarySource(filmId: String, profile: ReciprocityProfile) {
        if (filmId in PROMOTED_PRIMARY_IDS) return
        if (profile.source.authority != "official") {
            throw CatalogLoadException("Film $filmId primary profile is not official.")
        }
        if (profile.source.kind != "manufacturerPublished") {
            throw CatalogLoadException("Film $filmId primary source is not manufacturerPublished.")
        }
    }

    /** Profile shape of a film for reporting/tests. */
    fun shapeOf(film: FilmIdentity): String {
        val typed = film.profiles.firstOrNull()?.typedRules ?: emptyList()
        return when {
            typed.size == 1 && typed.first() is ReciprocityRule.Formula -> "formula"
            typed.size == 1 && typed.first() is ReciprocityRule.Table -> "tableInterpolation"
            typed.any { it is ReciprocityRule.Threshold } &&
                typed.any { it is ReciprocityRule.LimitedGuidance } -> "threshold+limitedGuidance"
            else -> "unknown"
        }
    }
}

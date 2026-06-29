#!/usr/bin/env python3
"""PTIMER-186: v2-only launch catalog verifier.

Run from the repository root:
    python3 tools/catalog-v2/verify.py

Exit 0 on PASS, 1 on any mismatch.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
V2_COPIES = [
    ROOT / "shared/catalog/LaunchPresetFilmCatalog.v2.json",
    ROOT / "ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.v2.json",
    ROOT / "android/core/src/main/resources/LaunchPresetFilmCatalog.v2.json",
]
EXPECTATIONS_PATH = ROOT / "shared/test-fixtures/catalog-validation-cases.json"

TABLE_KEYS = {
    "interpolation",
    "noCorrectionThroughSeconds",
    "sourceRangeThroughSeconds",
    "anchors",
    "notes",
}
FORMULA_KEYS = {
    "family",
    "coefficient",
    "referenceMeteredSeconds",
    "exponent",
    "offsetSeconds",
    "noCorrectionThroughSeconds",
    "sourceRangeThroughSeconds",
    "notes",
}
LIMITED_GUIDANCE_KEYS = {"noCorrectionRange", "guidance", "notes"}
EVIDENCE_KEYS = {
    "anchor",
    "stopDelta",
    "multiplier",
    "development",
    "colorFilter",
    "warning",
    "note",
    "approx",
    "evidenceOnly",
    "rowNotes",
}
REFERENCE_POINT_KEYS = (EVIDENCE_KEYS | {"meteredSeconds", "correctedSeconds"}) - {"anchor"}
REFERENCE_RANGE_KEYS = (EVIDENCE_KEYS | {"fromSeconds", "throughSeconds", "correctedSeconds"}) - {"anchor"}
WARNING_KEYS = {"severity", "message"}
COLOR_FILTER_KEYS = {"filterName", "note"}
SOURCE_LINK_KEYS = {"landingPageUrl", "downloadUrl", "archiveUrl", "accessedDate"}


errors: list[str] = []


def main() -> int:
    assert_copies_identical()
    catalog = load_json(V2_COPIES[0])
    expectations = load_json(EXPECTATIONS_PATH)["catalogExpectations"]

    validate_schema(catalog)
    validate_sources(catalog)
    validate_films(catalog)
    validate_expectations(catalog, expectations)

    if errors:
        print(f"FAIL: {len(errors)} errors")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(f"PASS: {len(catalog['films'])} v2 films verified.")
    return 0


def assert_copies_identical() -> None:
    canonical = V2_COPIES[0].read_bytes()
    for path in V2_COPIES[1:]:
        if path.read_bytes() != canonical:
            errors.append(f"v2 copy is not byte-identical to canonical: {relative(path)}")


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def validate_schema(catalog: dict) -> None:
    if catalog.get("schema") != "ptimer.catalog.v2":
        errors.append(f"schema is {catalog.get('schema')!r}")
    if catalog.get("schemaVersion") != 2:
        errors.append(f"schemaVersion is {catalog.get('schemaVersion')!r}")


def validate_sources(catalog: dict) -> None:
    sources = catalog.get("sources")
    if not isinstance(sources, dict):
        errors.append("sources must be an object")
        return

    for source_id, source in sources.items():
        if not isinstance(source_id, str) or not source_id.strip():
            errors.append("source id must be a non-empty string")
        if not isinstance(source, dict):
            errors.append(f"{source_id}: source entry must be an object")
            continue
        links = source.get("links")
        if links is None:
            continue
        if not isinstance(links, dict):
            errors.append(f"{source_id}: links must be an object")
            continue
        unknown = set(links) - SOURCE_LINK_KEYS
        if unknown:
            errors.append(f"{source_id}: unknown source link keys {sorted(unknown)}")
        for key, value in links.items():
            if not isinstance(value, str) or value == "":
                errors.append(f"{source_id}: links.{key} must be a non-empty string")


def validate_films(catalog: dict) -> None:
    sources = catalog.get("sources", {})
    films = catalog.get("films")
    if not isinstance(films, list):
        errors.append("films must be an array")
        return

    seen_films: set[str] = set()
    seen_profiles: set[str] = set()
    for index, film in enumerate(films):
        if not isinstance(film, dict):
            errors.append(f"films[{index}] must be an object")
            continue

        film_id = film.get("id")
        if not isinstance(film_id, str) or not film_id.strip():
            errors.append(f"films[{index}]: id must be a non-empty string")
            film_id = f"films[{index}]"
        elif film_id in seen_films:
            errors.append(f"{film_id}: duplicate film id")
        seen_films.add(film_id)

        profiles = film.get("profiles")
        if not isinstance(profiles, list):
            errors.append(f"{film_id}: profiles must be an array")
            continue

        if film.get("kind") == "preset":
            primary_count = sum(1 for profile in profiles if profile.get("role") == "primary")
            if primary_count != 1:
                errors.append(f"{film_id}: expected exactly one primary profile, found {primary_count}")

        for profile in profiles:
            validate_profile(film_id, profile, sources, seen_profiles)


def validate_profile(
    film_id: str,
    profile: dict,
    sources: dict,
    seen_profiles: set[str],
) -> None:
    if not isinstance(profile, dict):
        errors.append(f"{film_id}: profile must be an object")
        return

    profile_id = profile.get("id")
    if not isinstance(profile_id, str) or not profile_id.strip():
        errors.append(f"{film_id}: profile id must be a non-empty string")
        profile_id = "<unknown>"
    elif profile_id in seen_profiles:
        errors.append(f"{film_id}/{profile_id}: duplicate profile id")
    seen_profiles.add(profile_id)

    source_id = profile.get("sourceId")
    if source_id not in sources:
        errors.append(f"{film_id}/{profile_id}: sourceId {source_id!r} does not resolve")

    model = profile.get("model")
    calculation = profile.get("calculation")
    if not isinstance(calculation, dict):
        errors.append(f"{film_id}/{profile_id}: calculation must be an object")
        return

    if model == "table":
        validate_table_calculation(film_id, profile_id, calculation)
    elif model == "formula":
        validate_formula_calculation(film_id, profile_id, calculation)
    elif model == "limitedGuidance":
        validate_limited_guidance_calculation(film_id, profile_id, calculation)
    else:
        errors.append(f"{film_id}/{profile_id}: unsupported model {model!r}")

    validate_evidence_rows(film_id, profile_id, "evidence", profile.get("evidence"), EVIDENCE_KEYS)
    validate_evidence_rows(
        film_id,
        profile_id,
        "referencePoints",
        profile.get("referencePoints"),
        REFERENCE_POINT_KEYS,
    )
    validate_evidence_rows(
        film_id,
        profile_id,
        "referenceRanges",
        profile.get("referenceRanges"),
        REFERENCE_RANGE_KEYS,
    )


def validate_table_calculation(film_id: str, profile_id: str, calculation: dict) -> None:
    assert_allowed_keys(f"{film_id}/{profile_id}.calculation", calculation, TABLE_KEYS)
    anchors = calculation.get("anchors")
    if not isinstance(anchors, list) or not anchors:
        errors.append(f"{film_id}/{profile_id}: table anchors must be a non-empty array")
        return

    previous_metered: float | None = None
    seen_metered: set[float] = set()
    for index, anchor in enumerate(anchors):
        if not isinstance(anchor, dict):
            errors.append(f"{film_id}/{profile_id}: anchors[{index}] must be an object")
            continue
        metered = anchor.get("meteredSeconds")
        corrected = anchor.get("correctedSeconds")
        if not is_number(metered) or not is_number(corrected):
            errors.append(f"{film_id}/{profile_id}: anchors[{index}] must carry numeric seconds")
            continue
        if previous_metered is not None and metered <= previous_metered:
            errors.append(f"{film_id}/{profile_id}: anchors must be strictly ascending")
        previous_metered = metered
        if metered in seen_metered:
            errors.append(f"{film_id}/{profile_id}: duplicate anchor meteredSeconds {metered}")
        seen_metered.add(metered)
        if corrected < metered:
            errors.append(f"{film_id}/{profile_id}: anchor correctedSeconds {corrected} < meteredSeconds {metered}")


def validate_formula_calculation(film_id: str, profile_id: str, calculation: dict) -> None:
    assert_allowed_keys(f"{film_id}/{profile_id}.calculation", calculation, FORMULA_KEYS)
    exponent = calculation.get("exponent")
    coefficient = calculation.get("coefficient", 1)
    if not is_number(exponent) or exponent <= 0:
        errors.append(f"{film_id}/{profile_id}: formula exponent must be > 0")
    if not is_number(coefficient) or coefficient <= 0:
        errors.append(f"{film_id}/{profile_id}: formula coefficient must be > 0")


def validate_limited_guidance_calculation(film_id: str, profile_id: str, calculation: dict) -> None:
    assert_allowed_keys(f"{film_id}/{profile_id}.calculation", calculation, LIMITED_GUIDANCE_KEYS)
    no_correction_range = calculation.get("noCorrectionRange")
    if no_correction_range is not None:
        if (
            not isinstance(no_correction_range, list)
            or len(no_correction_range) != 2
            or not all(is_number(value) for value in no_correction_range)
        ):
            errors.append(f"{film_id}/{profile_id}: noCorrectionRange must be [min, max]")
        elif no_correction_range[0] >= no_correction_range[1]:
            errors.append(f"{film_id}/{profile_id}: noCorrectionRange min must be < max")

    guidance = calculation.get("guidance", [])
    if not isinstance(guidance, list):
        errors.append(f"{film_id}/{profile_id}: guidance must be an array")
        return

    previous_from: float | None = None
    for index, row in enumerate(guidance):
        if not isinstance(row, dict):
            errors.append(f"{film_id}/{profile_id}: guidance[{index}] must be an object")
            continue
        from_seconds = row.get("fromSeconds")
        if not is_number(from_seconds):
            errors.append(f"{film_id}/{profile_id}: guidance[{index}].fromSeconds must be numeric")
            continue
        if previous_from is not None and from_seconds < previous_from:
            errors.append(f"{film_id}/{profile_id}: guidance rows must be sorted by fromSeconds")
        previous_from = from_seconds
        color_filter = row.get("colorFilter")
        if color_filter is not None:
            validate_color_filter(f"{film_id}/{profile_id}: guidance[{index}].colorFilter", color_filter)


def validate_evidence_rows(
    film_id: str,
    profile_id: str,
    key: str,
    rows: object,
    allowed_keys: set[str],
) -> None:
    if rows is None:
        return
    if not isinstance(rows, list):
        errors.append(f"{film_id}/{profile_id}: {key} must be an array")
        return
    for index, row in enumerate(rows):
        label = f"{film_id}/{profile_id}: {key}[{index}]"
        if not isinstance(row, dict):
            errors.append(f"{label} must be an object")
            continue
        assert_allowed_keys(label, row, allowed_keys)
        warning = row.get("warning")
        if warning is not None:
            assert_allowed_keys(f"{label}.warning", warning, WARNING_KEYS)
        color_filter = row.get("colorFilter")
        if isinstance(color_filter, dict):
            validate_color_filter(f"{label}.colorFilter", color_filter)
        elif color_filter is not None and not isinstance(color_filter, str):
            errors.append(f"{label}.colorFilter must be a string or object")


def validate_color_filter(label: str, value: object) -> None:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return
    assert_allowed_keys(label, value, COLOR_FILTER_KEYS)
    if not isinstance(value.get("filterName"), str) or not value["filterName"]:
        errors.append(f"{label}.filterName must be a non-empty string")


def validate_expectations(catalog: dict, expectations: dict) -> None:
    films = catalog.get("films", [])
    expected_count = expectations.get("expectedFilmCount")
    expected_order = expectations.get("expectedFilmOrder")
    expected_ids = expectations.get("expectedFilmIds")

    if len(films) != expected_count:
        errors.append(f"expectedFilmCount {expected_count} != actual {len(films)}")
    if [film.get("canonicalStockName") for film in films] != expected_order:
        errors.append("expectedFilmOrder does not match bundled v2 catalog")
    if [film.get("id") for film in films] != expected_ids:
        errors.append("expectedFilmIds does not match bundled v2 catalog")


def assert_allowed_keys(label: str, value: object, allowed: set[str]) -> None:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return
    unknown = set(value) - allowed
    if unknown:
        errors.append(f"{label} contains unknown keys {sorted(unknown)}")


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


if __name__ == "__main__":
    sys.exit(main())

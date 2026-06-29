#!/usr/bin/env python3
"""PTIMER-186: v2-only launch catalog verifier.

Run from the repository root:
    python3 tools/catalog-v2/verify.py

Exit 0 on PASS, 1 on any mismatch.
"""

from __future__ import annotations

import json
import math
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
SUPPORTED_FORMULA_FAMILIES = {"modifiedSchwarzschild"}
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

# Carriers a profile may NOT have, by model (mirrors the platform loaders).
FORBIDDEN_CARRIERS = {
    "table": ("referencePoints", "referenceRanges"),
    "formula": ("evidence",),
    "limitedGuidance": ("evidence", "referencePoints", "referenceRanges"),
}


errors: list[str] = []


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()

    errors.clear()
    assert_copies_identical()
    catalog = load_json(V2_COPIES[0])
    expectations = load_json(EXPECTATIONS_PATH)["catalogExpectations"]

    validate_content(catalog)
    validate_expectations(catalog, expectations)

    if errors:
        print(f"FAIL: {len(errors)} errors")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(f"PASS: {len(catalog['films'])} v2 films verified.")
    return 0


def validate_content(catalog: dict) -> None:
    """Structural validation shared by the real run and the self-test:
    explicit-null rejection, schema, sources, and films (including
    model/carrier mismatch). Excludes copy-identity and the
    catalogExpectations cross-check, which only apply to the real run."""
    reject_nulls(catalog, "catalog")
    validate_schema(catalog)
    validate_sources(catalog)
    validate_films(catalog)


def reject_nulls(value: object, path: str) -> None:
    """Explicit JSON null is never valid anywhere in the catalog; optional
    fields must be omitted, not set to null."""
    if value is None:
        errors.append(f"explicit null at {path}")
    elif isinstance(value, dict):
        for key, item in value.items():
            reject_nulls(item, f"{path}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            reject_nulls(item, f"{path}[{index}]")


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

    for carrier in FORBIDDEN_CARRIERS.get(model, ()):
        if carrier in profile:
            errors.append(f"{film_id}/{profile_id}: {model} profile must not carry {carrier}")

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

    if model == "table" and isinstance(calculation.get("anchors"), list):
        validate_evidence_anchor_indices(
            film_id, profile_id, profile.get("evidence"), len(calculation["anchors"])
        )
    validate_reference_points(film_id, profile_id, profile.get("referencePoints"))
    validate_reference_ranges(film_id, profile_id, profile.get("referenceRanges"))


def validate_table_calculation(film_id: str, profile_id: str, calculation: dict) -> None:
    p = f"{film_id}/{profile_id}"
    assert_allowed_keys(f"{p}.calculation", calculation, TABLE_KEYS)
    anchors = calculation.get("anchors")
    if not isinstance(anchors, list) or not anchors:
        errors.append(f"{p}: table anchors must be a non-empty array")
        return

    previous_metered: float | None = None
    seen_metered: set[float] = set()
    anchors_ok = True
    for index, anchor in enumerate(anchors):
        if not isinstance(anchor, dict):
            errors.append(f"{p}: anchors[{index}] must be an object")
            anchors_ok = False
            continue
        metered = anchor.get("meteredSeconds")
        corrected = anchor.get("correctedSeconds")
        if not is_number(metered) or metered <= 0 or not is_number(corrected):
            errors.append(f"{p}: anchors[{index}] need finite meteredSeconds > 0 and finite correctedSeconds")
            anchors_ok = False
            continue
        if previous_metered is not None and metered <= previous_metered:
            errors.append(f"{p}: anchors must be strictly ascending by meteredSeconds")
        previous_metered = metered
        if metered in seen_metered:
            errors.append(f"{p}: duplicate anchor meteredSeconds {metered}")
        seen_metered.add(metered)
        if corrected < metered:
            errors.append(f"{p}: anchor correctedSeconds {corrected} < meteredSeconds {metered}")

    first_metered = anchors[0].get("meteredSeconds") if anchors_ok else None
    last_metered = anchors[-1].get("meteredSeconds") if anchors_ok else None
    no_corr = calculation.get("noCorrectionThroughSeconds")
    if no_corr is not None:
        if not is_number(no_corr) or no_corr < 0:
            errors.append(f"{p}: table noCorrectionThroughSeconds must be finite and >= 0")
        elif is_number(first_metered) and no_corr >= first_metered:
            errors.append(f"{p}: noCorrectionThroughSeconds must be < the first anchor meteredSeconds")
    source_range = calculation.get("sourceRangeThroughSeconds")
    if source_range is not None:
        if not is_number(source_range):
            errors.append(f"{p}: table sourceRangeThroughSeconds must be finite")
        else:
            if is_number(no_corr) and source_range <= no_corr:
                errors.append(f"{p}: sourceRangeThroughSeconds must be > noCorrectionThroughSeconds")
            if is_number(last_metered) and source_range < last_metered:
                errors.append(f"{p}: sourceRangeThroughSeconds must be >= the last anchor meteredSeconds")


def validate_formula_calculation(film_id: str, profile_id: str, calculation: dict) -> None:
    p = f"{film_id}/{profile_id}"
    assert_allowed_keys(f"{p}.calculation", calculation, FORMULA_KEYS)
    if calculation.get("family") not in SUPPORTED_FORMULA_FAMILIES:
        errors.append(f"{p}: unsupported formula family {calculation.get('family')!r}")
    if not is_number(calculation.get("exponent")) or calculation["exponent"] <= 0:
        errors.append(f"{p}: formula exponent must be finite and > 0")
    coefficient = calculation.get("coefficient", 1)
    if not is_number(coefficient) or coefficient <= 0:
        errors.append(f"{p}: formula coefficient must be finite and > 0")
    reference = calculation.get("referenceMeteredSeconds", 1)
    if not is_number(reference) or reference <= 0:
        errors.append(f"{p}: formula referenceMeteredSeconds must be finite and > 0")
    if "offsetSeconds" in calculation and not is_number(calculation["offsetSeconds"]):
        errors.append(f"{p}: formula offsetSeconds must be a finite number")
    no_corr = calculation.get("noCorrectionThroughSeconds")
    if no_corr is not None and (not is_number(no_corr) or no_corr < 0):
        errors.append(f"{p}: formula noCorrectionThroughSeconds must be finite and >= 0")
    source_range = calculation.get("sourceRangeThroughSeconds")
    if source_range is not None:
        if not is_number(source_range):
            errors.append(f"{p}: formula sourceRangeThroughSeconds must be finite")
        elif is_number(no_corr) and source_range <= no_corr:
            errors.append(f"{p}: sourceRangeThroughSeconds must be > noCorrectionThroughSeconds")


def validate_limited_guidance_calculation(film_id: str, profile_id: str, calculation: dict) -> None:
    p = f"{film_id}/{profile_id}"
    assert_allowed_keys(f"{p}.calculation", calculation, LIMITED_GUIDANCE_KEYS)
    no_correction_range = calculation.get("noCorrectionRange")
    range_max: float | None = None
    if no_correction_range is None:
        errors.append(f"{p}: limitedGuidance requires noCorrectionRange")
    elif (
        not isinstance(no_correction_range, list)
        or len(no_correction_range) != 2
        or not all(is_number(value) for value in no_correction_range)
    ):
        errors.append(f"{p}: noCorrectionRange must be exactly two finite numbers")
    elif no_correction_range[0] >= no_correction_range[1]:
        errors.append(f"{p}: noCorrectionRange min must be < max")
    else:
        range_max = no_correction_range[1]

    guidance = calculation.get("guidance", [])
    if not isinstance(guidance, list):
        errors.append(f"{p}: guidance must be an array")
        return

    previous_from: float | None = None
    for index, row in enumerate(guidance):
        if not isinstance(row, dict):
            errors.append(f"{p}: guidance[{index}] must be an object")
            continue
        from_seconds = row.get("fromSeconds")
        if not is_number(from_seconds):
            errors.append(f"{p}: guidance[{index}].fromSeconds must be a finite number")
            continue
        if range_max is not None and from_seconds < range_max:
            errors.append(f"{p}: guidance[{index}].fromSeconds must be >= noCorrectionRange max")
        if previous_from is not None and from_seconds < previous_from:
            errors.append(f"{p}: guidance rows must be sorted by fromSeconds")
        previous_from = from_seconds
        color_filter = row.get("colorFilter")
        if color_filter is not None:
            validate_color_filter(f"{p}: guidance[{index}].colorFilter", color_filter)


def validate_evidence_anchor_indices(film_id: str, profile_id: str, rows: object, anchor_count: int) -> None:
    if not isinstance(rows, list):
        return
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            continue
        anchor = row.get("anchor")
        if not isinstance(anchor, int) or isinstance(anchor, bool) or not 0 <= anchor < anchor_count:
            errors.append(f"{film_id}/{profile_id}: evidence[{index}].anchor must be an index in 0..{anchor_count - 1}")


def validate_reference_points(film_id: str, profile_id: str, rows: object) -> None:
    if not isinstance(rows, list):
        return
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            continue
        label = f"{film_id}/{profile_id}: referencePoints[{index}]"
        metered = row.get("meteredSeconds")
        if not is_number(metered) or metered <= 0:
            errors.append(f"{label}.meteredSeconds must be finite and > 0")
        if "correctedSeconds" in row:
            corrected = row["correctedSeconds"]
            if not is_number(corrected) or (is_number(metered) and corrected < metered):
                errors.append(f"{label}.correctedSeconds must be finite and >= meteredSeconds")


def validate_reference_ranges(film_id: str, profile_id: str, rows: object) -> None:
    if not isinstance(rows, list):
        return
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            continue
        label = f"{film_id}/{profile_id}: referenceRanges[{index}]"
        from_seconds = row.get("fromSeconds")
        through_seconds = row.get("throughSeconds")
        if not is_number(from_seconds) or not is_number(through_seconds):
            errors.append(f"{label} must carry finite fromSeconds and throughSeconds")
        elif from_seconds >= through_seconds:
            errors.append(f"{label}.fromSeconds must be < throughSeconds")


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
    """A finite JSON number (not bool, not NaN/Infinity)."""
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


def self_test() -> int:
    """Prove the verifier rejects each invalid schema class, by mutating the
    real catalog (otherwise valid) one fault at a time. Network-free."""
    import copy as _copy

    base = load_json(V2_COPIES[0])

    def find_model(model: str) -> str:
        for film in base["films"]:
            for profile in film["profiles"]:
                if profile.get("model") == model:
                    return film["id"]
        raise AssertionError(f"no {model} profile in bundled catalog")

    table_fid = find_model("table")
    formula_fid = find_model("formula")
    lg_fid = find_model("limitedGuidance")
    first_source = next(iter(base["sources"]))

    def prof(cat: dict, fid: str) -> dict:
        for film in cat["films"]:
            if film["id"] == fid:
                return film["profiles"][0]
        raise AssertionError(f"film {fid} missing")

    def set_field(cat: dict, fid: str, field: str, value: object) -> None:
        prof(cat, fid)[field] = value

    def set_calc(cat: dict, fid: str, field: str, value: object) -> None:
        prof(cat, fid)["calculation"][field] = value

    points = [{"meteredSeconds": 1, "correctedSeconds": 2}]
    ranges = [{"fromSeconds": 1, "throughSeconds": 2}]

    def table_nocorr_too_high(c: dict) -> None:
        calc = prof(c, table_fid)["calculation"]
        calc["noCorrectionThroughSeconds"] = calc["anchors"][0]["meteredSeconds"]

    def table_source_range_too_low(c: dict) -> None:
        calc = prof(c, table_fid)["calculation"]
        calc["sourceRangeThroughSeconds"] = calc["anchors"][-1]["meteredSeconds"] - 1

    def formula_source_le_nocorr(c: dict) -> None:
        calc = prof(c, formula_fid)["calculation"]
        calc["noCorrectionThroughSeconds"] = 1
        calc["sourceRangeThroughSeconds"] = 1

    def lg_guidance_below_max(c: dict) -> None:
        calc = prof(c, lg_fid)["calculation"]
        calc["guidance"] = [{"fromSeconds": calc["noCorrectionRange"][1] - 1, "message": "x"}]

    def lg_guidance_unsorted(c: dict) -> None:
        calc = prof(c, lg_fid)["calculation"]
        top = calc["noCorrectionRange"][1]
        calc["guidance"] = [
            {"fromSeconds": top + 10, "message": "a"},
            {"fromSeconds": top + 1, "message": "b"},
        ]

    cases: list[tuple[str, callable]] = [
        # carrier / null classes
        ("source links:null", lambda c: c["sources"][first_source].update(links=None)),
        ("source link downloadUrl:null", lambda c: c["sources"][first_source].update(links={"downloadUrl": None})),
        ("formula + evidence", lambda c: set_field(c, formula_fid, "evidence", [{"anchor": 0}])),
        ("table + referencePoints", lambda c: set_field(c, table_fid, "referencePoints", points)),
        ("table + referenceRanges", lambda c: set_field(c, table_fid, "referenceRanges", ranges)),
        ("limitedGuidance + evidence", lambda c: set_field(c, lg_fid, "evidence", [{"anchor": 0}])),
        ("limitedGuidance + referencePoints", lambda c: set_field(c, lg_fid, "referencePoints", points)),
        ("limitedGuidance + referenceRanges", lambda c: set_field(c, lg_fid, "referenceRanges", ranges)),
        # table numeric/range classes
        ("table noCorrection >= first anchor", table_nocorr_too_high),
        ("table sourceRange < last anchor", table_source_range_too_low),
        ("table evidence anchor out of range", lambda c: set_field(c, table_fid, "evidence", [{"anchor": 999}])),
        # formula numeric/range classes
        ("formula referenceMeteredSeconds <= 0", lambda c: set_calc(c, formula_fid, "referenceMeteredSeconds", 0)),
        ("formula offsetSeconds invalid type", lambda c: set_calc(c, formula_fid, "offsetSeconds", "x")),
        ("formula sourceRange <= noCorrection", formula_source_le_nocorr),
        ("formula referencePoints missing meteredSeconds",
         lambda c: set_field(c, formula_fid, "referencePoints", [{"correctedSeconds": 2}])),
        ("formula referencePoints corrected < metered",
         lambda c: set_field(c, formula_fid, "referencePoints", [{"meteredSeconds": 10, "correctedSeconds": 5}])),
        ("formula referenceRanges from >= through",
         lambda c: set_field(c, formula_fid, "referenceRanges", [{"fromSeconds": 2, "throughSeconds": 1}])),
        # limitedGuidance numeric/range classes
        ("limitedGuidance noCorrectionRange min >= max", lambda c: set_calc(c, lg_fid, "noCorrectionRange", [2, 1])),
        ("limitedGuidance guidance.fromSeconds < range max", lg_guidance_below_max),
        ("limitedGuidance guidance unsorted", lg_guidance_unsorted),
    ]

    ok = True
    errors.clear()
    validate_content(_copy.deepcopy(base))
    if errors:
        print(f"  baseline catalog unexpectedly failed: {errors[:3]}")
        ok = False
    for name, mutate in cases:
        catalog = _copy.deepcopy(base)
        mutate(catalog)
        errors.clear()
        validate_content(catalog)
        if errors:
            print(f"  rejected (good): {name}")
        else:
            print(f"  ACCEPTED (BAD): {name}")
            ok = False

    print("SELF-TEST PASS" if ok else "SELF-TEST FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

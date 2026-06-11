# PTIMER-170 App-Derived Formula Evaluation

## Purpose

Evaluate app-derived formula candidates for the PTIMER-168 migrated
table-origin profiles and ship alternates only where the fit is
useful and safe. Table calculation remains the default for every
migrated profile; an app-derived formula is always a non-default,
clearly labelled alternate.

The executable record is
`ios/PTimerKit/Tests/PTimerKitTests/Reciprocity/AppDerivedFormulaEvaluationTests.swift`,
which recomputes each fit from the live catalog anchors and locks the
constants, residuals, and decisions below. This document is the
human-readable summary; if the two ever disagree, the tests win.

## Method and decision policy

Fit: free least-squares log-log fit `Tc = a × Tm^p`
(modified Schwarzschild, the only shipped formula family), the same
method behind the retired pre-PTIMER-168 catalog formulas and the
shipped Fomapan 100 app-derived alternate.

Decision thresholds on the worst absolute anchor residual:

- `≤ 0.1 stop` — eligible to ship as an app-derived alternate
- `> 0.1 and ≤ 0.25 stop` — borderline; document only
- `> 0.25 stop` — poor/unsafe fit; document only

## Decisions

| Film | Fitted formula | Worst stop error | Decision |
|---|---|---|---|
| CHS 100 II | Tc = 1.2102 × Tm^1.3423 | 0.040 | **Added** as alternate |
| T-MAX 100 | Tc = 1.2364 × Tm^1.1003 | 0.054 | **Added** as alternate |
| Fomapan 200 Creative | Tc = 3.2097 × Tm^1.3891 | 0.195 | Documented only (borderline) |
| T-MAX 400 | Tc = 1.1556 × Tm^1.1884 | 0.249 | Documented only (borderline) |
| RPX 100 | Tc = 0.9243 × Tm^1.4650 | 0.288 | Documented only (poor fit) |
| RPX 400 | Tc = 1.7708 × Tm^1.2406 | 0.383 | Documented only (poor fit) |
| Fomapan 400 Action | Tc = 1.8014 × Tm^1.3635 | 0.528 | Documented only (poor fit) |

Reasons for the document-only group: a single power law cannot follow
the published curvature of these tables — the mid-table anchors miss
by up to half a stop (Fomapan 400's 10 s row: fitted 41.6 s vs
published 60 s). Shipping such a formula would present a materially
wrong exposure as an app-blessed option.

Not re-evaluated: Tri-X 400 and Fomapan 100 Classic already ship
app-derived alternates (PTIMER-168 / PTIMER-164). Out of scope per
PTIMER-167/169: the special / range / limited-guidance profiles
(Acros II, Velvia 50/100, Provia 100F, RETRO 80S, SUPERPAN 200,
CMS 20 II, Kodak limited-guidance color films) and community sources.

## Shipped alternates

Both follow the Tri-X 400 pattern in `AlternateReciprocityModels`:
non-default, named "App formula", `modelBasis` =
`manufacturerTable + guardedFormula`, enrolled in
`isAppDerivedModel`, published rows carried as source evidence so the
Details "App-derived comparison" section renders per-anchor percent
and stop deltas, and the formula keeps the table's no-correction band
and published source range:

- `kodak-tmax-100-app-formula` — no correction through 1/10 s,
  source range through 100 s
- `adox-chs-100-ii-app-formula` — no correction through 1 s,
  source range through 15 s

## Retired PTIMER-168 constants

Per the PTIMER-167 storage decision, the fitted constants PTIMER-168
removed from the catalog are preserved in the evaluation fixture as
executable data. Five (Fomapan 200/400, RPX 100/400, CHS 100 II)
reproduce from the current anchors via the free fit (asserted in
tests). The two T-MAX fits used different anchoring schemes —
T-MAX 100 `0.1 × (Tm/0.1)^1.0966`, T-MAX 400 `Tm^1.2261` (1 s
threshold) — so the fixture rebuilds those retired formulas from
their recorded constants and pins their outputs at the published
anchor inputs instead.

## Follow-up

- Borderline fits (Fomapan 200, T-MAX 400) can be revisited if a
  second formula family (e.g. an offset term fitted per film) lands;
  re-run the evaluation fixture against the new family first.

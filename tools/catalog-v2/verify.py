#!/usr/bin/env python3
"""PTIMER-186: independent v1<->v2 equivalence verifier.
Parses v1 and v2 separately (no shared extraction with convert.py) and compares
the full evidence grammar as a multiset. Run from repo root:
    python3 tools/catalog-v2/verify.py
Exit 0 on PASS, 1 on any mismatch.
"""
import json, sys
errors = []

# The v2 catalog is bundled as three byte-identical copies (canonical +
# per-platform resources). They are written together by convert.py; assert they
# stay in lockstep so a manual edit to one copy cannot drift unnoticed.
V2_COPIES = [
    'shared/catalog/LaunchPresetFilmCatalog.v2.json',
    'ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.v2.json',
    'android/core/src/main/resources/LaunchPresetFilmCatalog.v2.json',
]
_canonical_bytes = open(V2_COPIES[0], 'rb').read()
for _copy in V2_COPIES[1:]:
    if open(_copy, 'rb').read() != _canonical_bytes:
        errors.append(f"v2 copy not byte-identical to canonical: {_copy}")

v1 = json.load(open('ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.json'))
v2 = json.load(open(V2_COPIES[0]))
src = v2['sources']
f1 = {f['id']: f for f in v1['films']}; f2 = {f['id']: f for f in v2['films']}
def fn(x): return round(x, 9) if isinstance(x, (int, float)) else x

def facts_v1(p):
    out = []
    for row in p.get('sourceEvidence', []):
        me = row['meteredExposure']
        metered = ('range', fn(me['range']['minimumSeconds']), fn(me['range']['maximumSeconds'])) if me.get('kind') == 'range' else ('pt', fn(me.get('exactSeconds')))
        corrected = stop = mult = dev = cf = warn = note = None; approx = False
        evonly = bool(row.get('isSourceEvidenceOnly'))
        for adj in row.get('adjustments', []):
            k = adj.get('kind')
            if k == 'exposure':
                exp = adj['exposure']; ek = exp.get('kind')
                if ek == 'correctedTime':
                    corrected = fn(exp['correctedTime'].get('correctedSeconds'))
                    if exp['correctedTime'].get('isApproximate'): approx = True
                elif ek == 'stopDelta': stop = fn(exp['stopDelta']['stopDelta'])
                elif ek == 'multiplier': mult = fn(exp['multiplier']['factor'])
            elif k == 'development': dev = adj['development']['instruction']
            elif k == 'colorFilter': cf = adj['colorFilter']['filterName']
            elif k == 'warning': warn = (adj['warning'].get('severity'), adj['warning'].get('message'))
            elif k == 'note': note = adj['note']['text']
        row_notes = tuple(n for n in row.get('notes', []) if n)
        out.append((metered, corrected, stop, mult, dev, cf, warn, note, approx, evonly, row_notes))
    return sorted(out, key=str)

def facts_v2(p, anchors):
    out = []
    def pack(metered, corrected, d):
        return (metered, corrected if corrected is not None else (fn(d['correctedSeconds']) if 'correctedSeconds' in d else None),
                fn(d.get('stopDelta')), fn(d.get('multiplier')), d.get('development'), d.get('colorFilter'),
                (d['warning'].get('severity'), d['warning'].get('message')) if d.get('warning') else None,
                d.get('note'), bool(d.get('approx')), bool(d.get('evidenceOnly')),
                tuple(d.get('rowNotes', [])))
    for e in p.get('evidence', []):
        a = anchors[e['anchor']]
        out.append(pack(('pt', fn(a['meteredSeconds'])), fn(a['correctedSeconds']), e))
    for rp in p.get('referencePoints', []):
        out.append(pack(('pt', fn(rp.get('meteredSeconds'))), None, rp))
    for rr in p.get('referenceRanges', []):
        out.append(pack(('range', fn(rr['fromSeconds']), fn(rr['throughSeconds'])), None, rr))
    return sorted(out, key=str)

if [f['id'] for f in v1['films']] != [f['id'] for f in v2['films']]:
    errors.append("film order/set differs")
for fid, fa in f1.items():
    fb = f2.get(fid)
    if fb is None: errors.append(f"{fid} missing in v2"); continue
    for k in ['canonicalStockName', 'manufacturer', 'brandLabel', 'iso', 'kind', 'productionStatus']:
        if fa[k] != fb[k]: errors.append(f"{fid}.{k}")
    if fa.get('aliases', []) != fb.get('aliases', []): errors.append(f"{fid}.aliases")
    pa = fa['profiles'][0]; pb = fb['profiles'][0]; rk = [r['kind'] for r in pa['rules']]
    s1 = pa['source']; s2 = src[pb['sourceId']]
    for a, b in [('kind', 'sourceType'), ('authority', 'authority'), ('confidence', 'confidence'), ('publisher', 'publisher'), ('title', 'title'), ('citation', 'citation')]:
        if s1.get(a) != s2.get(b): errors.append(f"{fid} source.{a}")
    if (pa.get('modelBasis') or {}).get('sourceModel') != pb.get('basis'): errors.append(f"{fid} basis")
    if pa['source']['authority'] != pb['authority']: errors.append(f"{fid} authority")
    calc = pb.get('calculation', {})
    if 'tableInterpolation' in rk:
        tr = next(r['tableInterpolation'] for r in pa['rules'] if r['kind'] == 'tableInterpolation')
        a1 = [(fn(a['meteredSeconds']), fn(a['correctedSeconds'])) for a in tr['anchors']]
        a2 = [(fn(a['meteredSeconds']), fn(a['correctedSeconds'])) for a in calc.get('anchors', [])]
        if a1 != a2: errors.append(f"{fid} anchors")
        if fn(tr['noCorrectionThroughSeconds']) != fn(calc.get('noCorrectionThroughSeconds')): errors.append(f"{fid} table noCorr")
    elif 'formula' in rk and 'limitedGuidance' not in rk:
        f = next(r['formula'] for r in pa['rules'] if r['kind'] == 'formula')['formula']
        if f['formulaFamily'] != calc.get('family'): errors.append(f"{fid} family")
        if fn(f['exponent']) != fn(calc.get('exponent')): errors.append(f"{fid} exponent")
        if fn(f.get('coefficientSeconds', 1)) != fn(calc.get('coefficient', 1)): errors.append(f"{fid} coefficient")
        if fn(f.get('referenceMeteredTimeSeconds', 1)) != fn(calc.get('referenceMeteredSeconds', 1)): errors.append(f"{fid} reference")
        if fn(f.get('offsetSeconds', 0)) != fn(calc.get('offsetSeconds', 0)): errors.append(f"{fid} offset")
        if fn(f['noCorrectionThroughSeconds']) != fn(calc.get('noCorrectionThroughSeconds')): errors.append(f"{fid} formula noCorr")
        if fn(f.get('sourceRangeThroughSeconds')) != fn(calc.get('sourceRangeThroughSeconds')): errors.append(f"{fid} formula srcRange")
    elif 'limitedGuidance' in rk:
        thr = next((r['threshold'] for r in pa['rules'] if r['kind'] == 'threshold'), None)
        if thr:
            nr = thr['noCorrectionRange']
            if [fn(nr['minimumSeconds']), fn(nr['maximumSeconds'])] != [fn(x) for x in calc.get('noCorrectionRange', [])]: errors.append(f"{fid} noCorrRange")
        lg = next(r['limitedGuidance'] for r in pa['rules'] if r['kind'] == 'limitedGuidance')
        m1 = [adj['note']['text'] for adj in lg.get('adjustments', []) if adj.get('kind') == 'note']
        m2 = [g['message'] for g in calc.get('guidance', []) if 'message' in g]
        if m1 != m2: errors.append(f"{fid} guidance")
        cf1 = [(a['colorFilter']['filterName'], a['colorFilter'].get('note')) for a in lg.get('adjustments', []) if a.get('kind') == 'colorFilter']
        cf2 = [(g['colorFilter']['filterName'], g['colorFilter'].get('note')) for g in calc.get('guidance', []) if g.get('colorFilter')]
        if cf1 != cf2: errors.append(f"{fid} guidance colorFilter")
    if facts_v1(pa) != facts_v2(pb, calc.get('anchors', [])):
        errors.append(f"{fid} EVIDENCE MISMATCH")
    v1_profile_notes = [n for n in pa.get('notes', []) if n]
    if v1_profile_notes != pb.get('notes', []):
        errors.append(f"{fid} PROFILE NOTES MISMATCH (v1 {v1_profile_notes} vs v2 {pb.get('notes', [])})")
    v1_model_notes = []
    for r in pa['rules']:
        v1_model_notes += [n for n in r.get(r['kind'], {}).get('notes', []) if n]
    if v1_model_notes != pb.get('calculation', {}).get('notes', []):
        errors.append(f"{fid} MODEL NOTES MISMATCH (v1 {len(v1_model_notes)} vs v2 {len(pb.get('calculation', {}).get('notes', []))})")

if errors:
    print("FAIL:", len(errors), "errors")
    for e in errors[:60]: print("  -", e)
    sys.exit(1)
print(f"PASS: {len(f1)} films, full v1<->v2 equivalence (identity, source, basis, model, anchors,")
print("      formula params, limited guidance, and full evidence grammar).")

#!/usr/bin/env python3
"""PTIMER-186: convert v1 launch catalog -> Catalog Runtime Schema v2.

Deterministic, lossless conversion. Run from repo root:
    python3 tools/catalog-v2/convert.py
Writes shared/catalog/LaunchPresetFilmCatalog.v2.json and mirrors it to the
iOS and Android bundled-resource paths.
"""
import json, re, sys, os

ROOT = os.getcwd()
V1 = 'ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.json'

# Curated, human-managed stable source ids (PTIMER-186 condition 1).
# Keyed by source title (unique across the deduped source set).
SOURCE_IDS = {
    "Reciprocity characteristics": "ilford-reciprocity",
    "KODAK PROFESSIONAL TRI-X 400 Film — Technical Data": "kodak-tri-x-f4017",
    "KODAK PROFESSIONAL T-MAX 100 Film — Technical Data": "kodak-tmax-100-f4016",
    "KODAK PROFESSIONAL T-MAX 400 Film — Technical Data": "kodak-tmax-400-f4043",
    "KODAK PROFESSIONAL Ektar 100 Film — Technical Data": "kodak-ektar-100-e4046",
    "KODAK PROFESSIONAL Portra 160 Film — Technical Data": "kodak-portra-160-e4051",
    "KODAK PROFESSIONAL Portra 400 Film — Technical Data": "kodak-portra-400-e4050",
    "KODAK PROFESSIONAL Gold 200 Film — Technical Data": "kodak-gold-200-e7022",
    "KODAK PROFESSIONAL Ultra Max 400 Film — Technical Data": "kodak-ultramax-400-e7023",
    "KODAK PROFESSIONAL EKTACHROME E100 Film — Technical Data": "kodak-ektachrome-e100-e4000",
    "NEOPAN 100 ACROS II — Reciprocity guidance": "fuji-acros-ii",
    "FUJICHROME Velvia 50 — Long exposure guide": "fuji-velvia-50",
    "FUJICHROME Velvia 100 — Long exposure guide": "fuji-velvia-100",
    "FUJICHROME PROVIA 100F — Long exposure guide": "fuji-provia-100f",
    "FOMAPAN 100 CLASSIC — Technical sheet": "foma-fomapan-100",
    "FOMAPAN 200 CREATIVE — Technical sheet": "foma-fomapan-200",
    "FOMAPAN 400 ACTION — Technical sheet": "foma-fomapan-400",
    "Rollei RPX 25 — Data sheet": "rollei-rpx-25-sheet",
    "Rollei RPX 100 — Data sheet": "rollei-rpx-100-sheet",
    "Rollei RPX 400 — Data sheet": "rollei-rpx-400-sheet",
    "Rollei ORTHO 25 plus — Data sheet": "rollei-ortho-25-plus-sheet",
    "Rollei RETRO 80S — Data sheet": "rollei-retro-80s-sheet",
    "Rollei Retro 400S": "lafitte-retro-400s",
    "Rollei SUPERPAN 200 — Data sheet": "rollei-superpan-200-sheet",
    "ADOX CHS 100 II S/W Film — Technische Beschreibung, 11. Juli 2024": "adox-chs-100-ii",
    "ADOX CMS 20 II — Technical information": "adox-cms-20-ii",
}

def main():
    v1 = json.load(open(V1))
    reg = {}      # skey -> sourceId
    sources = {}  # sourceId -> entry

    def skey(s):
        return (s.get('kind'), s.get('authority'), s.get('confidence'), s.get('publisher'),
                s.get('title'), s.get('citation'), s.get('sourceVersion'))

    def source_id(s):
        k = skey(s)
        if k in reg:
            return reg[k]
        title = s.get('title')
        sid = SOURCE_IDS.get(title)
        if sid is None:
            sys.exit(f"ERROR: no curated source id for title {title!r}; add it to SOURCE_IDS")
        if sid in sources:
            sys.exit(f"ERROR: curated source id {sid!r} maps to two distinct sources")
        reg[k] = sid
        e = {"publisher": s.get('publisher'), "title": s.get('title'), "citation": s.get('citation'),
             "sourceType": s.get('kind'), "authority": s.get('authority'), "confidence": s.get('confidence')}
        if s.get('sourceVersion'):
            e["version"] = s["sourceVersion"]
        # `links` (landingPageUrl/downloadUrl/archiveUrl/accessedDate) is optional
        # provenance metadata. We do not fabricate URLs or bundle PDFs, so it is
        # omitted here; the schema/decoder treats it as optional.
        sources[sid] = {kk: vv for kk, vv in e.items() if vv is not None}
        return sid

    def payload(row):
        out = {}; corrected = None; approx = False
        if row.get('isSourceEvidenceOnly'):
            out['evidenceOnly'] = True
        for adj in row.get('adjustments', []):
            k = adj.get('kind')
            if k == 'exposure':
                exp = adj['exposure']; ek = exp.get('kind')
                if ek == 'correctedTime':
                    ct = exp['correctedTime']; corrected = ct.get('correctedSeconds')
                    if ct.get('isApproximate'):
                        approx = True
                elif ek == 'stopDelta':
                    out['stopDelta'] = exp['stopDelta']['stopDelta']
                elif ek == 'multiplier':
                    out['multiplier'] = exp['multiplier']['factor']
            elif k == 'development':
                out['development'] = adj['development']['instruction']
            elif k == 'colorFilter':
                out['colorFilter'] = adj['colorFilter']['filterName']
            elif k == 'warning':
                w = adj['warning']; out['warning'] = {"severity": w.get('severity'), "message": w.get('message')}
            elif k == 'note':
                out['note'] = adj['note']['text']
        if approx:
            out['approx'] = True
        # Row-level evidence notes (ReciprocitySourceEvidenceRow.notes) are
        # distinct from the `.note` adjustment above; 76/79 rows carry them
        # (e.g. "1 sec -> +1 stop, corrected 2 sec, develop -10%."). Preserve
        # them verbatim so decoded sourceEvidence round-trips exactly.
        row_notes = [n for n in row.get('notes', []) if n]
        if row_notes:
            out['rowNotes'] = row_notes
        return corrected, out

    def formula_calc(f):
        c = {"family": f['formulaFamily']}
        if abs(f.get('coefficientSeconds', 1) - 1) > 1e-12:
            c['coefficient'] = f['coefficientSeconds']
        if abs(f.get('referenceMeteredTimeSeconds', 1) - 1) > 1e-12:
            c['referenceMeteredSeconds'] = f['referenceMeteredTimeSeconds']
        c['exponent'] = f['exponent']
        if abs(f.get('offsetSeconds', 0)) > 1e-12:
            c['offsetSeconds'] = f['offsetSeconds']
        c['noCorrectionThroughSeconds'] = f['noCorrectionThroughSeconds']
        if f.get('sourceRangeThroughSeconds') is not None:
            c['sourceRangeThroughSeconds'] = f['sourceRangeThroughSeconds']
        return c

    def convert_profile(p):
        rk = [r['kind'] for r in p['rules']]
        out = {"id": p['id'], "label": p['name'], "role": "primary", "authority": p['source']['authority']}
        b = (p.get('modelBasis') or {}).get('sourceModel')
        if b:
            out['basis'] = b
        out['sourceId'] = source_id(p['source'])
        if p.get('selectorLabel'):
            out['selectorLabel'] = p['selectorLabel']
        evidence = []; refpoints = []; refranges = []

        if 'tableInterpolation' in rk:
            tr = next(r['tableInterpolation'] for r in p['rules'] if r['kind'] == 'tableInterpolation')
            out['model'] = 'table'
            calc = {"interpolation": "logLog", "noCorrectionThroughSeconds": tr['noCorrectionThroughSeconds']}
            if tr.get('sourceRangeThroughSeconds') is not None:
                calc['sourceRangeThroughSeconds'] = tr['sourceRangeThroughSeconds']
            calc['anchors'] = [{"meteredSeconds": a['meteredSeconds'], "correctedSeconds": a['correctedSeconds']} for a in tr['anchors']]
            out['calculation'] = calc
            aidx = {(round(a['meteredSeconds'], 9), round(a['correctedSeconds'], 9)): i for i, a in enumerate(tr['anchors'])}
            for row in p.get('sourceEvidence', []):
                me = row['meteredExposure']; corrected, pl = payload(row)
                if me.get('kind') == 'range':
                    r = me['range']; rr = {"fromSeconds": r['minimumSeconds'], "throughSeconds": r['maximumSeconds']}; rr.update(pl); refranges.append(rr)
                else:
                    m = me['exactSeconds']; key = (round(m, 9), round(corrected, 9)) if (m is not None and corrected is not None) else None
                    if key in aidx:
                        ev = {"anchor": aidx[key]}; ev.update(pl); evidence.append(ev)
                    else:
                        rp = {"meteredSeconds": m}
                        if corrected is not None: rp["correctedSeconds"] = corrected
                        rp.update(pl); refpoints.append(rp)
        elif 'formula' in rk and 'limitedGuidance' not in rk:
            f = next(r['formula'] for r in p['rules'] if r['kind'] == 'formula')['formula']
            out['model'] = 'formula'; out['calculation'] = formula_calc(f)
            for row in p.get('sourceEvidence', []):
                me = row['meteredExposure']; corrected, pl = payload(row)
                if me.get('kind') == 'range':
                    r = me['range']; rr = {"fromSeconds": r['minimumSeconds'], "throughSeconds": r['maximumSeconds']}; rr.update(pl); refranges.append(rr)
                else:
                    m = me['exactSeconds']; rp = {"meteredSeconds": m}
                    if corrected is not None: rp["correctedSeconds"] = corrected
                    rp.update(pl); refpoints.append(rp)
        elif 'limitedGuidance' in rk:
            out['model'] = 'limitedGuidance'
            thr = next((r['threshold'] for r in p['rules'] if r['kind'] == 'threshold'), None)
            lg = next(r['limitedGuidance'] for r in p['rules'] if r['kind'] == 'limitedGuidance')
            calc = {}
            if thr:
                nr = thr['noCorrectionRange']; calc['noCorrectionRange'] = [nr['minimumSeconds'], nr['maximumSeconds']]
            # The limited-guidance rule carries a note message and, for
            # Ektachrome E100, a colorFilter (CC10R) adjustment. Preserve both;
            # the adapter rebuilds adjustments as [colorFilter?, note] to match
            # the v1 order. Launch data has exactly one note per rule.
            frm = lg.get('appliesWhenMetered', {}).get('minimumSeconds')
            cf = None; msg = None
            for adj in lg.get('adjustments', []):
                if adj.get('kind') == 'colorFilter':
                    c = adj['colorFilter']; cf = {"filterName": c['filterName']}
                    if c.get('note'): cf['note'] = c['note']
                elif adj.get('kind') == 'note':
                    msg = adj['note']['text']
            g = []
            if msg is not None or cf is not None:
                gi = {}
                if frm is not None: gi['fromSeconds'] = frm
                if cf: gi['colorFilter'] = cf
                if msg is not None: gi['message'] = msg
                g.append(gi)
            if g: calc['guidance'] = g
            out['calculation'] = calc
        else:
            sys.exit(f"ERROR: unmapped rule kinds {rk} for {p['id']}")

        if evidence: out['evidence'] = evidence
        if refpoints: out['referencePoints'] = refpoints
        if refranges: out['referenceRanges'] = refranges
        # Keep profile-level notes and the model rule's notes SEPARATE: the
        # Details/film-mode UI renders profile.notes, so merging the rule
        # (model-description) notes into it would change the display. Profile
        # notes -> `notes`; the single calc rule's notes -> `calculation.notes`
        # (for limitedGuidance the notes live on the threshold rule; the
        # guidance rule carries none in the launch data). No profile has more
        # than one rule with notes, so this round-trips exactly.
        profile_notes = [n for n in p.get('notes', []) if n]
        if profile_notes:
            out['notes'] = profile_notes
        model_notes = []
        for r in p['rules']:
            model_notes += [n for n in r.get(r['kind'], {}).get('notes', []) if n]
        if model_notes:
            out['calculation']['notes'] = model_notes
        return out

    films = []
    for fv in v1['films']:
        films.append({"id": fv['id'], "canonicalStockName": fv['canonicalStockName'],
            "manufacturer": fv['manufacturer'], "brandLabel": fv['brandLabel'], "aliases": fv.get('aliases', []),
            "iso": fv['iso'], "kind": fv['kind'], "productionStatus": fv['productionStatus'],
            "profiles": [convert_profile(p) for p in fv['profiles']]})

    v2 = {"schema": "ptimer.catalog.v2", "schemaVersion": 2, "catalogVersion": "2026.06",
          "license": v1['_meta']['license'], "copyright": v1['_meta']['copyright'],
          "sources": sources, "films": films}

    s = json.dumps(v2, indent=2, ensure_ascii=False)
    s = re.sub(r'\{\s*\n\s*"meteredSeconds": (-?\d+(?:\.\d+)?),\s*\n\s*"correctedSeconds": (-?\d+(?:\.\d+)?)\s*\n\s*\}',
               r'{ "meteredSeconds": \1, "correctedSeconds": \2 }', s) + '\n'

    targets = [
        'shared/catalog/LaunchPresetFilmCatalog.v2.json',
        'ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.v2.json',
        'android/core/src/main/resources/LaunchPresetFilmCatalog.v2.json',
    ]
    for t in targets:
        os.makedirs(os.path.dirname(t), exist_ok=True)
        open(t, 'w').write(s)
    print("films", len(films), "sources", len(sources))
    print("wrote:\n  " + "\n  ".join(targets))

if __name__ == '__main__':
    main()

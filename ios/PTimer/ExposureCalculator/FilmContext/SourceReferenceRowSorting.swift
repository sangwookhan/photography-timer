import Foundation

/// Semantic type of a row rendered in the Film Details Source
/// reference / Guidance boundary blocks.
///
/// Used as the secondary sort key so the same metered-exposure
/// value can carry both a published point anchor and a band
/// without the ordering depending on label text or column count.
/// (`pointAnchor` before `range` is the recommended priority; see
/// `SourceReferenceRowSortKey`.)
enum SourceReferenceRowKind: Int, Comparable {
    /// A single published exposure anchor (`exactSeconds` metered
    /// exposure). Example: ADOX CMS 20 II's 1 s +1/2 stop row,
    /// FOMA's published multiplier rows at 1 / 10 / 100 s, Provia's
    /// 240 s reference.
    case pointAnchor

    /// A row that covers a *range* of metered-exposure values rather
    /// than a single point. Examples: the threshold rule's
    /// no-correction band (`1/1000s … 1s   No correction range`),
    /// or a range-valued published evidence row (Rollei RETRO 80S
    /// / SUPERPAN 200 — `1s … 2s` with a published note).
    case range

    /// A manufacturer not-recommended / stop-signal row. These rows
    /// render in the dedicated Guidance boundary section rather
    /// than the Source reference block, but the enum carries the
    /// case so call sites can reason uniformly about row priority.
    case boundary

    /// A free-text note row that does not name a specific metered
    /// exposure value beyond its `sortValue`. Reserved for future
    /// use; not currently emitted by the launch catalog presenters.
    case note

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Stable sort key for the Film Details Source reference / Guidance
/// boundary blocks.
///
/// Ordering rule (PTIMER-139 follow-up):
///
/// 1. Lowest `sortValue` first (metered-exposure start, ascending).
///    For an `exactSeconds` row this is the published value itself;
///    for a range row it is `range.minimumSeconds`.
/// 2. At a tie on `sortValue`, the row with the lower `kind` rawValue
///    wins — `pointAnchor` before `range`, `range` before `boundary`,
///    `boundary` before `note`. This expresses "the single point
///    anchor sits above the band that wraps it" without relying on
///    label text or column count.
/// 3. Any remaining ties preserve catalog declaration order via
///    `catalogOffset`. Stable sort.
///
/// This struct is deliberately presentation-only — calculation and
/// graph rendering do not depend on row order.
struct SourceReferenceRowSortKey: Comparable {
    let sortValue: Double
    let kind: SourceReferenceRowKind
    let catalogOffset: Int

    init(sortValue: Double, kind: SourceReferenceRowKind, catalogOffset: Int) {
        self.sortValue = sortValue
        self.kind = kind
        self.catalogOffset = catalogOffset
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.sortValue != rhs.sortValue {
            return lhs.sortValue < rhs.sortValue
        }
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return lhs.catalogOffset < rhs.catalogOffset
    }
}

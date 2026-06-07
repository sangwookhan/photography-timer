import Foundation

public enum CustomFilmEditorEditField: String, Identifiable, Hashable {
    case manufacturer
    case label
    case iso
    case exponent
    case referenceTm
    case correctedAtReference
    case offset
    case noCorrectionThrough
    case sourceRangeThrough

    public var id: String { rawValue }

    /// Sheet navigation title. Formula fields show the bare
    /// symbol (`Tc₀`, `Tm₀`, `p`, `b`) so the sheet header reads
    /// as the same token the photographer tapped on the main
    /// editor row. Threshold fields use their short label
    /// (`No correction`, `Source data`). Identity fields keep
    /// their short headings.
    public var sheetTitle: String {
        switch self {
        case .manufacturer: return "Manufacturer"
        case .label: return "Label"
        case .iso: return "ISO"
        case .exponent: return "p"
        case .referenceTm: return "Tm₀"
        case .correctedAtReference: return "Tc₀"
        case .offset: return "b"
        case .noCorrectionThrough: return "No correction"
        case .sourceRangeThrough: return "Source data"
        }
    }
}

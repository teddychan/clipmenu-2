import AppKit

// The `clip` object exposed to JS actions and the result it produces
// (ScriptableClip.m:139-339). A script may call
//   clip.setStringAttributes({...})  // replace attributes over the whole string
//   clip.addStringAttributes({...})  // merge attributes
// with { color:{foreground,background}, font:{name,size},
//        underline:{style,pattern,byWord} }, then `return clip;`
// to produce an RTF/RTFD clip (RTFD only if the source was already RTFD).

/// What a JS action produced (ScriptableClip.m + ActionController.m:445-470).
enum JSActionOutcome: Equatable {
    case string(String)         // plain transformed text (or returned ScriptableClip with no RTF)
    case rtf(Data, rtfd: Bool)  // styled clip
    case none                   // undefined / no change
}

/// Source text/rtf handed to the `clip` object.
struct JSClipInput: Sendable {
    var stringValue: String
    var rtfData: Data?
    var isRTFD: Bool
    init(stringValue: String, rtfData: Data? = nil, isRTFD: Bool = false) {
        self.stringValue = stringValue
        self.rtfData = rtfData
        self.isRTFD = isRTFD
    }
}

/// Mutable state behind the JS `clip` object (ScriptableClip._changeStringAttributes).
final class ScriptableClipState {
    enum Mode { case set, add }   // CMChangeAttributesSetType / AddType

    private let stringValue: String
    private var rtfData: Data?
    private var isRTFD: Bool

    init(_ input: JSClipInput) {
        stringValue = input.stringValue
        rtfData = input.rtfData
        isRTFD = input.isRTFD
    }

    /// The clip's current result (rtf if any styling was produced, else the text).
    var outcome: JSActionOutcome {
        if let rtfData { return .rtf(rtfData, rtfd: isRTFD) }
        return .string(stringValue)
    }

    /// setStringAttributes / addStringAttributes (ScriptableClip.m:178-265).
    func change(_ dict: [String: Any], mode: Mode) {
        guard !stringValue.isEmpty else { return }

        let attrString: NSMutableAttributedString
        if let data = rtfData, isRTFD,
           let s = NSMutableAttributedString(rtfd: data, documentAttributes: nil) {
            attrString = s
        } else if let data = rtfData,
                  let s = NSMutableAttributedString(rtf: data, documentAttributes: nil) {
            attrString = s
        } else {
            attrString = NSMutableAttributedString(string: stringValue)
        }

        let range = NSRange(location: 0, length: attrString.length)
        var attrs: [NSAttributedString.Key: Any] = [:]

        if let color = dict["color"] as? [String: Any] {
            if let fg = color["foreground"] as? String, let c = CSSColor.color(fg) {
                attrs[.foregroundColor] = c
            }
            if let bg = color["background"] as? String, let c = CSSColor.color(bg) {
                attrs[.backgroundColor] = c
            }
        }
        if let fontObj = dict["font"] as? [String: Any], let name = fontObj["name"] as? String {
            let size = (fontObj["size"] as? NSNumber)?.doubleValue
                ?? (fontObj["size"] as? Double) ?? 0
            if let font = NSFont(name: name, size: CGFloat(size)) { attrs[.font] = font }
        }
        if let underline = dict["underline"] as? [String: Any] {
            let style = Self.underlineStyle(underline["style"] as? String)
            let pattern = Self.underlinePattern(underline["pattern"] as? String)
            let byWord = (underline["byWord"] as? NSNumber)?.boolValue
                ?? (underline["byWord"] as? Bool) ?? false
            let raw = style.rawValue | pattern.rawValue | (byWord ? NSUnderlineStyle.byWord.rawValue : 0)
            attrs[.underlineStyle] = NSNumber(value: raw)
        }

        guard !attrs.isEmpty else { return }

        attrString.beginEditing()
        switch mode {
        case .set: attrString.setAttributes(attrs, range: range)
        case .add: attrString.addAttributes(attrs, range: range)
        }
        attrString.fixAttributes(in: range)
        attrString.endEditing()

        // A clip from a plain string becomes RTF; an RTFD source stays RTFD
        // (ScriptableClip.m:256-260).
        rtfData = isRTFD ? attrString.rtfd(from: range, documentAttributes: [:])
                         : attrString.rtf(from: range, documentAttributes: [:])
    }

    // Underline name → constant (ScriptableClip.m:43-100; default none/solid).
    private static func underlineStyle(_ name: String?) -> NSUnderlineStyle {
        switch name?.lowercased() {
        case "single": return .single
        case "thick":  return .thick
        case "double": return .double
        default:       return []   // none
        }
    }

    private static func underlinePattern(_ name: String?) -> NSUnderlineStyle {
        switch name?.lowercased() {
        case "dot":        return .patternDot
        case "dash":       return .patternDash
        case "dashdot":    return .patternDashDot
        case "dashdotdot": return .patternDashDotDot
        default:           return []   // patternSolid == 0
        }
    }
}

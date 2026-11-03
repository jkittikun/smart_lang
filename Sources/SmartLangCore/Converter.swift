import Foundation

public enum Converter {
    /// Re-types `text` as if the same physical keys had been pressed in `to`
    /// instead of `from`. Characters `from` can't produce (spaces, newlines,
    /// emoji, …) pass through unchanged.
    public static func convert(_ text: String, from: KeyLayout, to: KeyLayout) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if let stroke = from.reverse[scalar], let mapped = to.map[stroke] {
                out.append(contentsOf: mapped.unicodeScalars)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// Guesses which language a piece of text is written in, by majority of
    /// letters. Returns nil when there are no letters at all.
    public static func dominantLanguage(of text: String) -> Language? {
        var thai = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if ThaiChars.isThai(scalar) { thai += 1 }
            else if scalar.isASCII, CharacterSet.letters.contains(scalar) { latin += 1 }
        }
        if thai == 0 && latin == 0 { return nil }
        return thai >= latin ? .thai : .english
    }

    /// Which language the text was *typed* in, for converting a selection.
    /// Unlike `dominantLanguage`, wrong-layout English text such as `l;ylfu`
    /// counts as English because every character comes from the US layout.
    public static func sourceLanguage(of text: String) -> Language? {
        if text.unicodeScalars.contains(where: ThaiChars.isThai) { return .thai }
        if text.unicodeScalars.contains(where: { $0.isASCII && !CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return .english
        }
        return nil
    }
}

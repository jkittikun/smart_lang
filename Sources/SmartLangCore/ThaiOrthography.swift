import Foundation

public enum ThaiChars {
    public enum Category: Equatable {
        case consonant      // ก–ฮ
        case leadingVowel   // เ แ โ ใ ไ
        case followingVowel // ะ า ำ ๅ
        case markVowel      // ั ิ ี ึ ื ุ ู  (above / below the consonant)
        case maitaikhu      // ็
        case tone           // ่ ้ ๊ ๋
        case thanthakhat    // ์
        case rareMark       // ฺ ํ ๎ – obsolete or very rare marks
        case repetition     // ๆ
        case abbreviation   // ฯ
        case digit          // ๐–๙
        case baht           // ฿
        case other
    }

    public static func isThai(_ s: Unicode.Scalar) -> Bool {
        (0x0E01...0x0E5B).contains(s.value)
    }

    public static func category(_ s: Unicode.Scalar) -> Category {
        switch s.value {
        case 0x0E01...0x0E2E: return .consonant
        case 0x0E2F: return .abbreviation
        case 0x0E30, 0x0E32, 0x0E33, 0x0E45: return .followingVowel
        case 0x0E31, 0x0E34...0x0E39: return .markVowel
        case 0x0E3A, 0x0E4D, 0x0E4E: return .rareMark
        case 0x0E3F: return .baht
        case 0x0E40...0x0E44: return .leadingVowel
        case 0x0E46: return .repetition
        case 0x0E47: return .maitaikhu
        case 0x0E48...0x0E4B: return .tone
        case 0x0E4C: return .thanthakhat
        case 0x0E50...0x0E59: return .digit
        default: return .other
        }
    }

    /// Characters that exist on the keyboard but almost never appear in modern text.
    public static let rareLetters: Set<Unicode.Scalar> = ["ฃ", "ฅ", "ฦ", "ๅ", "ฺ", "ํ", "๎"]
}

/// Lightweight Thai spelling-shape rules. They don't prove a word is real,
/// but random English keystrokes rendered in a Thai layout break them very
/// often (a tone mark at the start, a vowel stacked on a vowel, …).
public enum ThaiOrthography {
    public struct Result: Equatable {
        public var isValid: Bool
        public var rareCount: Int
    }

    public static func check(_ text: String) -> Result {
        var rare = 0
        var prev: ThaiChars.Category? = nil
        var prevScalar: Unicode.Scalar? = nil
        var prevPrevScalar: Unicode.Scalar? = nil

        for s in text.unicodeScalars {
            if ThaiChars.rareLetters.contains(s) { rare += 1 }
            let cat = ThaiChars.category(s)
            let ok: Bool
            switch cat {
            case .consonant:
                ok = true
            case .leadingVowel:
                ok = prev != .leadingVowel
            case .markVowel, .maitaikhu:
                ok = prev == .consonant
            case .tone:
                ok = prev == .consonant || prev == .markVowel
            case .thanthakhat:
                ok = prev == .consonant || prevScalar == "ิ" || prevScalar == "ุ"
            case .followingVowel:
                switch s {
                case "ะ": ok = prev == .consonant || prev == .tone || prevScalar == "า"
                case "ๅ": ok = prevScalar == "ฤ" || prevScalar == "ฦ"
                default: ok = prev == .consonant || prev == .tone // า ำ
                }
            case .rareMark:
                ok = prev == .consonant
            case .repetition, .abbreviation:
                ok = prev != nil && prev != .leadingVowel
            case .digit, .baht:
                ok = prev == nil || prev == .digit || prev == .baht
            case .other:
                ok = false
            }
            if !ok { return Result(isValid: false, rareCount: rare) }
            // A leading vowel must be followed by a consonant.
            if prev == .leadingVowel && cat != .consonant { return Result(isValid: false, rareCount: rare) }
            // Mai han-akat ( ั ) needs a final consonant (optionally after a tone mark);
            // mai taikhu ( ็ ) is always followed by a final consonant.
            if prevScalar == "ั" && cat != .consonant && cat != .tone { return Result(isValid: false, rareCount: rare) }
            // (ก็ "also" is the one common exception.)
            if prev == .maitaikhu && cat != .consonant && prevPrevScalar != "ก" {
                return Result(isValid: false, rareCount: rare)
            }
            prev = cat
            prevPrevScalar = prevScalar
            prevScalar = s
        }
        if prev == .leadingVowel || prevScalar == "ั" || (prev == .maitaikhu && prevPrevScalar != "ก") {
            return Result(isValid: false, rareCount: rare)
        }
        return Result(isValid: true, rareCount: rare)
    }
}

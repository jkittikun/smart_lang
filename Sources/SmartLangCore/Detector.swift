import Foundation

/// Scores how plausible a piece of text is in a language and decides whether a
/// word typed in one layout should be replaced by its other-layout rendering.
///
/// Scores roughly mean:  +3 = known word,  0 = plausible but unknown,
/// negative = looks like keyboard garbage.
public final class Detector {
    public enum Sensitivity: String, Codable, CaseIterable, Sendable {
        case conservative, balanced, aggressive

        /// Minimum (alternative score − typed score) required to auto-correct.
        public var threshold: Int {
            switch self {
            case .conservative: return 5
            case .balanced: return 4
            case .aggressive: return 3
            }
        }
    }

    public var englishWords: Set<String>
    public var thaiWords: Set<String> {
        didSet { maxThaiWordLength = Self.maxLength(thaiWords) }
    }
    /// Optional extra English dictionary (the app plugs in NSSpellChecker).
    public var extraEnglishCheck: ((String) -> Bool)?
    /// Words the user never wants auto-corrected (learned from undo).
    public var ignored: Set<String> = []
    /// Words the user fixed by hand with the flip shortcut: what they typed
    /// (in the wrong layout) → what it should become. Learned so the same
    /// word is fixed automatically next time.
    public var learned: [String: String] = [:]
    public var minimumKeystrokes = 3
    /// Shortest word that can be learned from a manual flip.
    public static let minimumLearnedKeystrokes = 2

    /// True if the user taught us that `typed` should become `alternative`.
    public func isLearned(typed: String, alternative: String) -> Bool {
        learned[typed] == alternative
    }

    private var maxThaiWordLength: Int

    private static func maxLength(_ words: Set<String>) -> Int {
        words.map { $0.unicodeScalars.count }.max() ?? 1
    }

    public init(englishWords: Set<String> = WordLists.english,
                thaiWords: Set<String> = WordLists.thai,
                extraEnglishCheck: ((String) -> Bool)? = nil) {
        self.englishWords = englishWords
        self.thaiWords = thaiWords
        self.extraEnglishCheck = extraEnglishCheck
        self.maxThaiWordLength = Self.maxLength(thaiWords)
    }

    public func score(_ text: String, as language: Language) -> Int {
        switch language {
        case .english: return englishScore(text)
        case .thai: return thaiScore(text)
        }
    }

    /// Should `typed` (in `typedLanguage`) be replaced with `alternative`?
    public func shouldCorrect(typed: String, typedLanguage: Language,
                              alternative: String, keystrokeCount: Int,
                              sensitivity: Sensitivity = .balanced) -> Bool {
        guard typed != alternative else { return false }
        if ignored.contains(typed.lowercased()) { return false }
        if keystrokeCount >= Self.minimumLearnedKeystrokes, isLearned(typed: typed, alternative: alternative) {
            return true
        }
        guard keystrokeCount >= minimumKeystrokes else { return false }
        let t = score(typed, as: typedLanguage)
        let a = score(alternative, as: typedLanguage.other)
        return t < 0 && a >= 0 && a - t >= sensitivity.threshold
    }

    /// Minimum keystrokes before a word may be fixed mid-word.
    public var liveMinimumKeystrokes = 4

    /// Stricter rule for fixing a word *while it is still being typed*
    /// (before Space). The typed text must be clearly broken and the
    /// alternative must be a known word, since the word may not be finished.
    public func shouldCorrectLive(typed: String, typedLanguage: Language,
                                  alternative: String, keystrokeCount: Int,
                                  sensitivity: Sensitivity = .balanced) -> Bool {
        guard typed != alternative else { return false }
        let lower = typed.lowercased()
        // Never fire on the beginning of a word the user has told us to leave alone.
        if ignored.contains(where: { $0.hasPrefix(lower) }) { return false }
        if keystrokeCount >= minimumKeystrokes, isLearned(typed: typed, alternative: alternative) {
            // A learned word is fixed as soon as it is complete, unless it is a real
            // word as typed (it may be the start of something longer) or the start
            // of another learned word.
            return score(typed, as: typedLanguage) < 3
                && !learned.keys.contains(where: { $0 != typed && $0.hasPrefix(typed) })
        }
        guard keystrokeCount >= liveMinimumKeystrokes else { return false }
        let t = score(typed, as: typedLanguage)
        guard t <= -2 else { return false }
        let a = score(alternative, as: typedLanguage.other)
        return a >= 3 && a - t >= sensitivity.threshold + 1
    }

    // MARK: English

    private static let leadingPunct: Set<Character> = ["(", "\""]
    private static let trailingPunct: Set<Character> = [".", ",", "!", "?", ":", ")", "\""]
    /// Punctuation that is legal at a word edge in English but sits on very
    /// common Thai keys (ง ว บ ล), so it is suspicious there.
    private static let suspiciousEdge: Set<Character> = [";", "'", "[", "]"]
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
    private static let onsets: Set<String> = [
        "bl", "br", "ch", "cl", "cr", "dr", "dw", "fl", "fr", "gh", "gl", "gn", "gr", "kl", "kn", "kr",
        "ph", "pl", "pn", "pr", "ps", "qu", "rh", "sc", "sh", "sk", "sl", "sm", "sn", "sp", "sq", "st",
        "sw", "th", "tr", "tw", "wh", "wr", "sch", "scr", "shr", "sph", "spl", "spr", "squ", "str",
        "thr", "chr", "phr", "ts", "zh", "cz", "mc", "dj", "sv", "vl", "pf",
    ]

    func englishScore(_ raw: String) -> Int {
        var word = Substring(raw)
        var edgePenalty = 0
        while let f = word.first, Self.leadingPunct.contains(f) || Self.suspiciousEdge.contains(f) {
            if Self.suspiciousEdge.contains(f) { edgePenalty -= 2 }
            word = word.dropFirst()
        }
        while let l = word.last, Self.trailingPunct.contains(l) || Self.suspiciousEdge.contains(l) {
            if Self.suspiciousEdge.contains(l) { edgePenalty -= 2 }
            word = word.dropLast()
        }
        if word.isEmpty { return -3 }

        let lower = word.lowercased()
        var hasLetter = false, hasDigit = false
        for (i, ch) in lower.enumerated() {
            if ch.isASCII && ch.isLetter { hasLetter = true; continue }
            if ch.isASCII && ch.isNumber { hasDigit = true; continue }
            // Allow internal apostrophes and hyphens: don't, e-mail.
            if (ch == "'" || ch == "-") && i > 0 && i < lower.count - 1 { continue }
            return -3
        }
        if hasDigit { return hasLetter ? -3 : edgePenalty } // pure numbers are fine, "4kKk" is not
        if englishWords.contains(lower) { return 3 + edgePenalty }
        var score = edgePenalty
        if let extra = extraEnglishCheck {
            if extra(String(word)) { return 3 + edgePenalty }
            // A full dictionary is available and doesn't know this word.
            score -= 1
        }

        // Mixed case like "kKk" (but allow Capitalised and ALLCAPS).
        let tail = word.dropFirst()
        if tail.contains(where: { $0.isUppercase }) && tail.contains(where: { $0.isLowercase }) { score -= 2 }

        let letters = Array(lower)
        if letters.count >= 3 && !letters.contains(where: { Self.vowels.contains($0) }) { score -= 2 }

        // Initial consonant cluster must be a real English onset.
        var onset = ""
        for ch in letters { if Self.vowels.contains(ch) { break }; onset.append(ch) }
        if onset.count >= 2 && onset.count < letters.count && !Self.onsets.contains(onset) { score -= 2 }

        var consonantRun = 0, vowelRun = 0, maxC = 0, maxV = 0
        for ch in letters {
            if Self.vowels.contains(ch) { vowelRun += 1; consonantRun = 0 } else { consonantRun += 1; vowelRun = 0 }
            maxC = max(maxC, consonantRun); maxV = max(maxV, vowelRun)
        }
        if maxC >= 5 { score -= 2 }
        if maxV >= 4 { score -= 1 }
        for i in letters.indices where letters[i] == "q" {
            if i + 1 >= letters.count || letters[i + 1] != "u" { score -= 1; break }
        }
        for i in letters.indices.dropFirst(2) where letters[i] == letters[i - 1] && letters[i] == letters[i - 2] {
            score -= 1; break
        }
        return score
    }

    // MARK: Thai

    func thaiScore(_ raw: String) -> Int {
        var scalars = Array(raw.unicodeScalars)
        // Ignore trailing sentence punctuation the user may have typed.
        while let l = scalars.last, l.isASCII, ".,!?".unicodeScalars.contains(l) { scalars.removeLast() }
        if scalars.isEmpty { return -3 }

        var hasThaiLetter = false, hasThaiDigit = false
        for s in scalars {
            if !ThaiChars.isThai(s) { return -3 } // ASCII letters/punctuation mixed in
            switch ThaiChars.category(s) {
            case .digit: hasThaiDigit = true
            case .baht: break
            default: hasThaiLetter = true
            }
        }
        if hasThaiDigit && hasThaiLetter { return -3 }
        if !hasThaiLetter { return 0 }

        let text = String(String.UnicodeScalarView(scalars))
        let ortho = ThaiOrthography.check(text)
        if !ortho.isValid { return -3 }

        var score = -2 * min(ortho.rareCount, 2)
        let coverage = dictionaryCoverage(scalars)
        if coverage >= 0.999 { score += 3 }
        else if coverage >= 0.7 { score += 1 }
        else if coverage < 0.5 { score -= 1 } // well-formed, but nothing we recognise
        return score
    }

    /// Fraction of scalars covered by dictionary words in the best segmentation.
    /// Thai is written without spaces, so a chunk may be several words.
    func dictionaryCoverage(_ s: [Unicode.Scalar]) -> Double {
        let n = s.count
        guard n > 0 else { return 0 }
        // best[i] = most scalars covered by dictionary words in s[i...]
        var best = [Int](repeating: 0, count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var b = best[i + 1] // skip one scalar as unknown
            let limit = min(n, i + maxThaiWordLength)
            if i + 1 <= limit {
                for j in (i + 1)...limit {
                    let candidate = String(String.UnicodeScalarView(s[i..<j]))
                    if thaiWords.contains(candidate) { b = max(b, (j - i) + best[j]) }
                }
            }
            best[i] = b
        }
        return Double(best[0]) / Double(n)
    }
}

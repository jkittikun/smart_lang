import Carbon
import Foundation
import SmartLangCore

/// Wraps the Text Input Source (TIS) APIs: which keyboard layout is active,
/// switching layouts, and reading each installed layout's real key table.
final class InputSourceManager {
    struct Source {
        let id: String
        let name: String
        let language: Language
        let ref: TISInputSource
    }

    private var layoutCache: [String: KeyLayout] = [:]
    /// Candidate layouts per language. Rebuilt when the input source changes,
    /// because the live check asks for them on every keystroke.
    private var candidateCache: [Language: [KeyLayout]] = [:]
    /// Last layout the user had active for each language, so we switch back to
    /// *their* Thai/English layout (Kedmanee vs Pattachote, US vs ABC, …).
    private(set) var lastUsed: [Language: String] = [:]
    var onChange: (() -> Void)?

    init() {
        if let current = currentSource() { lastUsed[current.language] = current.id }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let current = self.currentSource() { self.lastUsed[current.language] = current.id }
            self.candidateCache.removeAll()
            self.onChange?()
        }
    }

    // MARK: Querying

    func currentSource() -> Source? {
        guard let ref = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return makeSource(ref)
    }

    /// All enabled, selectable keyboard layouts that are Thai or English.
    func enabledSources() -> [Source] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true,
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue()
                as? [TISInputSource] else { return [] }
        return list.compactMap(makeSource)
    }

    func sources(for language: Language) -> [Source] {
        enabledSources().filter { $0.language == language }
    }

    /// The layout to try for `language`: the one used most recently, else the
    /// first enabled one, else nil.
    func preferredSource(for language: Language) -> Source? {
        let candidates = sources(for: language)
        if let id = lastUsed[language], let s = candidates.first(where: { $0.id == id }) { return s }
        return candidates.first
    }

    /// Key table for a source, read from the installed layout data so it is
    /// exactly what macOS would type. Falls back to built-in tables.
    func layout(for source: Source) -> KeyLayout {
        if let cached = layoutCache[source.id] { return cached }
        let layout = readLayout(source) ?? builtinLayout(id: source.id, language: source.language)
        layoutCache[source.id] = layout
        return layout
    }

    /// Candidate layouts to render a word in for `language`, best first.
    func candidateLayouts(for language: Language) -> [KeyLayout] {
        if let cached = candidateCache[language] { return cached }
        var result: [KeyLayout] = []
        if let preferred = preferredSource(for: language) { result.append(layout(for: preferred)) }
        for s in sources(for: language) where !result.contains(where: { $0.id == s.id }) {
            result.append(layout(for: s))
        }
        if result.isEmpty {
            result = language == .english ? [BuiltinLayouts.us] : [BuiltinLayouts.kedmanee, BuiltinLayouts.pattachote]
        }
        candidateCache[language] = result
        return result
    }

    // MARK: Switching

    @discardableResult
    func select(language: Language, preferringLayoutID id: String? = nil) -> Bool {
        let candidates = sources(for: language)
        let target = candidates.first(where: { $0.id == id }) ?? preferredSource(for: language)
        guard let target else { return false }
        return TISSelectInputSource(target.ref) == noErr
    }

    // MARK: Private

    private func makeSource(_ ref: TISInputSource) -> Source? {
        guard let id = stringProperty(ref, kTISPropertyInputSourceID) else { return nil }
        let name = stringProperty(ref, kTISPropertyLocalizedName) ?? id
        var language: Language?
        if let ptr = TISGetInputSourceProperty(ref, kTISPropertyInputSourceLanguages),
           let langs = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String],
           let primary = langs.first {
            if primary.hasPrefix("th") { language = .thai }
            else if primary.hasPrefix("en") { language = .english }
        }
        if language == nil && id.localizedCaseInsensitiveContains("thai") { language = .thai }
        guard let language else { return nil }
        return Source(id: id, name: name, language: language, ref: ref)
    }

    private func stringProperty(_ ref: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(ref, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func builtinLayout(id: String, language: Language) -> KeyLayout {
        if language == .english { return BuiltinLayouts.us }
        return id.localizedCaseInsensitiveContains("patta") ? BuiltinLayouts.pattachote : BuiltinLayouts.kedmanee
    }

    private func readLayout(_ source: Source) -> KeyLayout? {
        guard let ptr = TISGetInputSourceProperty(source.ref, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())
        var map: [KeyStroke: String] = [:]

        data.withUnsafeBytes { raw in
            guard let layoutPtr = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in KeyCodes.printable {
                for shift in [false, true] {
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let modifiers: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
                    let status = UCKeyTranslate(layoutPtr, code, UInt16(kUCKeyActionDown), modifiers,
                                                keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                                &deadKeyState, chars.count, &length, &chars)
                    guard status == noErr, length > 0 else { continue }
                    let s = String(utf16CodeUnits: chars, count: length)
                    if s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                        map[KeyStroke(keyCode: code, shift: shift)] = s
                    }
                }
            }
        }
        // Sanity check: a usable table covers most keys.
        guard map.count >= 80 else { return nil }
        return KeyLayout(id: source.id, name: source.name, language: source.language, map: map)
    }
}

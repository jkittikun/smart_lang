import AppKit
import Carbon
import SmartLangCore

/// Watches the keyboard, auto-corrects words typed in the wrong layout and
/// flips the last word / selection on the hotkey.
final class Engine {
    private let settings: AppSettings
    private let inputSources = InputSourceManager()
    private let detector: Detector
    private var tap: CFMachPort?
    private var retryTimer: Timer?
    private let workQueue = DispatchQueue(label: "smartlang.replace")

    /// Notifies the UI (menu bar icon) after a correction or flip.
    var onActivity: ((String) -> Void)?
    var isRunning: Bool { tap != nil }

    // MARK: Word state

    /// The word being typed (or the one just finished, until something else happens).
    private struct Word {
        var strokes: [KeyStroke] = []
        var capsLock = false
        /// What is currently on screen for this word.
        var text = ""
        var language: Language = .english
        var layoutID = ""
        /// The layout the word was first typed in.
        var typedLanguage: Language = .english
        var typedLayoutID = ""
        /// Space/tab that followed the word, if it has been finished.
        var boundary: CGEvent?
        /// The layout of the *other* rendering, so flipping toggles between
        /// exactly the same two texts.
        var otherLayoutID: String?
        /// What the user originally typed, if we auto-corrected it.
        var autoCorrectedFrom: String?
        /// The language the word was originally typed in, if we auto-corrected it.
        var autoCorrectedLanguage: Language?
        /// The user flipped this word by hand; don't auto-check it again.
        var manual = false
        /// Already fixed mid-word; don't check it again (live or at Space).
        var liveFixed = false
        /// The typed text we learned from flipping this word by hand, if any.
        var learnedKey: String?
    }

    private var current = Word()
    private var last: Word?

    // MARK: Replacement / queued input

    private var replacing = false
    private var queued: [CGEvent] = []

    // MARK: Double-tap hotkey

    private var tapModifier: Hotkey.Modifier?
    private var tapDownAt: TimeInterval = 0
    private var lastTapUpAt: TimeInterval = 0
    private var tapsSoFar = 0
    private var otherKeySinceTapDown = false

    private var frontmostBundleID: String?

    init(settings: AppSettings) {
        self.settings = settings
        detector = Detector(extraEnglishCheck: { word in
            let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: "en",
                                                            wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            return range.location == NSNotFound
        })
        applySettings()
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostBundleID = app?.bundleIdentifier
            self?.resetWords()
        }
    }

    func applySettings() {
        detector.ignored = Set(settings.ignoredWords.map { $0.lowercased() })
        detector.thaiWords = WordLists.thai.union(settings.customThaiWords)
        detector.learned = settings.learnedWords
    }

    // MARK: Lifecycle

    func start() {
        guard tap == nil else { return }
        if !installTap() {
            // Not trusted yet: keep trying until the user grants permission.
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                if self?.installTap() == true { timer.invalidate() }
            }
        }
    }

    private func installTap() -> Bool {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<Engine>.fromOpaque(refcon).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        onActivity?("ready")
        return true
    }

    // MARK: Event handling (main thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if Synth.isOurs(event) { return pass }

        // While we are rewriting text, hold the user's keystrokes and replay them afterwards.
        if replacing && (type == .keyDown || type == .keyUp) {
            // Never queue the flip shortcut itself: holding it down would
            // otherwise replay as a burst of flips once the rewrite ends.
            if isFlipCombo(event) { return nil }
            if let copy = event.copy() { queued.append(copy) }
            return nil
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            resetWords()
            resetDoubleTap()
            return pass
        case .flagsChanged:
            if handleFlagsChanged(event) {
                DispatchQueue.main.async { [weak self] in self?.flip() }
            }
            return pass
        case .keyUp:
            return pass
        case .keyDown:
            return handleKeyDown(event) ? nil : pass
        default:
            return pass
        }
    }

    /// Returns true if the event should be swallowed.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        otherKeySinceTapDown = true
        tapsSoFar = 0
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // The shortcut is left alone while it is being recorded, and inside
        // SmartLang's own windows (there is nothing to flip there).
        if settings.enabled, !settings.isRecordingHotkey, !isOwnAppFrontmost,
           case let .combo(code, mods, _) = settings.hotkey,
           keyCode == code, flags.rawValue & Self.modifierMask == mods {
            DispatchQueue.main.async { [weak self] in self?.flip() }
            return true
        }

        guard settings.enabled, !isExcludedApp else { resetWords(); return false }

        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            resetWords()
            return false
        }

        if keyCode == KeyCodes.delete {
            if current.strokes.isEmpty {
                last = nil
            } else {
                current.strokes.removeLast()
                if !current.text.unicodeScalars.isEmpty { current.text.unicodeScalars.removeLast() }
                if current.strokes.isEmpty { current = Word() }
            }
            return false
        }

        if KeyCodes.boundaries.contains(keyCode) {
            return finishWord(boundary: event, keyCode: keyCode)
        }

        if KeyCodes.printable.contains(keyCode) {
            let typed = unicodeString(of: event)
            guard !typed.isEmpty else { resetWords(); return false } // dead key etc.
            if current.strokes.isEmpty {
                last = nil
                current = Word()
                if let src = inputSources.currentSource() {
                    current.language = src.language
                    current.layoutID = src.id
                }
                current.typedLanguage = current.language
                current.typedLayoutID = current.layoutID
            }
            current.strokes.append(KeyStroke(keyCode: keyCode, shift: flags.contains(.maskShift)))
            current.capsLock = flags.contains(.maskAlphaShift)
            current.text += typed
            liveCheck()
            return false
        }

        // Arrows, escape, function keys, …: the cursor moved, forget everything.
        resetWords()
        return false
    }

    /// Word boundary reached. Returns true if the boundary key was swallowed
    /// (because we are about to rewrite the word and re-post it).
    private func finishWord(boundary: CGEvent, keyCode: UInt16) -> Bool {
        guard !current.strokes.isEmpty else { last = nil; return false }
        var word = current
        current = Word()
        let flippable = keyCode == KeyCodes.space || keyCode == KeyCodes.tab
        word.boundary = flippable ? boundary.copy() : nil
        // Flipped by hand while typing: the word may have grown since, so
        // remember the whole of it now that it is complete.
        if word.manual { learn(from: &word) }

        if settings.autoCorrect, !word.manual, !word.liveFixed, let fix = bestAlternative(for: word, live: false) {
            word.autoCorrectedFrom = word.text
            word.autoCorrectedLanguage = word.language
            word.otherLayoutID = word.layoutID
            let oldText = word.text
            word.text = fix.text
            word.language = fix.layout.language
            word.layoutID = fix.layout.id
            last = flippable ? word : nil
            rewrite(deleting: oldText.unicodeScalars.count, typing: fix.text,
                    then: boundary.copy(), switchTo: fix.layout)
            onActivity?("\(oldText) → \(fix.text)")
            return true
        }
        last = flippable ? word : nil
        return false
    }

    /// Fixes the word being typed as soon as it is clearly a real word in the
    /// other language, without waiting for Space. The input source switches
    /// too, so the rest of the word comes out in the right language.
    private func liveCheck() {
        guard settings.fixWhileTyping, settings.autoCorrect, !current.manual, !current.liveFixed,
              let fix = bestAlternative(for: current, live: true) else { return }
        let oldText = current.text
        current.autoCorrectedFrom = oldText
        current.autoCorrectedLanguage = current.language
        current.otherLayoutID = current.layoutID
        current.text = fix.text
        current.language = fix.layout.language
        current.layoutID = fix.layout.id
        current.liveFixed = true
        // The key that completed the word is still on its way to the app;
        // `rewrite` waits briefly so its Backspaces arrive after it.
        rewrite(deleting: oldText.unicodeScalars.count, typing: fix.text,
                then: nil, switchTo: fix.layout, afterPendingKey: true)
        onActivity?("\(oldText) → \(fix.text)")
    }

    private func bestAlternative(for word: Word, live: Bool) -> (text: String, layout: KeyLayout)? {
        let layouts = inputSources.candidateLayouts(for: word.language.other)
        // A word the user taught us by flipping it wins outright.
        for layout in layouts {
            let alt = layout.render(word.strokes, capsLock: word.capsLock)
            guard detector.isLearned(typed: word.text, alternative: alt) else { continue }
            let ok = live
                ? detector.shouldCorrectLive(typed: word.text, typedLanguage: word.language, alternative: alt,
                                             keystrokeCount: word.strokes.count, sensitivity: settings.sensitivity)
                : detector.shouldCorrect(typed: word.text, typedLanguage: word.language, alternative: alt,
                                         keystrokeCount: word.strokes.count, sensitivity: settings.sensitivity)
            return ok ? (alt, layout) : nil
        }
        var best: (text: String, layout: KeyLayout, score: Int)?
        for layout in layouts {
            let alt = layout.render(word.strokes, capsLock: word.capsLock)
            let ok = live
                ? detector.shouldCorrectLive(typed: word.text, typedLanguage: word.language, alternative: alt,
                                             keystrokeCount: word.strokes.count, sensitivity: settings.sensitivity)
                : detector.shouldCorrect(typed: word.text, typedLanguage: word.language, alternative: alt,
                                         keystrokeCount: word.strokes.count, sensitivity: settings.sensitivity)
            guard ok else { continue }
            let s = detector.score(alt, as: layout.language)
            if best == nil || s > best!.score { best = (alt, layout, s) }
        }
        return best.map { ($0.text, $0.layout) }
    }

    // MARK: Flip (hotkey)

    /// Flips the current word, else the last word, else the selection.
    func flip() {
        guard settings.enabled, !replacing else { return }
        if !current.strokes.isEmpty {
            flipWord(&current, includesBoundary: false)
        } else if var word = last {
            flipWord(&word, includesBoundary: true)
            last = word
        } else {
            flipSelection()
        }
    }

    private func flipWord(_ word: inout Word, includesBoundary: Bool) {
        let target = word.language.other
        // Toggling back? Use exactly the layout the other text came from.
        let layout: KeyLayout
        if let otherID = word.otherLayoutID,
           let src = inputSources.sources(for: target).first(where: { $0.id == otherID }) {
            layout = inputSources.layout(for: src)
        } else if let builtin = BuiltinLayouts.all.first(where: { $0.id == word.otherLayoutID && $0.language == target }) {
            layout = builtin
        } else {
            layout = inputSources.candidateLayouts(for: target).max { a, b in
                detector.score(a.render(word.strokes, capsLock: word.capsLock), as: target)
                    < detector.score(b.render(word.strokes, capsLock: word.capsLock), as: target)
            } ?? (target == .english ? BuiltinLayouts.us : BuiltinLayouts.kedmanee)
        }
        let newText = layout.render(word.strokes, capsLock: word.capsLock)
        let oldText = word.text
        let boundary = includesBoundary ? word.boundary : nil

        let undidAutoCorrection = word.autoCorrectedFrom != nil && word.autoCorrectedLanguage == layout.language
        if undidAutoCorrection {
            // The user undid an auto-correction: remember not to do that again.
            // Use the whole word as typed (it may be longer than when it was fixed).
            let key = newText.lowercased()
            if !settings.ignoredWords.contains(key) {
                settings.ignoredWords.append(key)
            }
            // If it was fixed because we learned it, unlearn it.
            settings.learnedWords[newText] = nil
            applySettings()
        }
        word.otherLayoutID = word.layoutID
        word.text = newText
        word.language = layout.language
        word.layoutID = layout.id
        word.manual = true

        // Flipped by hand: learn it right away. If the word is still being typed,
        // it is learned again when it ends, in case it grew.
        if !undidAutoCorrection { learn(from: &word) }

        rewrite(deleting: oldText.unicodeScalars.count + (boundary == nil ? 0 : 1),
                typing: newText, then: boundary, switchTo: layout, manual: true)
        onActivity?("\(oldText) → \(newText)")
    }

    private func flipSelection() {
        if let text = Selection.selectedTextViaAccessibility() {
            replaceSelection(text)
            return
        }
        replacing = true
        workQueue.async { [weak self] in
            let text = Selection.selectedTextViaCopy()
            DispatchQueue.main.async {
                guard let self else { return }
                self.replacing = false
                if let text { self.replaceSelection(text) } else { self.flushQueued(); NSSound.beep() }
            }
        }
    }

    private func replaceSelection(_ text: String) {
        guard let from = Converter.sourceLanguage(of: text),
              let fromLayout = inputSources.candidateLayouts(for: from).first else { NSSound.beep(); return }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let best = inputSources.candidateLayouts(for: from.other).map { layout -> (KeyLayout, String, Int) in
            let converted = Converter.convert(text, from: fromLayout, to: layout)
            let score = words.reduce(0) { $0 + detector.score(Converter.convert($1, from: fromLayout, to: layout), as: from.other) }
            return (layout, converted, score)
        }.max { $0.2 < $1.2 }
        guard let best, best.1 != text else { NSSound.beep(); return }
        let (layout, converted, _) = best
        resetWords()
        learnFromSelection(text.trimmingCharacters(in: .whitespacesAndNewlines),
                           becomes: converted.trimmingCharacters(in: .whitespacesAndNewlines))
        // Typing over a selection replaces it.
        rewrite(deleting: 0, typing: converted, then: nil, switchTo: layout, manual: true)
        onActivity?("\(text) → \(converted)")
    }

    // MARK: Learning

    /// Remembers a word the user flipped by hand, so it is fixed automatically
    /// next time. Flipping it back to how it was typed forgets it again.
    private func learn(from word: inout Word) {
        guard word.autoCorrectedFrom == nil, word.strokes.count >= Detector.minimumLearnedKeystrokes,
              let typedLayout = layout(id: word.typedLayoutID, language: word.typedLanguage) else { return }
        let typed = typedLayout.render(word.strokes, capsLock: word.capsLock)
        // Learned earlier from a shorter version of this word: replace it.
        if let old = word.learnedKey, old != typed {
            settings.learnedWords[old] = nil
        }
        word.learnedKey = nil
        if word.language == word.typedLanguage {
            // Flipped back to what was typed: it was right after all.
            settings.learnedWords[typed] = nil
        } else {
            remember(typed: typed, fixed: word.text)
            word.learnedKey = typed
        }
        applySettings()
    }

    /// Learns from flipping a selected word by hand.
    private func learnFromSelection(_ text: String, becomes converted: String) {
        guard !text.contains(where: \.isWhitespace),
              text.unicodeScalars.count >= Detector.minimumLearnedKeystrokes else { return }
        if settings.learnedWords[converted] == text {
            // Flipping a learned fix back: forget it.
            settings.learnedWords[converted] = nil
        } else {
            remember(typed: text, fixed: converted)
        }
        applySettings()
    }

    private func remember(typed: String, fixed: String) {
        guard typed != fixed else { return }
        if settings.learnedWords[typed] != fixed { settings.learnedWords[typed] = fixed }
        // Learning it overrides an earlier "never auto-correct".
        if settings.ignoredWords.contains(typed.lowercased()) {
            settings.ignoredWords.removeAll { $0 == typed.lowercased() }
        }
    }

    private func layout(id: String, language: Language) -> KeyLayout? {
        if let src = inputSources.sources(for: language).first(where: { $0.id == id }) {
            return inputSources.layout(for: src)
        }
        return BuiltinLayouts.all.first { $0.id == id && $0.language == language }
            ?? inputSources.candidateLayouts(for: language).first
    }

    // MARK: Rewriting

    private func rewrite(deleting count: Int, typing text: String, then boundary: CGEvent?,
                         switchTo layout: KeyLayout, afterPendingKey: Bool = false, manual: Bool = false) {
        replacing = true
        let sound = manual ? settings.flipSound : settings.fixSound
        let volume = settings.soundVolume
        workQueue.async { [weak self] in
            if afterPendingKey { usleep(10_000) }
            Synth.backspace(count)
            Synth.type(text)
            if let boundary { Synth.repost(boundary, markAsOurs: true) }
            DispatchQueue.main.async {
                guard let self else { return }
                var switched = false
                if self.settings.switchInputSource {
                    switched = self.inputSources.select(language: layout.language, preferringLayoutID: layout.id)
                }
                Sounds.play(sound, volume: volume)
                // Give the layout switch a moment to take effect before replaying
                // keys typed meanwhile, so they come out in the new language.
                DispatchQueue.main.asyncAfter(deadline: .now() + (switched ? 0.03 : 0)) {
                    self.replacing = false
                    self.flushQueued(retranslate: switched)
                }
            }
        }
    }

    /// Replays keystrokes the user typed while we were rewriting. They go back
    /// through our tap, so they are tracked like normal typing.
    ///
    /// With `retranslate`, key events are rebuilt from their key codes: a copied
    /// event still carries the character from the *old* layout, while a new one
    /// is translated with the layout that is active now.
    private func flushQueued(retranslate: Bool = false) {
        let events = queued
        queued.removeAll()
        for e in events {
            if retranslate, e.type == .keyDown || e.type == .keyUp {
                let code = CGKeyCode(e.getIntegerValueField(.keyboardEventKeycode))
                if let fresh = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: e.type == .keyDown) {
                    fresh.flags = e.flags
                    fresh.post(tap: .cghidEventTap)
                    continue
                }
            }
            e.post(tap: .cghidEventTap)
        }
    }

    // MARK: Helpers

    private static let modifierMask: UInt64 =
        CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue

    private func isFlipCombo(_ event: CGEvent) -> Bool {
        guard case let .combo(code, mods, _) = settings.hotkey else { return false }
        return UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == code
            && event.flags.rawValue & Self.modifierMask == mods
    }

    private var isOwnAppFrontmost: Bool {
        frontmostBundleID != nil && frontmostBundleID == Bundle.main.bundleIdentifier
    }

    private var isExcludedApp: Bool {
        guard let id = frontmostBundleID else { return false }
        return settings.excludedBundleIDs.contains(id)
    }

    private func resetWords() {
        current = Word()
        last = nil
    }

    private func unicodeString(of event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: Double-tap detection

    private static let modifierKeyCodes: [UInt16: Hotkey.Modifier] = [
        56: .shift, 60: .shift, 58: .option, 61: .option, 59: .control, 62: .control, 55: .command, 54: .command,
    ]

    private func resetDoubleTap() {
        tapsSoFar = 0
        tapModifier = nil
    }

    /// Returns true when the configured double-tap just completed.
    private func handleFlagsChanged(_ event: CGEvent) -> Bool {
        guard case let .doubleTap(wanted) = settings.hotkey else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let modifier = Self.modifierKeyCodes[keyCode] else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let flags = event.flags
        let flag: CGEventFlags
        switch modifier {
        case .shift: flag = .maskShift
        case .option: flag = .maskAlternate
        case .control: flag = .maskControl
        case .command: flag = .maskCommand
        }
        let isDown = flags.contains(flag)
        let others = flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand]).subtracting(flag)

        guard modifier == wanted, others.isEmpty else { resetDoubleTap(); return false }

        if isDown {
            if tapModifier != modifier || now - lastTapUpAt > 0.4 { tapsSoFar = 0 }
            tapModifier = modifier
            tapDownAt = now
            otherKeySinceTapDown = false
            return false
        }
        // Key released: count it as a tap if it was quick and nothing else was pressed.
        guard tapModifier == modifier, !otherKeySinceTapDown, now - tapDownAt < 0.3 else {
            resetDoubleTap(); return false
        }
        tapsSoFar += 1
        lastTapUpAt = now
        if tapsSoFar >= 2 {
            resetDoubleTap()
            return true
        }
        return false
    }
}

import Combine
import Foundation
import SmartLangCore

/// The flip shortcut. Either a double-tap of a modifier key or a normal key combo.
enum Hotkey: Codable, Equatable {
    enum Modifier: String, Codable, CaseIterable {
        case shift, option, control, command
        var title: String {
            switch self {
            case .shift: return "⇧ Shift"
            case .option: return "⌥ Option"
            case .control: return "⌃ Control"
            case .command: return "⌘ Command"
            }
        }
        var symbol: String {
            switch self {
            case .shift: return "⇧"
            case .option: return "⌥"
            case .control: return "⌃"
            case .command: return "⌘"
            }
        }
    }

    case doubleTap(Modifier)
    /// keyCode plus modifier flags (CGEventFlags raw value, masked to ⌘⌥⌃⇧).
    case combo(keyCode: UInt16, modifiers: UInt64, display: String)

    static let `default` = Hotkey.doubleTap(.shift)

    /// Ready-made combos offered in Settings.
    static let presets: [Hotkey] = [
        .combo(keyCode: 51, modifiers: shiftFlag, display: "⇧⌫"),    // Shift + Delete
        .combo(keyCode: 117, modifiers: shiftFlag, display: "⇧⌦"),   // Shift + Forward Delete (Fn+Delete)
    ]

    /// Always built from the key code, never from the typed character: keys
    /// like ⌫ type invisible characters, and letters depend on the active layout.
    var displayName: String {
        switch self {
        case .doubleTap(let m): return "Double-tap \(m.title)"
        case .combo(let code, let mods, _): return Self.describe(keyCode: code, modifiers: mods)
        }
    }

    // MARK: Key names

    static let shiftFlag: UInt64 = 1 << 17
    static let controlFlag: UInt64 = 1 << 18
    static let optionFlag: UInt64 = 1 << 19
    static let commandFlag: UInt64 = 1 << 20

    static func describe(keyCode: UInt16, modifiers: UInt64) -> String {
        var s = ""
        if modifiers & controlFlag != 0 { s += "⌃" }
        if modifiers & optionFlag != 0 { s += "⌥" }
        if modifiers & shiftFlag != 0 { s += "⇧" }
        if modifiers & commandFlag != 0 { s += "⌘" }
        return s + keyName(keyCode)
    }

    private static let specialKeys: [UInt16: String] = [
        51: "⌫", 117: "⌦", 36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖ Home", 119: "↘ End", 116: "⇞ Page Up", 121: "⇟ Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 75: "Keypad /", 78: "Keypad -", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
    ]

    /// Function keys; they may be used with no modifier at all.
    static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                             105, 107, 113, 106, 64, 79, 80, 90]

    static func keyName(_ keyCode: UInt16) -> String {
        if let name = specialKeys[keyCode] { return name }
        // Name letters and symbols as on a US keyboard, whatever layout is active.
        if let ch = BuiltinLayouts.us.map[KeyStroke(keyCode: keyCode, shift: false)] { return ch.uppercased() }
        return "Key \(keyCode)"
    }

    /// Why a combo is not allowed, or nil if it is fine.
    static func rejectionReason(keyCode: UInt16, modifiers: UInt64) -> String? {
        let hasCmdOptCtrl = modifiers & (commandFlag | optionFlag | controlFlag) != 0
        if hasCmdOptCtrl || functionKeys.contains(keyCode) { return nil }
        // The one Shift-only exception: ⇧⌫ / ⇧⌦ (on a Mac they just delete anyway).
        if modifiers == shiftFlag && shiftDeleteKeys.contains(keyCode) { return nil }
        return "Add ⌘, ⌥ or ⌃ (⇧ alone works only with ⌫ or ⌦), so normal typing doesn't trigger it."
    }

    /// ⌫ (Delete) and ⌦ (Forward Delete, Fn+Delete on laptops).
    static let shiftDeleteKeys: Set<UInt16> = [51, 117]

    /// True if this shortcut is allowed by the current rules.
    var isAllowed: Bool {
        guard case let .combo(code, mods, _) = self else { return true }
        return Self.rejectionReason(keyCode: code, modifiers: mods) == nil
    }

    /// A warning if the combo replaces a common macOS shortcut.
    var conflictWarning: String? {
        guard case let .combo(code, mods, _) = self else { return nil }
        let known: [String: String] = [
            "⌘⌫": "deleting to the start of the line", "⌥⌫": "deleting the previous word",
            "⌘C": "Copy", "⌘V": "Paste", "⌘X": "Cut", "⌘Z": "Undo", "⌘A": "Select All",
            "⌘S": "Save", "⌘Q": "Quit", "⌘W": "Close Window", "⌘⇥": "switching apps",
            "⌘Space": "Spotlight", "⌃Space": "switching input sources", "⌃⌥Space": "switching input sources",
        ]
        guard let what = known[Self.describe(keyCode: code, modifiers: mods)] else { return nil }
        return "This replaces the macOS shortcut for \(what) in every app."
    }
}

/// UserDefaults-backed preferences, observable from SwiftUI.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var autoCorrect: Bool { didSet { defaults.set(autoCorrect, forKey: "autoCorrect") } }
    /// Fix a word as soon as it is clearly wrong, without waiting for Space.
    @Published var fixWhileTyping: Bool { didSet { defaults.set(fixWhileTyping, forKey: "fixWhileTyping") } }
    @Published var switchInputSource: Bool { didSet { defaults.set(switchInputSource, forKey: "switchInputSource") } }
    /// System sound played when a word is fixed automatically ("" = none).
    @Published var fixSound: String {
        didSet { defaults.set(fixSound, forKey: "fixSound"); Sounds.play(fixSound, volume: soundVolume) }
    }
    /// System sound played when you flip with the shortcut ("" = none).
    @Published var flipSound: String {
        didSet { defaults.set(flipSound, forKey: "flipSound"); Sounds.play(flipSound, volume: soundVolume) }
    }
    @Published var soundVolume: Double { didSet { defaults.set(soundVolume, forKey: "soundVolume") } }
    /// Menu-bar icon style (StatusIcon.Style raw value).
    @Published var menuBarIcon: String { didSet { defaults.set(menuBarIcon, forKey: "menuBarIcon") } }
    /// How many times the menu-bar icon blinks when a word is fixed or flipped (0 = off).
    @Published var flashCount: Int { didSet { defaults.set(flashCount, forKey: "flashCount") } }
    /// How long each blink stays inverted, in seconds.
    @Published var flashDuration: Double { didSet { defaults.set(flashDuration, forKey: "flashDuration") } }
    /// True while the Settings window is recording a new shortcut; the engine
    /// then leaves the current shortcut alone so it can be recorded.
    var isRecordingHotkey = false
    @Published var sensitivity: Detector.Sensitivity {
        didSet { defaults.set(sensitivity.rawValue, forKey: "sensitivity") }
    }
    @Published var hotkey: Hotkey {
        didSet { defaults.set(try? JSONEncoder().encode(hotkey), forKey: "hotkey") }
    }
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") }
    }
    /// Words the user reverted after an auto-correction; never auto-correct them again.
    @Published var ignoredWords: [String] { didSet { defaults.set(ignoredWords, forKey: "ignoredWords") } }
    /// Words fixed by hand with the flip shortcut: typed text → corrected text.
    /// They are auto-corrected from then on.
    @Published var learnedWords: [String: String] { didSet { defaults.set(learnedWords, forKey: "learnedWords") } }
    /// Extra Thai words to recognise (the built-in Thai list is small).
    @Published var customThaiWords: [String] { didSet { defaults.set(customThaiWords, forKey: "customThaiWords") } }

    static let defaultExcluded = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess",
    ]

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "enabled": true, "autoCorrect": true, "fixWhileTyping": true, "switchInputSource": true,
            "soundVolume": 0.6,
            "menuBarIcon": "diagonal", "flashCount": 2, "flashDuration": 0.15,
            "sensitivity": Detector.Sensitivity.balanced.rawValue,
            "excludedBundleIDs": AppSettings.defaultExcluded,
        ])
        enabled = defaults.bool(forKey: "enabled")
        autoCorrect = defaults.bool(forKey: "autoCorrect")
        fixWhileTyping = defaults.bool(forKey: "fixWhileTyping")
        switchInputSource = defaults.bool(forKey: "switchInputSource")
        // Older versions had a single on/off sound (Tink).
        let legacySound = defaults.bool(forKey: "playSound") ? "Tink" : ""
        fixSound = defaults.string(forKey: "fixSound") ?? legacySound
        flipSound = defaults.string(forKey: "flipSound") ?? ""
        soundVolume = defaults.double(forKey: "soundVolume")
        menuBarIcon = defaults.string(forKey: "menuBarIcon") ?? "diagonal"
        flashCount = min(3, max(0, defaults.integer(forKey: "flashCount")))
        flashDuration = min(0.6, max(0.05, defaults.double(forKey: "flashDuration")))
        sensitivity = Detector.Sensitivity(rawValue: defaults.string(forKey: "sensitivity") ?? "") ?? .balanced
        // A saved shortcut that is no longer allowed (e.g. ⇧⌫ from an earlier
        // version) falls back to the default double-tap Shift.
        if let data = defaults.data(forKey: "hotkey"), let hk = try? JSONDecoder().decode(Hotkey.self, from: data),
           hk.isAllowed {
            hotkey = hk
        } else {
            hotkey = .default
        }
        excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? AppSettings.defaultExcluded
        ignoredWords = defaults.stringArray(forKey: "ignoredWords") ?? []
        customThaiWords = defaults.stringArray(forKey: "customThaiWords") ?? []
        learnedWords = defaults.dictionary(forKey: "learnedWords") as? [String: String] ?? [:]
    }
}

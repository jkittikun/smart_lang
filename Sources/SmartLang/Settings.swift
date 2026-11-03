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

    var displayName: String {
        switch self {
        case .doubleTap(let m): return "Double-tap \(m.title)"
        case .combo(_, _, let display): return display
        }
    }
}

/// UserDefaults-backed preferences, observable from SwiftUI.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var autoCorrect: Bool { didSet { defaults.set(autoCorrect, forKey: "autoCorrect") } }
    @Published var switchInputSource: Bool { didSet { defaults.set(switchInputSource, forKey: "switchInputSource") } }
    @Published var playSound: Bool { didSet { defaults.set(playSound, forKey: "playSound") } }
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
    /// Extra Thai words to recognise (the built-in Thai list is small).
    @Published var customThaiWords: [String] { didSet { defaults.set(customThaiWords, forKey: "customThaiWords") } }

    static let defaultExcluded = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess",
    ]

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "enabled": true, "autoCorrect": true, "switchInputSource": true, "playSound": false,
            "sensitivity": Detector.Sensitivity.balanced.rawValue,
            "excludedBundleIDs": AppSettings.defaultExcluded,
        ])
        enabled = defaults.bool(forKey: "enabled")
        autoCorrect = defaults.bool(forKey: "autoCorrect")
        switchInputSource = defaults.bool(forKey: "switchInputSource")
        playSound = defaults.bool(forKey: "playSound")
        sensitivity = Detector.Sensitivity(rawValue: defaults.string(forKey: "sensitivity") ?? "") ?? .balanced
        if let data = defaults.data(forKey: "hotkey"), let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = hk
        } else {
            hotkey = .default
        }
        excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? AppSettings.defaultExcluded
        ignoredWords = defaults.stringArray(forKey: "ignoredWords") ?? []
        customThaiWords = defaults.stringArray(forKey: "customThaiWords") ?? []
    }
}

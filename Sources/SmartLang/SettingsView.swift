import AppKit
import ServiceManagement
import SmartLangCore
import SwiftUI

/// Local UI state for the Settings window.
///
/// This deliberately uses an `ObservableObject` instead of SwiftUI's state
/// property macro: in newer SDKs that macro's plugin ships only with full
/// Xcode, so it fails to build with just the Command Line Tools.
final class SettingsUIState: ObservableObject {
    private let settings: AppSettings
    private var monitor: Any?
    private var updatingLoginItem = false

    @Published var recording = false
    @Published var newBundleID = ""
    @Published var thaiText = ""
    @Published var launchAtLogin: Bool {
        didSet {
            guard !updatingLoginItem, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                updatingLoginItem = true
                launchAtLogin = SMAppService.mainApp.status == .enabled
                updatingLoginItem = false
            }
        }
    }

    init(settings: AppSettings) {
        self.settings = settings
        launchAtLogin = SMAppService.mainApp.status == .enabled
        thaiText = settings.customThaiWords.joined(separator: " ")
    }

    // MARK: Shortcut recording

    func startRecording() {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == UInt16(53) && mods.isEmpty { self.stopRecording(); return nil } // Esc cancels
            // Require ⌘, ⌥ or ⌃ so normal typing never triggers the shortcut.
            guard !mods.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            self.settings.hotkey = .combo(keyCode: event.keyCode, modifiers: UInt64(mods.rawValue),
                                          display: Self.describe(event, mods))
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false }
    }

    private static func describe(_ event: NSEvent, _ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        switch event.keyCode {
        case 49: s += "Space"
        case 36: s += "Return"
        case 48: s += "Tab"
        default: s += (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
        return s
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: SettingsUIState

    var body: some View {
        TabView {
            GeneralTab(settings: settings, ui: ui).tabItem { Text("General") }
            AppsTab(settings: settings, ui: ui).tabItem { Text("Apps") }
            WordsTab(settings: settings, ui: ui).tabItem { Text("Words") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}

// MARK: General

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: SettingsUIState

    var body: some View {
        Form {
            Toggle("Enabled", isOn: $settings.enabled)
            Toggle("Auto-correct words typed in the wrong layout", isOn: $settings.autoCorrect)
            Toggle("Fix while typing (don't wait for Space)", isOn: $settings.fixWhileTyping)
                .disabled(!settings.autoCorrect)
                .padding(.leading, 16)
            Toggle("Switch keyboard layout after fixing a word", isOn: $settings.switchInputSource)
            Toggle("Play a sound when a word is fixed", isOn: $settings.playSound)

            Picker("Auto-correct sensitivity", selection: $settings.sensitivity) {
                Text("Conservative").tag(Detector.Sensitivity.conservative)
                Text("Balanced").tag(Detector.Sensitivity.balanced)
                Text("Aggressive").tag(Detector.Sensitivity.aggressive)
            }

            Divider()

            LabeledContent("Flip shortcut") {
                HStack {
                    Menu(ui.recording ? "Press a shortcut…" : settings.hotkey.displayName) {
                        ForEach(Hotkey.Modifier.allCases, id: \.self) { m in
                            Button("Double-tap \(m.title)") { ui.stopRecording(); settings.hotkey = .doubleTap(m) }
                        }
                        Divider()
                        Button("Record custom shortcut…") { ui.startRecording() }
                    }
                    .frame(width: 220)
                    if ui.recording { Button("Cancel") { ui.stopRecording() } }
                }
            }
            Text("Flips the word you're typing, the last word, or the selected text between Thai and English. Press again to flip back.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Toggle("Launch at login", isOn: $ui.launchAtLogin)

            HStack {
                Text(Permissions.isTrusted ? "✅ Accessibility permission granted" : "⚠️ Accessibility permission needed")
                Spacer()
                if !Permissions.isTrusted {
                    Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                }
            }
        }
        .onDisappear { ui.stopRecording() }
    }
}

// MARK: Apps

private struct AppsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: SettingsUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SmartLang does nothing in these apps:").font(.headline)
            List {
                ForEach(settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        Text(appName(id)).frame(minWidth: 140, alignment: .leading)
                        Text(id).foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button("Remove") { settings.excludedBundleIDs.removeAll { $0 == id } }
                    }
                }
            }
            HStack {
                Menu("Add running app") {
                    ForEach(runningApps(), id: \.self) { id in
                        Button(appName(id)) { add(id) }
                    }
                }
                .frame(width: 180)
                TextField("or bundle ID, e.g. com.apple.Terminal", text: $ui.newBundleID)
                    .onSubmit { add(ui.newBundleID); ui.newBundleID = "" }
                Button("Add") { add(ui.newBundleID); ui.newBundleID = "" }
            }
        }
    }

    private func add(_ id: String) {
        let id = id.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !settings.excludedBundleIDs.contains(id) else { return }
        settings.excludedBundleIDs.append(id)
    }

    private func runningApps() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != Bundle.main.bundleIdentifier && !settings.excludedBundleIDs.contains($0) }
            .sorted()
    }

    private func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

// MARK: Words

private struct WordsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: SettingsUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Never auto-correct (learned when you flip a fix back):").font(.headline)
            List {
                ForEach(settings.ignoredWords, id: \.self) { w in
                    HStack {
                        Text(w)
                        Spacer()
                        Button("Remove") { settings.ignoredWords.removeAll { $0 == w } }
                    }
                }
            }
            .frame(height: 120)

            Text("Extra Thai words to recognise (space or newline separated):").font(.headline)
            TextEditor(text: $ui.thaiText)
                .font(.body)
                .frame(height: 100)
                .border(Color.secondary.opacity(0.3))
            HStack {
                Spacer()
                Button("Save words") {
                    settings.customThaiWords = ui.thaiText
                        .split(whereSeparator: { $0.isWhitespace })
                        .map(String.init)
                }
            }
        }
    }
}

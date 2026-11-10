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
    /// Shown under the recorder when a pressed combo isn't allowed.
    @Published var recordingMessage: String?
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
        recordingMessage = nil
        settings.isRecordingHotkey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Ignore keystrokes SmartLang itself typed (e.g. the ⌘C it uses to read a selection).
            if let cg = event.cgEvent, Synth.isOurs(cg) { return nil }
            let mods = UInt64(event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue)
            if event.keyCode == UInt16(53) && mods == 0 { self.stopRecording(); return nil } // Esc cancels
            if let reason = Hotkey.rejectionReason(keyCode: event.keyCode, modifiers: mods) {
                self.recordingMessage = reason
                NSSound.beep()
                return nil
            }
            self.settings.hotkey = .combo(keyCode: event.keyCode, modifiers: mods,
                                          display: Hotkey.describe(keyCode: event.keyCode, modifiers: mods))
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settings.isRecordingHotkey = false
        if recording { recording = false }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: SettingsUIState

    var body: some View {
        TabView {
            // Pin each tab's content to the top instead of centring it.
            GeneralTab(settings: settings, ui: ui)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tabItem { Text("General") }
            AppsTab(settings: settings, ui: ui)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tabItem { Text("Apps") }
            WordsTab(settings: settings, ui: ui)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tabItem { Text("Words") }
            UpdatesTab(settings: settings, updater: Updater.shared)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tabItem { Text("Updates") }
        }
        .padding(20)
        .frame(width: 560, height: 660)
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
            Toggle("Switch keyboard layout after fixing a word", isOn: $settings.switchInputSource)

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
                        Button("⇧⌫  Shift + Delete") { ui.stopRecording(); settings.hotkey = Hotkey.presets[0] }
                        Button("⇧⌦  Shift + Forward Delete (Fn+Delete)") { ui.stopRecording(); settings.hotkey = Hotkey.presets[1] }
                        Divider()
                        Button("Record custom shortcut…") { ui.startRecording() }
                    }
                    .frame(width: 220)
                    if ui.recording { Button("Cancel") { ui.stopRecording() } }
                }
            }
            if ui.recording {
                Text(ui.recordingMessage ?? "Press the new shortcut, or Esc to cancel.")
                    .font(.caption).foregroundStyle(ui.recordingMessage == nil ? Color.secondary : Color.orange)
            } else if let warning = settings.hotkey.conflictWarning {
                Text("⚠️ " + warning).font(.caption).foregroundStyle(.orange)
            }
            Text("Flips the word you're typing, the last word, or the selected text between Thai and English. Press again to flip back.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            SoundPicker(title: "Sound when a word is fixed", selection: $settings.fixSound)
            SoundPicker(title: "Sound when you flip", selection: $settings.flipSound)
            LabeledContent("Volume") {
                HStack {
                    Slider(value: $settings.soundVolume, in: 0...1, onEditingChanged: { editing in
                        if !editing { Sounds.play(settings.fixSound.isEmpty ? settings.flipSound : settings.fixSound,
                                                  volume: settings.soundVolume) }
                    })
                    .frame(width: 180)
                }
            }
            .disabled(settings.fixSound.isEmpty && settings.flipSound.isEmpty)

            Divider()

            Picker("Menu bar icon", selection: $settings.menuBarIcon) {
                ForEach(StatusIcon.Style.allCases) { style in
                    Label { Text(style.title) } icon: { Image(nsImage: StatusIcon.image(style)) }
                        .tag(style.rawValue)
                }
            }
            Picker("Flash icon when a word is fixed", selection: $settings.flashCount) {
                Text("Off").tag(0)
                Text("Once").tag(1)
                Text("Twice").tag(2)
                Text("Three times").tag(3)
            }
            LabeledContent("Flash length") {
                HStack {
                    Slider(value: $settings.flashDuration, in: 0.05...0.6, onEditingChanged: { editing in
                        if !editing { NotificationCenter.default.post(name: .smartLangPreviewFlash, object: nil) }
                    })
                    .frame(width: 160)
                    Text(String(format: "%.2f s", settings.flashDuration))
                        .monospacedDigit()
                        .frame(width: 52, alignment: .leading)
                    Button("Preview") { NotificationCenter.default.post(name: .smartLangPreviewFlash, object: nil) }
                }
            }
            .disabled(settings.flashCount == 0)

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

private struct SoundPicker: View {
    let title: String
    @Binding var selection: String
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        LabeledContent(title) {
            HStack {
                Picker("", selection: $selection) {
                    Text("None").tag("")
                    ForEach(Sounds.available, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
                Button("▶︎") { Sounds.play(selection, volume: settings.soundVolume) }
                    .disabled(selection.isEmpty)
                    .help("Preview")
            }
        }
    }
}

// MARK: Updates

private struct UpdatesTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            LabeledContent("Installed version") { Text(Updater.currentVersionString).monospacedDigit() }
            Toggle("Check for updates automatically", isOn: $settings.autoCheckForUpdates)
            Text("SmartLang looks for a new release on GitHub about once a day. When there is one, you get a notification and a dot on the menu-bar icon; nothing is installed until you click Install.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            HStack {
                Button("Check Now") { updater.check(userInitiated: true) }
                    .disabled(busy)
                if let version = updater.available?.version {
                    Button("Install \(version.description)…") { updater.showUpdateAlert() }
                        .disabled(busy)
                }
                Spacer()
                Button("Releases Page") { NSWorkspace.shared.open(Updater.releasesPage) }
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            if !settings.skippedUpdateVersion.isEmpty {
                HStack {
                    Text("Skipped version: \(settings.skippedUpdateVersion)").font(.caption)
                    Button("Don't skip") { settings.skippedUpdateVersion = "" }
                }
            }
        }
    }

    private var busy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private var status: String {
        switch updater.state {
        case .checking: return "Checking…"
        case .downloading: return "Downloading the update…"
        case .installing: return "Installing the update…"
        case .available: return "Version \(updater.available?.version?.description ?? "") is available."
        case .upToDate: return "SmartLang is up to date." + lastCheckedText
        case .failed(let message): return message
        case .idle: return lastCheckedText.trimmingCharacters(in: .whitespaces)
        }
    }

    private var lastCheckedText: String {
        guard let date = updater.lastChecked else { return "" }
        return " Last checked " + date.formatted(date: .abbreviated, time: .shortened) + "."
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
            Text("Always auto-correct (learned when you flip a word by hand):").font(.headline)
            List {
                ForEach(settings.learnedWords.sorted { $0.key < $1.key }, id: \.key) { typed, fixed in
                    HStack {
                        Text(typed).foregroundStyle(.secondary)
                        Text("→")
                        Text(fixed)
                        Spacer()
                        Button("Remove") { settings.learnedWords[typed] = nil }
                    }
                }
            }
            .frame(height: 120)

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

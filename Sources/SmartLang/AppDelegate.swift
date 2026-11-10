import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private let updater = Updater.shared
    private var engine: Engine!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var lastActivity = ""
    /// Bumped on every flash so an older, still-running blink can't override a newer one.
    private var flashGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = Engine(settings: settings)
        engine.onActivity = { [weak self] text in
            guard text != "ready" else { return } // tap installed; nothing was fixed
            guard text != "stalled" else { self?.updateIcon(); return }
            self?.lastActivity = text
            self?.flashIcon()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // "Preview" in Settings asks for a flash.
        NotificationCenter.default.addObserver(self, selector: #selector(flashIcon),
                                               name: .smartLangPreviewFlash, object: nil)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.engine.applySettings()
                    self?.updateIcon()
                }
            }
            .store(in: &cancellables)

        // Show a dot on the icon while an update is waiting.
        updater.$available
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateIcon() } }
            .store(in: &cancellables)
        updater.start()

        if !Permissions.isTrusted {
            Permissions.requestAccessibility()
            Permissions.requestInputMonitoring()
        }
        engine.start()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let headerTitle: String
        if engine.isRunning { headerTitle = "SmartLang — Thai ⇄ English" }
        else if engine.stalled { headerTitle = "SmartLang — stopped: its permission changed. Quit and reopen it." }
        else { headerTitle = "SmartLang — waiting for permission" }
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !lastActivity.isEmpty && lastActivity != "ready" {
            let item = NSMenuItem(title: "Last: \(lastActivity)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if let version = updater.available?.version {
            let busy = updater.state == .downloading || updater.state == .installing
            let title = busy ? "Downloading SmartLang \(version)…" : "Update to SmartLang \(version)…"
            let item = NSMenuItem(title: title, action: busy ? nil : #selector(showUpdate), keyEquivalent: "")
            item.target = self
            item.isEnabled = !busy
            menu.addItem(item)
            menu.addItem(.separator())
        }

        menu.addItem(toggle("Enabled", settings.enabled, #selector(toggleEnabled)))
        menu.addItem(toggle("Auto-correct wrong-layout words", settings.autoCorrect, #selector(toggleAuto)))
        let live = toggle("Fix while typing (don't wait for Space)", settings.fixWhileTyping, #selector(toggleLive))
        live.isEnabled = settings.autoCorrect
        menu.addItem(live)
        menu.addItem(toggle("Switch keyboard layout after fixing", settings.switchInputSource, #selector(toggleSwitch)))

        let flip = NSMenuItem(title: "Flip last word / selection  (\(settings.hotkey.displayName))",
                              action: #selector(flipNow), keyEquivalent: "")
        flip.target = self
        menu.addItem(flip)
        menu.addItem(.separator())

        if !Permissions.isTrusted {
            let perm = NSMenuItem(title: "Grant Accessibility permission…", action: #selector(openPermissions), keyEquivalent: "")
            perm.target = self
            menu.addItem(perm)
            let im = NSMenuItem(title: "Grant Input Monitoring permission…", action: #selector(openInputMonitoring), keyEquivalent: "")
            im.target = self
            menu.addItem(im)
            menu.addItem(.separator())
        }

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        menu.addItem(NSMenuItem(title: "Quit SmartLang", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func toggleEnabled() { settings.enabled.toggle() }
    @objc private func toggleAuto() { settings.autoCorrect.toggle() }
    @objc private func toggleLive() { settings.fixWhileTyping.toggle() }
    @objc private func toggleSwitch() { settings.switchInputSource.toggle() }
    @objc private func openPermissions() { Permissions.requestAccessibility(); Permissions.openAccessibilitySettings() }
    @objc private func openInputMonitoring() { Permissions.requestInputMonitoring(); Permissions.openInputMonitoringSettings() }

    @objc private func showUpdate() { updater.showUpdateAlert() }
    @objc private func checkForUpdates() { updater.check(userInitiated: true) }

    @objc private func flipNow() {
        // Give focus back to the previous app before flipping its selection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.engine.flip() }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, ui: SettingsUIState(settings: settings)))
            let window = NSWindow(contentViewController: hosting)
            window.title = "SmartLang Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Icon

    private var iconStyle: StatusIcon.Style {
        StatusIcon.Style(rawValue: settings.menuBarIcon) ?? .diagonal
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.image = StatusIcon.image(iconStyle, badge: updater.available != nil)
        button.imagePosition = .imageOnly
        button.appearsDisabled = !settings.enabled // dimmed while paused
        var tip = "SmartLang — \(settings.enabled ? "on" : "paused")"
        if let version = updater.available?.version { tip += " — version \(version) available" }
        button.toolTip = tip
    }

    /// Blinks the icon in inverted colours when a word is fixed or flipped:
    /// `flashCount` times, each blink inverted for `flashDuration` seconds.
    @objc private func flashIcon() {
        guard let button = statusItem?.button, settings.flashCount > 0 else { return }
        flashGeneration += 1
        let generation = flashGeneration
        let style = iconStyle
        let on = settings.flashDuration
        let gap = max(0.08, on * 0.8)
        var steps: [(TimeInterval, Bool)] = [] // (time from now, inverted?)
        for i in 0..<settings.flashCount {
            let start = Double(i) * (on + gap)
            steps.append((start, true))
            steps.append((start + on, false))
        }
        for (delay, inverted) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.flashGeneration == generation else { return }
                button.image = StatusIcon.image(style, inverted: inverted, badge: self.updater.available != nil)
            }
        }
    }
}

extension Notification.Name {
    static let smartLangPreviewFlash = Notification.Name("SmartLangPreviewFlash")
}

import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private var engine: Engine!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var lastActivity = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = Engine(settings: settings)
        engine.onActivity = { [weak self] text in
            self?.lastActivity = text
            self?.flashIcon()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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

        if !Permissions.isTrusted {
            Permissions.requestAccessibility()
            Permissions.requestInputMonitoring()
        }
        engine.start()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: engine.isRunning ? "SmartLang — Thai ⇄ English" : "SmartLang — waiting for permission",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !lastActivity.isEmpty && lastActivity != "ready" {
            let item = NSMenuItem(title: "Last: \(lastActivity)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(toggle("Enabled", settings.enabled, #selector(toggleEnabled)))
        menu.addItem(toggle("Auto-correct wrong-layout words", settings.autoCorrect, #selector(toggleAuto)))
        let live = toggle("Fix while typing (don't wait for Space)", settings.fixWhileTyping, #selector(toggleLive))
        live.indentationLevel = 1
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

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        button.title = settings.enabled ? "ก⇄A" : "ก/A"
        button.appearsDisabled = !settings.enabled
        button.toolTip = "SmartLang — \(settings.enabled ? "on" : "paused")"
    }

    private func flashIcon() {
        guard let button = statusItem?.button else { return }
        button.title = "✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.updateIcon() }
    }
}

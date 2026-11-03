import AppKit
import ApplicationServices

enum Permissions {
    /// Accessibility lets us read selections and post keystrokes; the event tap
    /// also needs it (macOS lists it under Privacy & Security → Accessibility).
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Input Monitoring (macOS 10.15+) is needed to observe keystrokes.
    static func requestInputMonitoring() {
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

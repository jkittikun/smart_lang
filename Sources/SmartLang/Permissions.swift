import AppKit
import ApplicationServices

enum Permissions {
    /// Accessibility lets us read selections and post keystrokes; the event tap
    /// also needs it (macOS lists it under Privacy & Security → Accessibility).
    ///
    /// `AXIsProcessTrusted()` can keep answering true after the permission is
    /// taken away while SmartLang runs (e.g. `tccutil reset`, or removing it in
    /// System Settings) until SmartLang restarts. Our keyboard tap then stalls
    /// every keystroke system-wide. The window server checks the permission
    /// each time a keyboard tap is created, so also try creating one.
    static var isTrusted: Bool { AXIsProcessTrusted() && canTapKeyboard }

    /// Creates a keyboard event tap and drops it at once. Fails (nil) when
    /// SmartLang may not filter keystrokes.
    private static var canTapKeyboard: Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) }
        guard let probe = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                            options: .defaultTap, eventsOfInterest: mask,
                                            callback: callback, userInfo: nil) else { return false }
        CGEvent.tapEnable(tap: probe, enable: false)
        CFMachPortInvalidate(probe)
        return true
    }

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

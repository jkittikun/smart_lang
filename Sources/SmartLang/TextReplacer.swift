import AppKit
import Carbon
import SmartLangCore

/// Posts synthetic keyboard events. Every event we post carries `marker` in
/// its user-data field so our own event tap can recognise and skip it.
enum Synth {
    static let marker: Int64 = 0x534C_414E_47 // "SLANG"
    private static let source = CGEventSource(stateID: .privateState)
    private static let gap: useconds_t = 1_500 // keeps slower apps (Electron, browsers) in sync

    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    static func key(_ code: UInt16, flags: CGEventFlags = []) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cghidEventTap)
            usleep(gap)
        }
    }

    static func backspace(_ count: Int) {
        for _ in 0..<max(0, count) { key(KeyCodes.delete) }
    }

    /// Types arbitrary text regardless of the active layout.
    static func type(_ text: String) {
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            // Don't split a surrogate pair across events.
            var end = min(i + 16, units.count)
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            var chunk = Array(units[i..<end])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                e.setIntegerValueField(.eventSourceUserData, value: marker)
                e.post(tap: .cghidEventTap)
                usleep(gap)
            }
            i = end
        }
    }

    /// Re-posts a captured event (e.g. the space that ended a word).
    static func repost(_ event: CGEvent, markAsOurs: Bool) {
        guard let copy = event.copy() else { return }
        if markAsOurs { copy.setIntegerValueField(.eventSourceUserData, value: marker) }
        copy.post(tap: .cghidEventTap)
        usleep(gap)
    }

    /// ⌘C, used to read a selection when the Accessibility API can't.
    static func copyShortcut() {
        key(UInt16(kVK_ANSI_C), flags: .maskCommand)
    }
}

/// Reads the selected text in the focused app.
enum Selection {
    static func selectedTextViaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var value: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// Fallback: copy with ⌘C and read the pasteboard, then restore it.
    /// Must be called off the main thread (it waits for the copy to land).
    static func selectedTextViaCopy() -> String? {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        } ?? []
        let before = pb.changeCount
        Synth.copyShortcut()
        var text: String?
        for _ in 0..<20 { // up to ~300 ms
            usleep(15_000)
            if pb.changeCount != before { text = pb.string(forType: .string); break }
        }
        if pb.changeCount != before {
            pb.clearContents()
            let items = saved.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (t, data) in dict { item.setData(data, forType: t) }
                return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
        }
        // Some editors copy the whole line when nothing is selected; that
        // comes back with a trailing newline, so don't treat it as a selection.
        guard let text, !text.isEmpty, !text.hasSuffix("\n") else { return nil }
        return text
    }
}

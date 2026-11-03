import Foundation

/// The language a keyboard layout produces.
public enum Language: String, Codable, CaseIterable, Sendable {
    case english
    case thai

    public var other: Language { self == .english ? .thai : .english }
}

/// One physical key press: the macOS virtual key code plus whether Shift was held.
/// Storing physical keys (not characters) lets us re-render exactly what the
/// user *would* have typed in any other layout.
public struct KeyStroke: Hashable, Codable, Sendable {
    public let keyCode: UInt16
    public let shift: Bool

    public init(keyCode: UInt16, shift: Bool) {
        self.keyCode = keyCode
        self.shift = shift
    }
}

/// macOS virtual key codes (ANSI positions) that produce printable characters,
/// listed row by row in the same order as the layout strings below.
public enum KeyCodes {
    public static let rows: [[UInt16]] = [
        [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24], // ` 1 2 3 4 5 6 7 8 9 0 - =
        [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42], // q w e r t y u i o p [ ] \
        [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],               // a s d f g h j k l ; '
        [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],                 // z x c v b n m , . /
    ]

    /// Every printable key code (plus 10, the ISO "section" key, when present).
    public static let printable: [UInt16] = rows.flatMap { $0 } + [10]

    public static let space: UInt16 = 49
    public static let returnKey: UInt16 = 36
    public static let tab: UInt16 = 48
    public static let keypadEnter: UInt16 = 76
    public static let delete: UInt16 = 51
    public static let forwardDelete: UInt16 = 117
    public static let escape: UInt16 = 53
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126

    /// Keys that end a word and trigger the automatic check.
    public static let boundaries: Set<UInt16> = [space, returnKey, tab, keypadEnter]
}

/// A mapping between physical keystrokes and the characters a layout produces.
public struct KeyLayout: Sendable {
    public let id: String
    public let name: String
    public let language: Language
    public let map: [KeyStroke: String]
    /// Character (single unicode scalar) -> keystroke. Unshifted keys win on duplicates.
    public let reverse: [Unicode.Scalar: KeyStroke]

    public init(id: String, name: String, language: Language, map: [KeyStroke: String]) {
        self.id = id
        self.name = name
        self.language = language
        self.map = map
        var rev: [Unicode.Scalar: KeyStroke] = [:]
        // Insert shifted first so unshifted entries overwrite them.
        for shift in [true, false] {
            for code in KeyCodes.printable {
                let stroke = KeyStroke(keyCode: code, shift: shift)
                guard let s = map[stroke], s.unicodeScalars.count == 1, let scalar = s.unicodeScalars.first else { continue }
                rev[scalar] = stroke
            }
        }
        self.reverse = rev
    }

    /// Builds a layout from four unshifted and four shifted row strings.
    /// Strings are walked by unicode scalar, so combining Thai marks are fine.
    public init(id: String, name: String, language: Language, unshifted: [String], shifted: [String]) {
        precondition(unshifted.count == 4 && shifted.count == 4, "need 4 rows")
        var map: [KeyStroke: String] = [:]
        for (rowIndex, codes) in KeyCodes.rows.enumerated() {
            for (shift, rows) in [(false, unshifted), (true, shifted)] {
                let scalars = Array(rows[rowIndex].unicodeScalars)
                precondition(scalars.count == codes.count,
                             "\(id) row \(rowIndex) shift=\(shift): expected \(codes.count) keys, got \(scalars.count)")
                for (i, code) in codes.enumerated() {
                    map[KeyStroke(keyCode: code, shift: shift)] = String(scalars[i])
                }
            }
        }
        self.init(id: id, name: name, language: language, map: map)
    }

    /// Renders keystrokes as text in this layout. `capsLock` upper-cases Latin letters.
    public func render(_ strokes: [KeyStroke], capsLock: Bool = false) -> String {
        var out = ""
        for stroke in strokes {
            guard var s = map[stroke] else { continue }
            if capsLock && language == .english && !stroke.shift {
                s = s.uppercased()
            }
            out += s
        }
        return out
    }

    /// Keystrokes for `text` in this layout. Characters the layout can't produce
    /// are returned as `nil` entries so callers can pass them through untouched.
    public func strokes(for text: String) -> [KeyStroke?] {
        text.unicodeScalars.map { reverse[$0] }
    }
}

/// Built-in layout tables. At runtime the app prefers tables read from the
/// installed macOS layouts (via UCKeyTranslate); these are the fallback and
/// what the unit tests use.
public enum BuiltinLayouts {
    public static let us = KeyLayout(
        id: "com.apple.keylayout.US", name: "U.S.", language: .english,
        unshifted: ["`1234567890-=", "qwertyuiop[]\\", "asdfghjkl;'", "zxcvbnm,./"],
        shifted: ["~!@#$%^&*()_+", "QWERTYUIOP{}|", "ASDFGHJKL:\"", "ZXCVBNM<>?"]
    )

    /// Thai Kedmanee (TIS 820-2538), macOS "Thai".
    public static let kedmanee = KeyLayout(
        id: "com.apple.keylayout.Thai", name: "Thai (Kedmanee)", language: .thai,
        unshifted: ["_ๅ/-ภถุึคตจขช", "ๆไำพะัีรนยบลฃ", "ฟหกดเ้่าสวง", "ผปแอิืทมใฝ"],
        shifted: ["%+๑๒๓๔ู฿๕๖๗๘๙", "๐\"ฎฑธํ๊ณฯญฐ,ฅ", "ฤฆฏโฌ็๋ษศซ.", "()ฉฮฺ์?ฒฬฦ"]
    )

    /// Thai Pattachote, macOS "Thai - Pattachote".
    public static let pattachote = KeyLayout(
        id: "com.apple.keylayout.Thai-PattaChote", name: "Thai (Pattachote)", language: .thai,
        unshifted: ["_=๒๓๔๕ู๗๘๙๐๑๖", "็ตยอร่ดมวแใฌฺ", "้ทงกัีานเไข", "บปลหิคสะจพ"],
        shifted: ["฿+\"/,?ุ_.()-%", "๊ฤๆญษึฝซถฒฯฦํ", "๋ธำณ์ืผชโฆฑ", "ฎฏฐภัศฮฟฉฬ"]
    )

    public static let all: [KeyLayout] = [us, kedmanee, pattachote]
}

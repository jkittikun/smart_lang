import XCTest
@testable import SmartLangCore

final class LayoutTests: XCTestCase {
    let us = BuiltinLayouts.us
    let ked = BuiltinLayouts.kedmanee
    let pat = BuiltinLayouts.pattachote

    func testTablesAreComplete() {
        for layout in BuiltinLayouts.all {
            XCTAssertEqual(layout.map.count, 47 * 2, layout.id)
        }
    }

    func testKedmaneeConversion() {
        XCTAssertEqual(Converter.convert("l;ylfu", from: us, to: ked), "สวัสดี")
        XCTAssertEqual(Converter.convert("hello", from: us, to: ked), "้ำสสน")
        XCTAssertEqual(Converter.convert("้ำสสน", from: ked, to: us), "hello")
        XCTAssertEqual(Converter.convert("8iy[", from: us, to: ked), "ครับ")
        XCTAssertEqual(Converter.convert("hello world", from: us, to: ked), "้ำสสน ไนพสก")
    }

    func testPattachoteConversion() {
        let typed = Converter.convert("สวัสดี", from: pat, to: us)
        XCTAssertEqual(Converter.convert(typed, from: us, to: pat), "สวัสดี")
    }

    func testRoundTrip() {
        for word in ["hello", "keyboard", "Thank you!", "don't"] {
            for thai in [ked, pat] {
                let there = Converter.convert(word, from: us, to: thai)
                XCTAssertEqual(Converter.convert(there, from: thai, to: us), word, "\(word) via \(thai.id)")
            }
        }
    }

    func testRenderFromKeystrokes() {
        let strokes = us.strokes(for: "l;ylfu").compactMap { $0 }
        XCTAssertEqual(ked.render(strokes), "สวัสดี")
        XCTAssertEqual(us.render(strokes), "l;ylfu")
        XCTAssertEqual(us.render(us.strokes(for: "abc").compactMap { $0 }, capsLock: true), "ABC")
    }

    func testSourceLanguage() {
        XCTAssertEqual(Converter.sourceLanguage(of: "l;ylfu"), .english)
        XCTAssertEqual(Converter.sourceLanguage(of: "้ำสสน"), .thai)
        XCTAssertNil(Converter.sourceLanguage(of: "   "))
    }
}

final class OrthographyTests: XCTestCase {
    func testValidWords() {
        for w in ["สวัสดี", "ครับ", "ก็", "น้ำ", "ศักดิ์", "เกาะ", "ไทย", "ทั้ง", "เป็น"] {
            XCTAssertTrue(ThaiOrthography.check(w).isValid, w)
        }
    }

    func testInvalidShapes() {
        for w in ["้ำสสน", "ะ้ำ", "กิิ", "เ", "ก่่", "ำก", "กั"] {
            XCTAssertFalse(ThaiOrthography.check(w).isValid, w)
        }
    }
}

final class DetectorTests: XCTestCase {
    let d = Detector()
    let us = BuiltinLayouts.us
    let ked = BuiltinLayouts.kedmanee

    private func check(_ typed: String, in from: KeyLayout, to: KeyLayout) -> (Bool, String) {
        let alt = Converter.convert(typed, from: from, to: to)
        let ok = d.shouldCorrect(typed: typed, typedLanguage: from.language, alternative: alt,
                                 keystrokeCount: typed.unicodeScalars.count)
        return (ok, alt)
    }

    func testThaiTypedOnEnglishLayout() {
        for thai in ["สวัสดี", "ครับ", "ขอบคุณ", "ภาษาไทย", "ไม่เป็นไร"] {
            let typed = Converter.convert(thai, from: ked, to: us)
            let (ok, alt) = check(typed, in: us, to: ked)
            XCTAssertTrue(ok, "\(typed) should become \(thai)")
            XCTAssertEqual(alt, thai)
        }
    }

    func testEnglishTypedOnThaiLayout() {
        for english in ["hello", "thanks", "keyboard", "meeting", "tomorrow"] {
            let typed = Converter.convert(english, from: us, to: ked)
            let (ok, alt) = check(typed, in: ked, to: us)
            XCTAssertTrue(ok, "\(typed) should become \(english)")
            XCTAssertEqual(alt, english)
        }
    }

    func testCorrectTextIsLeftAlone() {
        for english in ["hello", "github", "keyboard", "Bangkok", "lol", "1234", "don't"] {
            XCTAssertFalse(check(english, in: us, to: ked).0, english)
        }
        for thai in ["สวัสดี", "ครับ", "ภาษาไทย", "กิน", "ผม"] {
            XCTAssertFalse(check(thai, in: ked, to: us).0, thai)
        }
    }

    func testShortWordsAndIgnoreList() {
        XCTAssertFalse(check("ok", in: us, to: ked).0) // too short to judge
        d.ignored = ["l;ylfu"]
        XCTAssertFalse(check("l;ylfu", in: us, to: ked).0)
        d.ignored = []
    }

    private func live(_ typed: String, in from: KeyLayout, to: KeyLayout, detector: Detector? = nil) -> Bool {
        let det = detector ?? d
        return det.shouldCorrectLive(typed: typed, typedLanguage: from.language,
                                     alternative: Converter.convert(typed, from: from, to: to),
                                     keystrokeCount: typed.unicodeScalars.count)
    }

    func testLiveFixesCompleteWords() {
        XCTAssertTrue(live("l;ylfu", in: us, to: ked))                 // สวัสดี
        XCTAssertTrue(live("้ำสสน", in: ked, to: us))                  // hello
        XCTAssertTrue(live(Converter.convert("ขอบคุณ", from: ked, to: us), in: us, to: ked))
    }

    func testLiveWaitsForAKnownWord() {
        XCTAssertFalse(live("l;yl", in: us, to: ked))   // สวัส – not a word yet
        XCTAssertFalse(live("l;ylf", in: us, to: ked))
        XCTAssertFalse(live("l;y", in: us, to: ked))    // too short
    }

    func testLiveNeverFiresOnCorrectTyping() {
        for word in ["hello", "keyboard", "meeting", "tomorrow", "github", "Bangkok"] {
            for k in 4...word.count {
                let prefix = String(word.prefix(k))
                XCTAssertFalse(live(prefix, in: us, to: ked), prefix)
                XCTAssertFalse(live(prefix, in: us, to: BuiltinLayouts.pattachote), prefix)
            }
        }
        for word in ["สวัสดี", "ขอบคุณ", "ภาษาไทย", "ไม่เป็นไร", "เป็น"] {
            let scalars = Array(word.unicodeScalars)
            guard scalars.count >= 4 else { continue }
            for k in 4...scalars.count {
                let prefix = String(String.UnicodeScalarView(scalars[0..<k]))
                XCTAssertFalse(live(prefix, in: ked, to: us), prefix)
            }
        }
    }

    func testLiveRespectsIgnoredPrefix() {
        let det = Detector()
        det.ignored = ["l;ylfu"]
        XCTAssertFalse(live("l;ylfu", in: us, to: ked, detector: det))
    }

    func testLearnedWordsAreCorrected() {
        let det = Detector(extraEnglishCheck: { _ in false })
        let typed = Converter.convert("สะพาน", from: ked, to: us)
        XCTAssertEqual(typed, "ltrko")
        det.learned = [typed: "สะพาน"]
        XCTAssertTrue(det.shouldCorrect(typed: typed, typedLanguage: .english,
                                        alternative: "สะพาน", keystrokeCount: 5))
        XCTAssertTrue(live(typed, in: us, to: ked, detector: det))
        // Only the exact pair that was learned.
        XCTAssertFalse(det.isLearned(typed: typed, alternative: "สะพา"))
        // Undoing it (ignore list) wins.
        det.ignored = [typed]
        XCTAssertFalse(det.shouldCorrect(typed: typed, typedLanguage: .english,
                                         alternative: "สะพาน", keystrokeCount: 5))
    }

    func testLearnedWordsWaitWhenTheyMayContinue() {
        let det = Detector()
        // A real English word taught to become Thai is fixed at Space, not mid-word.
        det.learned = ["hello": "้ำสสน"]
        XCTAssertFalse(det.shouldCorrectLive(typed: "hello", typedLanguage: .english,
                                             alternative: "้ำสสน", keystrokeCount: 5))
        XCTAssertTrue(det.shouldCorrect(typed: "hello", typedLanguage: .english,
                                        alternative: "้ำสสน", keystrokeCount: 5))
        // Nor when it is the start of another learned word.
        det.learned = ["ltrk": "สะพา", "ltrko": "สะพาน"]
        XCTAssertFalse(det.shouldCorrectLive(typed: "ltrk", typedLanguage: .english,
                                             alternative: "สะพา", keystrokeCount: 4))
        XCTAssertTrue(det.shouldCorrectLive(typed: "ltrko", typedLanguage: .english,
                                            alternative: "สะพาน", keystrokeCount: 5))
    }

    func testExtraDictionaryPenalisesUnknownEnglish() {
        let withDict = Detector(extraEnglishCheck: { _ in false })
        // "dyo" is กัน typed on the US layout; plausible-looking but not a word.
        XCTAssertTrue(withDict.shouldCorrect(typed: "dyo", typedLanguage: .english,
                                             alternative: "กัน", keystrokeCount: 3))
    }
}

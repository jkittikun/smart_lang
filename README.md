# SmartLang — Thai ⇄ English wrong-layout fixer for macOS

Forgot to switch your keyboard? SmartLang is a small menu-bar app that notices
when you typed a word in the wrong layout and fixes it for you:

| You meant | You typed (wrong layout) | SmartLang turns it into |
|-----------|--------------------------|-------------------------|
| สวัสดี    | `l;ylfu` (US layout)     | สวัสดี and switches to Thai |
| hello     | `้ำสสน` (Thai layout)     | hello and switches to English |

It also has a **flip shortcut** (by default, tap **Shift twice**). Use it to
switch a word between Thai and English by hand. Press it again to switch back.

## Features

- **Fix while typing.** As soon as the keys you've typed spell a real word in
  the other language, SmartLang replaces it and switches your input source,
  without waiting for Space. For example, `l;ylfu` becomes `สวัสดี` the moment
  you type the `u`. The rest of the word then comes out in the right language,
  so if you type `hello` on the Thai layout, it's fixed at `hell` and the `o`
  arrives in English. This needs at least 4 keys. You can turn it off in the
  menu or in Settings.
- **Auto-correct when a word ends.** When you press Space, Tab or Return,
  SmartLang checks the word again, using a slightly looser rule. If it clearly
  belongs to the other language, it replaces it and switches your input source.
- **Flip shortcut.** It works on, in this order:
  1. the word you are typing right now,
  2. the word you just finished (including one that was just auto-corrected,
     so you can undo the fix), or
  3. the selected text. You can select a whole sentence and flip it.

  Press the shortcut again to switch back. You can change the shortcut in
  Settings: double-tap Shift, Option, Control or Command, pick a ready-made
  combo (⇧⌫, ⌃⌥Space or F5), or record a key
  combo. A combo needs ⌘, ⌥ or ⌃ (for example ⌃⌥Space), except in two cases:
  Shift alone works with keys that don't type a letter, such as ⇧⌫, ⇧↩ or
  ⇧→; and function keys (F1–F20) work on their own. Settings warns you if a
  combo replaces a common macOS shortcut such as ⌘⌫ or ⌘C.
- **Both Thai layouts.** Works with Thai Kedmanee and Thai Pattachote, plus
  US, ABC or any English layout. SmartLang reads the key tables of the layouts
  you have installed, so its conversions match exactly what macOS would type.
- **Learns from your undo.** If you flip back an auto-correction, that word is
  never auto-corrected again. You can edit this list in Settings → Words.
- **Stays out of the way.** It does nothing in Terminal, iTerm, Warp or password
  managers, or in any other app you add in Settings → Apps. It also can't see
  password fields, because macOS blocks that.
- **Sensitivity**: Conservative, Balanced or Aggressive. It sets how sure
  SmartLang must be before it changes a word automatically. It doesn't affect
  the flip shortcut.
- **Sounds**: choose any macOS alert sound (or none) for automatic fixes and,
  separately, for flips, with a volume slider and a preview button.
- **Launch at login.**

## How it works

SmartLang records the **physical keys** you press, not the characters they
produce. When a word ends, it renders those keys in the other language's layout
and scores both versions:

- **English** uses the macOS spell checker, a built-in word list, and the shape
  of English words: vowels, legal opening consonant clusters, no `;` or `[`
  inside words, and so on.
- **Thai** uses Thai spelling rules and a Thai word list, and splits the text
  into words, because Thai is written without spaces. Examples of the rules: a
  word can't start with a tone mark or vowel mark, two vowel marks can't stack,
  and `ั` must be followed by a final consonant.

SmartLang only replaces the word when the typed version looks like nonsense and
the other version looks like a real word. To replace a word, it sends
Backspaces and then types the new text.

The detection logic lives in `Sources/SmartLangCore` (pure Swift, unit-tested).
The macOS-specific parts live in `Sources/SmartLang`: the event tap, input
sources, typing, and the UI.

## Install

You need macOS 13 or later and the Xcode Command Line Tools
(`xcode-select --install`). Full Xcode isn't required. The build script makes
a version for your Mac's chip. Run `UNIVERSAL=1 ./scripts/build_app.sh` to
build one app that runs on both Apple Silicon and Intel Macs.

```bash
git clone https://github.com/jkittikun/smart_lang.git
```

```bash
cd smart_lang
```

```bash
./scripts/build_app.sh --install
```

```bash
open /Applications/SmartLang.app
```

You can also download `SmartLang.zip` from the **Artifacts** of the latest
**macOS build & test** run on GitHub Actions. Because the app isn't notarized,
the first time you open it, right-click it and choose **Open**.

### Permissions

The first time it runs, macOS asks for two permissions. Grant both in
**System Settings → Privacy & Security**:

- **Accessibility**: lets SmartLang type the correction and read selected text.
- **Input Monitoring**: lets SmartLang see which keys you press.

After you grant them, SmartLang starts working within a couple of seconds. You
don't need to restart it. The menu-bar icon is `ก⇄A`.

> If you rebuild the app, macOS may treat it as a new app. If it stops
> reacting, remove SmartLang from both lists in System Settings and add it
> again.

## Development

```bash
swift test
```

```bash
swift run SmartLang
```

When you use `swift run`, grant the permissions to the Terminal or IDE you
launched it from.

### App icon

`Resources/AppIcon.icns` is generated by `scripts/make_icon.py` (needs
Pillow: `pip3 install pillow`). It draws two keycaps, ก and A, with swap
arrows. On a Mac the script uses the Thonburi font for ก. Edit the script and
re-run it to change the icon:

```bash
python3 scripts/make_icon.py
```

### Built-in word lists

`Sources/SmartLangCore/WordLists.swift` has about 1,000 common English words
and about 500 Thai words. The macOS spell checker covers the rest of English.
For Thai, add words you use often in Settings → Words, or add them to the list.

## Limitations

- Each word is checked on its own. A very short word (fewer than 3 keys, or
  fewer than 4 for fixing while typing) is never auto-corrected, because many
  of them are real words in both languages. For example, `ok` typed on the Thai layout
  is `นา`, a real Thai word. Use the flip shortcut for these.
- After you press Return, the last word can't be flipped. Flipping it would
  mean typing Return again, which might send a chat message twice.
- Some apps with custom text engines, such as certain games and remote
  desktops, may not accept the typed replacement.

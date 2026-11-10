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
  Settings: double-tap Shift, Option, Control or Command, or record a key
  combo. A combo needs ⌘, ⌥ or ⌃ (for example ⌃⌥Space). The exceptions are
  ⇧⌫ and ⇧⌦, which you can pick straight from the menu, and function keys
  (F1–F20), which work on their own. Settings warns you if
  a combo replaces a common macOS shortcut such as ⌘⌫ or ⌘C.
- **Both Thai layouts.** Works with Thai Kedmanee and Thai Pattachote, plus
  US, ABC or any English layout. SmartLang reads the key tables of the layouts
  you have installed, so its conversions match exactly what macOS would type.
- **Learns from your undo.** If you flip back an auto-correction, that word is
  never auto-corrected again. You can edit this list in Settings → Words.
- **Learns from your flips.** If SmartLang missed a word and you flipped it
  yourself (say `ltrko` → `สะพาน`), whether while typing, right after, or by
  selecting it, it remembers, and fixes `ltrko` automatically from then on. Flip it back, or undo the fix, and it forgets.
  You can see and remove learned words in Settings → Words.
- **Stays out of the way.** It does nothing in Terminal, iTerm, Warp or password
  managers, or in any other app you add in Settings → Apps. It also can't see
  password fields, because macOS blocks that.
- **Sensitivity**: Conservative, Balanced or Aggressive. It sets how sure
  SmartLang must be before it changes a word automatically. It doesn't affect
  the flip shortcut.
- **Sounds**: choose any macOS alert sound (or none) for automatic fixes and,
  separately, for flips, with a volume slider and a preview button.
- **Launch at login.**
- **Updates itself.** About once a day SmartLang checks GitHub for a new
  release. When there is one, you get a notification and a dot on the
  menu-bar icon; choose **Update to SmartLang x.y.z…** in the menu to see
  what's new and install it. See [Updates](#updates).

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

You can also download `SmartLang-x.y.z.dmg` from the
[Releases](https://github.com/jkittikun/smart_lang/releases) page: open it and
drag SmartLang onto Applications. Because the app isn't notarized, macOS says
"Apple could not verify SmartLang.app is free of malware" the first time you
open it. Click **Done**, then open **System Settings → Privacy & Security**,
scroll down to Security and click **Open Anyway** next to SmartLang. (On macOS
15 and later, right-click → Open no longer skips this check.) Or, in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/SmartLang.app
```

### Permissions

The first time it runs, macOS asks for two permissions. Grant both in
**System Settings → Privacy & Security**:

- **Accessibility**: lets SmartLang type the correction and read selected text.
- **Input Monitoring**: lets SmartLang see which keys you press.

After you grant them, SmartLang starts working within a couple of seconds. You
don't need to restart it. The menu-bar icon shows a small ก and A with two arrows; it blinks when a word is fixed or flipped. You can change the icon style and how it blinks (off, once, twice or three times, and for how long) in Settings → General.

> If you rebuild the app and it isn't signed with the
> [SmartLang Signing certificate](#signing), macOS treats it as a new app.
> If it stops reacting, remove SmartLang from both lists in System Settings
> and add it again.

### Updates

SmartLang checks the [Releases](https://github.com/jkittikun/smart_lang/releases)
page shortly after it starts and then about once a day. Turn this off, check
by hand or un-skip a version in **Settings → Updates** (or use **Check for
Updates…** in the menu). When a new version is out:

1. A notification says so, and the menu-bar icon gets a small dot. Nothing is
   downloaded yet.
2. Click the notification, or choose **Update to SmartLang x.y.z…** in the
   menu. You see what's new and can pick **Install and Relaunch**, **Later**
   or **Skip This Version**.
3. SmartLang downloads the `.zip` from the release and checks it. The SHA-256
   must match the published `.sha256` file, the bundle ID and version must be
   right, and the new app must be signed with the same certificate as the one
   you're running. Then it replaces `/Applications/SmartLang.app` and restarts.

You don't need to run `xattr` or click **Open Anyway** again. macOS only
quarantines files that a browser downloads, and SmartLang downloads the
update itself. You also don't need to grant the permissions again, as long
as both versions are signed with the same certificate (see [Signing](#signing)).
The first time, macOS may ask whether SmartLang may update apps
(**Privacy & Security → App Management**). Allow it.

Updating in place needs SmartLang to be in a folder you can write to, such as
`/Applications` on an admin account. If it can't, it shows an error and you
can install the new version by hand from the Releases page.

## Development

```bash
swift test
```

```bash
swift run SmartLang
```

When you use `swift run`, grant the permissions to the Terminal or IDE you
launched it from.

### Making a release

On GitHub, open **Actions → Release → Run workflow** and enter a version such
as `1.0.1`. The workflow runs the tests, builds a universal app, tags the
commit `v1.0.1`, and publishes a release with `SmartLang-1.0.1.dmg` and
`SmartLang-1.0.1.zip` attached. Running it again for an existing version adds
any missing files to that release.

To make the disk image on your own Mac, run `./scripts/make_dmg.sh 1.0.1`
after `./scripts/build_app.sh`.

The in-app updater installs the newest release that isn't a pre-release, if
it has `SmartLang-x.y.z.zip` and `SmartLang-x.y.z.zip.sha256` attached (the
workflow attaches both). Pre-releases are never offered as updates.

### Signing

macOS remembers the Accessibility and Input Monitoring permissions by the
certificate an app is signed with. With the default ad-hoc signature, every
build counts as a new app, so the permissions must be granted again after
each update. A self-signed certificate fixes this for free. (It doesn't
remove the "could not verify" warning on the very first install. Only an
Apple Developer ID with notarization does that.)

Set it up once, on your Mac:

```bash
./scripts/make_signing_cert.sh
```

The script creates the **SmartLang Signing** certificate and adds it to your
login keychain. It also saves a backup in `~/SmartLang-signing`. Keep that
folder safe and never commit it. The script then prints two values. Add them
on GitHub as repository secrets, under **Settings → Secrets and variables →
Actions**:

- `SMARTLANG_CERT_P12`: the certificate as base64 (the script copies it to
  the clipboard)
- `SMARTLANG_CERT_PASSWORD`: its password

From then on, `./scripts/build_app.sh` and the Release workflow both sign
with this certificate. If the secrets are missing, the workflow signs ad hoc
and shows a warning. The updater won't install a release signed with a
different certificate than the running app, so always sign with the same one.

The first release signed with the certificate still needs the permissions
granted once more, because the old ad-hoc build had a different identity.

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

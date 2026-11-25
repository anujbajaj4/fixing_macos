# MC Close

Control windows right from **Mission Control** on your Mac. Open Mission Control and point at a window:
four buttons appear on its corner.

| Button | Does | Shortcut |
|---|---|---|
| ✕ | Close the window | ⌘W |
| − | Minimize it | ⌘M |
| ⤢ | Full screen (its own space) | ⌃⌘F |
| + | Zoom: fill the screen in place, like Option-clicking the green button. Again to restore. | ⌥⌘F |
| | Hide the app | ⌘H |
| | Quit the app | ⌘Q |

Shortcuts only act while Mission Control is open and the pointer is on a window. Everywhere else, your keys
work as usual.

MC Close is a small menu-bar app. It's free, needs no Apple Developer account, and works on
macOS 13 (Ventura) or later, on both Apple silicon and Intel Macs.

## Install

Paste this into Terminal:

```bash
curl -fsSL https://anujbajaj4.github.io/fixing_macos/install.sh | bash
```

It downloads the app from the latest release, puts it in Applications and opens it. No password needed.
If your network can't reach GitHub's download server, it uses the mirror on GitHub Pages instead.
The same installer is also attached to each release:
`curl -fsSL https://github.com/anujbajaj4/fixing_macos/releases/latest/download/install.sh | bash`
Then, in the window that opens, click **Open Accessibility Settings** and switch **MC Close** on.

Prefer to download? Get **MCClose.dmg** from the [latest release](https://github.com/anujbajaj4/fixing_macos/releases/latest)
and drag MC Close to Applications. macOS will say it "could not verify" the app because it isn't
notarized by Apple: click **Done**, then System Settings ▸ Privacy & Security ▸ **Open Anyway**.

## How it works

| Part | File | What it does |
|---|---|---|
| Spotting Mission Control | `Sources/MCClose/MissionControlWatcher.swift` | The Dock draws Mission Control and posts accessibility notifications when it opens and closes. MC Close listens for them and does nothing in between. |
| Finding the window | `Sources/MCClose/WindowCloser.swift`, `Sources/Core/Core.swift` | Asks the Dock for Mission Control's window thumbnails (macOS's "what's under the pointer" sees through them), reads the title of the one under the pointer and finds the one real window with that title. Two windows with the same title: it does nothing rather than guess. |
| Shortcuts and clicks | `Sources/MCClose/KeyTap.swift` | An event tap that, only while Mission Control is open, handles the shortcuts when the pointer is on a window, and catches clicks on the buttons (Mission Control would otherwise take them). Everything else passes through. |
| Buttons | `Sources/MCClose/WindowButtonsOverlay.swift` | Close, minimize, full screen and zoom, floating on the corner of the thumbnail under the pointer. |
| Acting on the window | `Sources/MCClose/WindowCloser.swift` | Presses the window's own buttons, sets minimized/full screen, resizes for zoom, or hides/quits the app. |
| Menu, welcome window, updates | `Sources/MCClose/MCCloseApp.swift` | Menu-bar icon, first-run setup, Start at Login, a once-a-month update check against GitHub releases. |

Privacy: MC Close needs Accessibility permission to see Mission Control and press close buttons.
It contacts nothing except GitHub, once a month, to check for a new version, and sends nothing about you.

## If something doesn't work

Open the log from the menu (**Open Log**), or in Terminal:

```bash
tail -30 ~/Library/Logs/MCClose.log
```

The log records what the Dock reported and what MC Close found under the pointer. Window titles are
left out (shown as `<12 chars>`). To include them while you debug, run this, then quit and reopen MC Close:

```bash
defaults write io.github.anujbajaj4.MCClose VerboseLog -bool YES
```

- **Nothing happens after an update or rebuild.** Each build has a new signature, so macOS's old
  permission no longer applies. Choose **Set Up… ▸ Reset Permission** in the menu and switch MC Close on again.
- **No "Dock says AXExposeShowAllWindows" lines when you open Mission Control.** Your macOS version
  doesn't send these notifications, so MC Close can't tell when Mission Control is open.
- **"pointer … is not on any of the 0 window thumbnails".** This macOS shows Mission Control's
  thumbnails differently from macOS 15. Open Accessibility Inspector (Xcode ▸ Open Developer Tool),
  open Mission Control and look at what the Dock shows.
- **"no unique window found".** The thumbnail's title didn't match exactly one window. With verbose
  logging on, the log shows both titles.
- **The buttons never appear but the shortcuts work.** You can switch the buttons off with
  **Show Window Buttons** in the menu and keep using the shortcuts.
- **A window with unsaved changes doesn't close.** The app's "Save changes?" sheet is waiting for you.

## Build it yourself

You need a Mac with the Command Line Tools (`xcode-select --install`). Xcode itself isn't required.

```bash
scripts/build.sh --test
```

This runs the logic tests, then makes `build/MCClose.app` and `build/MCClose.dmg` (universal, ad-hoc signed).
To install your build the same way users do:

```bash
MCCLOSE_DMG_URL="file://$PWD/build/MCClose.dmg" bash < install.sh
```

The installer tests run anywhere, Linux included: `bash Tests/install_test.sh`.

## Releasing

1. Bump `VERSION` and update `.github/release-notes.md`.
2. Run the **Release** workflow from the Actions tab. It tests, builds, and publishes `v<VERSION>` with
   `MCClose.dmg` and `install.sh` attached, then refreshes the download page and mirror on GitHub Pages
   (one-time setup: Settings ▸ Pages ▸ Source: **GitHub Actions**). Installed copies will offer the update within a month,
   or straight away from **Check for Updates**.

## Uninstall

Quit MC Close from its menu, then:

```bash
rm -rf /Applications/MCClose.app ~/Library/Logs/MCClose*.log
```

```bash
tccutil reset Accessibility io.github.anujbajaj4.MCClose
```

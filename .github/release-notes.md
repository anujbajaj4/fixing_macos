Control any window right from Mission Control: point at it, then use the buttons on its corner or a shortcut.

## What's new in 1.1.0
- **Four buttons on the window you point at:** close, minimize, full screen, and zoom (+). Zoom does what Option-clicking the green button does: the window fills the screen in place, without a separate full-screen space. Zoom again to put it back.
- **Shortcuts in Mission Control:** ⌘W close · ⌘M minimize · ⌃⌘F full screen · ⌥⌘F zoom · ⌘H hide the app · ⌘Q quit the app. They only act when the pointer is on a window, so everywhere else your keys work as usual.
- **Works when macOS doesn't announce Mission Control:** on some macOS versions (seen on macOS 27) the Dock no longer says when Mission Control opens, so 1.0.0 never showed its button. MC Close now also recognises Mission Control from the Dock's layout.
- **Diagnose Mission Control…** in the menu records what your Mac shows in Mission Control, so any remaining problem can be fixed from evidence.
- **Downloads that don't hang:** if your network can't reach GitHub's download server, the installer switches to a mirror after 10 seconds.
- **Safer:** pointing at a Dock icon in Mission Control no longer counts as pointing at a window.
- Every button and shortcut is tested on a real Mac in Mission Control before each release.

## Install or update
Paste this into Terminal (no password needed):

```
curl -fsSL https://anujbajaj4.github.io/fixing_macos/install.sh | bash
```

Already have MC Close? It offers the update itself within a month, or choose **Check for Updates** in its menu. After updating, macOS asks for Accessibility again: switch MC Close on once more.

Or download **MCClose.dmg** below and drag MC Close to Applications. Because the app isn't notarized by Apple, macOS will say it "could not verify" it: click **Done**, then System Settings ▸ Privacy & Security ▸ **Open Anyway**. The Terminal command avoids this.

Needs macOS 13 (Ventura) or later. Works on Apple silicon and Intel Macs.

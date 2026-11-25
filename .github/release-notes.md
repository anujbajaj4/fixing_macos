Control any window right from Mission Control: point at it, then use the buttons on its corner or a shortcut.

## What's new in 1.1.1
- **No more lag, ever, from MC Close.** MC Close now only listens to the keyboard and mouse while Mission Control is open; the rest of the time it isn't in the path at all. In 1.0.0, updating could leave the old copy stalled in that path for minutes, which slowed down every click and key press. Updating now switches that off and quits the old copy before installing the new one, and the Update button only runs once.
- **Better diagnosis for new macOS versions.** On macOS 27 Mission Control isn't drawn by the Dock any more, so MC Close can't see it yet. **Diagnose Mission Control…** now records which part of macOS draws it, so the next version can support it.
- Updating no longer fills the log with "event tap was disabled" lines from the old copy.

## In 1.1.0
- **Four buttons on the window you point at:** close, minimize, full screen, and zoom (+). Zoom does what Option-clicking the green button does: the window fills the screen in place, without a separate full-screen space. Zoom again to put it back.
- **Shortcuts in Mission Control:** ⌘W close · ⌘M minimize · ⌃⌘F full screen · ⌥⌘F zoom · ⌘H hide the app · ⌘Q quit the app. They only act when the pointer is on a window, so everywhere else your keys work as usual.
- Recognises Mission Control from the Dock's layout when the Dock doesn't announce it, and a mirror for downloads.

## Install or update
Paste this into Terminal (no password needed):

```
curl -fsSL https://anujbajaj4.github.io/fixing_macos/install.sh | bash
```

Already have MC Close? It offers the update itself within a month, or choose **Check for Updates** in its menu. After updating, macOS asks for Accessibility again: switch MC Close on once more.

Or download **MCClose.dmg** below and drag MC Close to Applications. Because the app isn't notarized by Apple, macOS will say it "could not verify" it: click **Done**, then System Settings ▸ Privacy & Security ▸ **Open Anyway**. The Terminal command avoids this.

Needs macOS 13 (Ventura) or later. Works on Apple silicon and Intel Macs.

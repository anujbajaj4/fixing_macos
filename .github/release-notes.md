Control any window right from Mission Control: point at it, then use the buttons on its corner or a shortcut.

## What's new in 1.3.1
- **No more stray buttons.** On macOS 27, Mission Control also lists things that aren't drawn as windows (invisible helper windows, placeholders behind real windows), and 1.3.0 put buttons on them too. Buttons now only appear on thumbnails that match one real, visible window MC Close can act on.

## In 1.3.0
- **Buttons on every window, where they belong.** When Mission Control opens, each window gets its own controls in the top-left corner of its title bar, in Apple's red, yellow and green (plus a graphite + for zoom), on a small frosted pill, instead of one set following the pointer. Like on a real window, the symbols appear when you point at the buttons, and holding Option turns green into +. Narrow windows get smaller buttons that fit.
- The buttons fade in once Mission Control has settled and follow the layout as windows close or move. Clicking anywhere else on a window still picks it, as usual.

## In 1.2.0
- **Works on macOS 27.** Apple moved Mission Control out of the Dock into a part of macOS called WindowManager, and stopped announcing when it opens, so earlier versions never showed their buttons there. MC Close now finds Mission Control and its windows in WindowManager (and still in the Dock on older macOS).
- **Picks the right window more reliably on macOS 27,** which tells MC Close which app each window belongs to.
- **No more lag, ever, from MC Close.** It only listens to the keyboard and mouse while Mission Control is open; the rest of the time it isn't in the path at all. In 1.0.0, updating could leave the old copy stalled in that path for minutes, slowing every click and key press. Updating now switches that off and quits the old copy first, and the Update button only runs once.
- **Diagnose Mission Control…** records far more (which part of macOS draws Mission Control, and what's under the pointer), still without window titles.

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

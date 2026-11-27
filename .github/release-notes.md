Control any window right from Mission Control: point at it, then use the buttons on its corner or a shortcut.

## What's new in 1.4.1
- **Buttons in the right place, on the right window.** On macOS 27 a few windows got no buttons (Preview) or buttons in the wrong spot (Finder). MC Close now prefers the window whose title fits best over helper windows named after the app, refuses a match whose shape doesn't agree with its thumbnail, and uses the standard corner if a measurement looks wrong.
- The log now says, for each window in Mission Control, what MC Close matched and where it put the buttons (window titles stay hidden), so any remaining glitch can be fixed from one log.

## In 1.4.0
- **Buttons that work on more windows.** Some windows on macOS 27 (seen with Preview) are labelled slightly differently in Mission Control, so their buttons did nothing. MC Close now compares titles more loosely and, within an app, uses the window's shape to find the right one. It still does nothing if it isn't sure.
- **Updates keep your Accessibility permission.** From this version on, every release is signed with the same certificate, so macOS recognises updates as the same app. (Updating to 1.4.0 itself asks once more.)
- **Buttons ride with the windows.** As Mission Control opens, each window's buttons travel from its real controls to its thumbnail; as it closes, they travel back and fade. Turn this off in Settings ("Move buttons with the windows"); MC Close also follows Reduce motion.
- **Choose your buttons.** In Settings ▸ Buttons, tick the ones you want and drag them into any order: Close, Minimize, Full Screen, Zoom, and now also Hide App and Quit App.
- **Settings window** (⌘, from the menu): button colours with a preview, buttons on or off, each shortcut on or off, and Start at Login.
- **Snappier:** MC Close now reads Mission Control in the background, so your keyboard and mouse never wait for it.
- **Buttons that look like the window's own.** MC Close now finds where each window's real controls are and draws its buttons exactly over their miniature in Mission Control, at the same size, with zoom (+) as a fourth control after green. No extra background.
- **Button colours to match your Mac.** Choose **Button Colours** in the menu: Match System (the default), Multicolor, Graphite, Blue, Purple, Pink, Red, Orange, Yellow or Green, like the accent colours in System Settings ▸ Appearance. On a Mac set to Graphite, Match System draws grey buttons, as macOS does.
- **No more stray buttons** on things in Mission Control that aren't windows.

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

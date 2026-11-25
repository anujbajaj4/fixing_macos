Close windows right from Mission Control: point at a window and click the ✕ on its corner, or press ⌘W.

## What's in 1.0.0
- A ✕ button on the window under the pointer while Mission Control is open.
- ⌘W closes the window under the pointer, only while Mission Control is open. Everywhere else ⌘W works as usual.
- If two windows have the same title, MC Close does nothing rather than risk closing the wrong one.
- A welcome window walks you through the Accessibility permission, plus Start at Login.
- Checks GitHub for a new version once a month (it sends nothing about you).

## Install
Paste this into Terminal (no password needed):

```
curl -fsSL https://github.com/anujbajaj4/fixing_macos/releases/latest/download/install.sh | bash
```

Or download **MCClose.dmg** below and drag MC Close to Applications. Because the app isn't notarized by Apple, macOS will say it "could not verify" it: click **Done**, then System Settings ▸ Privacy & Security ▸ **Open Anyway**. The Terminal command avoids this.

Needs macOS 13 (Ventura) or later. Works on Apple silicon and Intel Macs.

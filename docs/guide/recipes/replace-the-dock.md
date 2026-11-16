---
title: Use Nexus instead of the Dock
summary: Hide the macOS Dock while Nexus runs, and get it back exactly as it was.
---

Dock Replacement hides the macOS Dock while Nexus runs. Nothing is removed, and the Dock returns when Nexus quits.

## When to use it

- You want Nexus to be your only dock.
- You want the Dock back after a crash.

## How to use it

### Turn it on

1. Click the Nexus icon in the menu bar and choose **Settings…**.
2. Open the **Dock** tab.
3. Next to **Nexus is**, choose **My Dock**.

### What changes

Nexus saves your Dock settings first, then changes four of them: auto-hide, the auto-hide delay, the auto-hide speed and the Dock's edge. The Dock keeps running, so Mission Control and Spaces work as before. The **Dock** tab shows **macOS Dock** as **Hidden by Nexus** or **Visible**.

### Get the Dock back

Quitting Nexus puts the Dock back as you had it. If it is still hidden, for example after a crash, try these in order.

1. Open Nexus again. It notices and restores the Dock on launch.
2. Choose **Restore macOS Dock** in the menu-bar icon menu, or in Settings › **Dock**.
3. Press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>D</kbd>. macOS handles this itself.
4. As a last resort, paste this into Terminal:

```
defaults delete com.apple.dock autohide-delay
defaults delete com.apple.dock autohide-time-modifier
defaults write com.apple.dock autohide -bool false
killall Dock
```

To go back to a sidebar next to the Dock, choose **A sidebar** next to **Nexus is**.

## What it will not do

- It does not remove or patch the Dock or any system file.
- It does not touch your settings other than the four above.

## Next steps

- [Position and displays](../bar/position-and-displays.md)
- [Troubleshooting](../reference/troubleshooting.md)
- [Settings](../reference/settings.md)

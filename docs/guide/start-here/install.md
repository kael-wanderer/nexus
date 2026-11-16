---
title: Install Nexus
summary: Drag Nexus to Applications, open it past the first-launch warning, and keep it updated.
---

Nexus comes as a disk image (DMG). Drag it to Applications, then open it the first time with a right-click.

## When to use it

- You have just downloaded Nexus.
- macOS says it cannot open Nexus.
- You want to update or remove Nexus.

## How to use it

### Requirements

- macOS 14 or later.
- A Mac with Apple silicon.

### Install

1. Open the DMG you downloaded.
2. Drag **Nexus** onto the **Applications** shortcut in the window.
3. Eject the disk image.

### Open it the first time

Nexus is not notarised by Apple, so macOS blocks the first launch. You only do this once.

1. Open **Applications** in Finder.
2. Right-click **Nexus** and choose **Open**.
3. Click **Open** in the dialog that appears.

If you double-clicked first and only saw a warning, use one of these instead.

- Open System Settings, go to **Privacy & Security**, scroll down and click **Open Anyway** next to the Nexus message.
- Or run this in Terminal:

```
xattr -dr com.apple.quarantine /Applications/Nexus.app
```

### Launch at login

1. Click the Nexus icon in the menu bar and choose **Settings…**.
2. In **General**, turn on **Launch Nexus at login**.
3. If macOS asks, approve Nexus in System Settings › General › Login Items.

Move Nexus to Applications first. Otherwise Settings says login would start it from wherever it is now.

### Update

Nexus does not update itself. Download the new DMG, quit Nexus, and drag the new Nexus into Applications, replacing the old one. Your settings are kept.

### Uninstall

1. Choose **Quit Nexus** from the menu-bar icon.
2. Drag Nexus from Applications to the Trash.

If you used Nexus instead of the Dock, the Dock comes back on its own when Nexus quits.

## What it will not do

- It does not install anything outside the Nexus app and its settings.
- It does not check for updates.

## Next steps

- [Your first five minutes](first-five-minutes.md)
- [Troubleshooting](../reference/troubleshooting.md)
- [Use Nexus instead of the Dock](../recipes/replace-the-dock.md)

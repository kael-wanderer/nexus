---
title: Troubleshooting
summary: Permissions that will not stick, a missing Dock, a hidden bar, and answers to common questions.
---

Answers to the problems people hit most often.

## When to use it

- Something in Nexus is not working as this guide says.

## How to use it

### I granted Accessibility but Nexus still says it is denied

macOS only hands out Accessibility when a program starts. Click **Restart Nexus** on the permission screen (Settings › **Permissions**). Also make sure Nexus runs from the Applications folder, not from the disk image.

### macOS will not open Nexus the first time

Nexus is not notarised. Right-click it in Applications and choose **Open**. See [Install Nexus](../start-here/install.md) for the other ways.

### The Dock is missing after Nexus crashed

Open Nexus again, or choose **Restore macOS Dock** in Settings › **Dock** or the menu-bar menu. <kbd>⌥</kbd><kbd>⌘</kbd><kbd>D</kbd> also toggles it. See [Use Nexus instead of the Dock](../recipes/replace-the-dock.md).

### The bar disappears over a full-screen app

That is the **Hide over full-screen apps** setting in Settings › **Bar**, and it matches how the Dock behaves. Turn it off to keep the bar visible. Only the display with the full-screen window loses its bar.

### A shortcut does nothing

Another app may use the same keys. Open Settings › **Shortcuts** and record a different one. Also check that **Enable the global shortcut** is on in Settings › **General**.

### Windows have no thumbnails

Thumbnails need Screen Recording, which is optional. Grant it in Settings › **Permissions**. Window names and switching only need Accessibility.

### A folder stack says it cannot read the folder

macOS asks before an app reads Desktop, Documents or Downloads. Allow it when the prompt appears, or in System Settings › Privacy & Security › Files and Folders.

### The menu-bar icon is gone

Turn on **Show Nexus in the menu bar** in Settings › **General**.

### Check for Updates says Retry

Nexus could not reach kael.io.vn, or the site did not answer. The line under the button says which. Check your connection and click **Retry**. A failed check never reports **Up to Date**, so you are not told you are current when Nexus could not find out.

## What it will not do

- Nexus does not fix permissions for you. Only macOS can grant them.

## Next steps

- [Privacy and permissions](privacy-and-permissions.md)
- [Settings](settings.md)
- [Keyboard shortcuts](keyboard-shortcuts.md)

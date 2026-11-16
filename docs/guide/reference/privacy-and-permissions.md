---
title: Privacy and permissions
summary: No account and no telemetry. Which permission each feature needs, and what works without it.
---

Nexus has no account and no analytics. The only thing it asks the internet is whether a newer version exists, and you can switch that off.

## What goes online
- **The update check.** On launch and once a day, Nexus fetches one small file from kael.io.vn that names the newest version. The request carries nothing about you or your Mac: no account, no identifier, no cookies, no list of apps. Like any web request, the server sees your IP address.
- To stop it, switch off Settings › **About** › **Check for updates automatically**. **Check Now** in the same place still works when you ask.
- **Guide links** in Settings, the menu-bar menu and setup open pages of this guide in your browser. Nexus itself fetches nothing for them.

## What is stored
- **Settings, pinned apps, groups and folders** are stored on this Mac in macOS preferences (UserDefaults).
- **Search history** is a count and a last-used time for results you ran, so the palette can rank them. Nexus keeps the last 500 and forgets the oldest first.
- Nothing is uploaded, and there is no analytics. The update check only downloads.
- File search uses the Spotlight index already on your Mac.

## Permissions
Nexus never asks for a permission at launch and never asks again after you refuse. It asks only when you use a feature that needs one.

| Permission | Needed for | Without it |
|---|---|---|
| **Accessibility** | Listing an app's windows, reading titles, bringing a window forward, window search, the window switcher, **Keep windows off Nexus** | Pinned apps, launching, quitting, window counts, and search for apps, files and actions still work. |
| **Screen Recording** (optional) | Small pictures of each window | Window lists show titles only, and switcher cards show the app icon. |
| **Automation** (macOS asks per app, on first use) | Empty Trash in Finder, the Start menu's Sleep, Restart, Shut Down and Log Out, and the timeline of Music, Spotify and VLC | That one action does nothing. Everything else works. |
| File access | Reading Desktop, Documents or Downloads in a folder stack | macOS asks the first time. If you refuse, the stack says it cannot read the folder. |

## How to use it
### Grant a permission
1. Open Settings ▸ **Permissions**.
2. Click **Open System Settings** under the permission.
3. Switch Nexus on in the list.
4. If Nexus still says **Not granted**, click **Restart Nexus**. macOS only hands out these permissions when an app starts.

### Revoke a permission
1. Open System Settings ▸ Privacy & Security.
2. Choose Accessibility, Screen Recording or Automation.
3. Switch Nexus off.

## What it will not do
- It does not ask for Full Disk Access. The Trash is counted without it.
- It does not read window contents unless Screen Recording is on, and then only to draw thumbnails on this Mac.

## Next steps
- [What is Nexus?](../start-here/what-is-nexus.md)
- [Install Nexus](../start-here/install.md)
- [Troubleshooting](troubleshooting.md)
- [Settings](settings.md)

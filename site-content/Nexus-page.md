# Nexus — product page copy

Source of truth: `page_data.py`. Rebuild and re-check with `python3 site-content/build.py`.
Counts are characters; the figure after the slash is the admin's limit.

## Catalog fields

- **Name:** Nexus
- **Pronunciation:** — (left blank; see questions)
- **Summary / tagline:** A vertical dock and a search palette for macOS in one menu-bar app. Pin and group apps, see every window, and find apps, windows and files from one shortcut.  `(157/200)`
- **Details:** Nexus replaces the macOS Dock with a bar on any screen edge and adds a search palette. The bar holds your apps, groups, folders, the Trash, a clock and a volume control. Hover an app to see its windows, or press ⌃⌥W to see every window on the Mac at once. The palette (⌥Space) searches apps, open windows, files and System Settings panes. It all runs locally: no account, no network, and your Dock settings are put back exactly when Nexus quits.  `(445, target 300–600)`
- **Category:** Utilities
- **Tags:** dock, launcher, window switcher, search, menu bar, productivity
- **Platform / OS:** macOS
- **License:** MIT
- **Requirements:** macOS 14 Sonoma or later · Apple Silicon  `(40/80)`
- **Accent colour:** `#8A5A1C` — a darker shade of the icon's gold star (#E1AD66) (white text on it: 5.9:1)

## Screenshots

All 2880 × 1800 px PNG (1440 × 900 pt at 2×), in `screenshots/`.

| File | Label |
|---|---|
| `01-hero.png` | The bar on the right edge, an app's windows on hover  `(52/60)` |
| `02-search.png` | Search palette: windows and files for one query  `(47/60)` |
| `03-window-switcher.png` | Window switcher filtered to one app, two cards selected  `(55/60)` |
| `04-groups.png` | A group of developer tools opened from the bar  `(46/60)` |
| `05-folder-stack.png` | A project folder opened as a stack from the bar  `(47/60)` |
| `06-settings.png` | Settings, Bar tab: what the bar shows  `(37/60)` |
| `07-bottom-edge.png` | The bar on the bottom edge, with window previews  `(48/60)` |

## Feature sections

### 1. What it is — `split`, background `plain`, side `right`

- **Kicker:** What it is  `(10/40)`
- **Title:** A dock that knows about your windows  `(36/70)`
- **Description:** Nexus puts a bar on the edge of your screen with your apps, groups and folders, and opens a search palette from one shortcut. It runs from the menu bar, never takes focus from what you are typing, and changes no system setting unless you ask it to.  `(248/320)`
- **Bullets:**
  1. Pin, reorder, group and launch apps; running apps show a dot and a window count  `(79/120)`
  2. Hover an app to see its windows as thumbnails, then click one to bring it forward  `(81/120)`
  3. The Trash, a clock with a month calendar and a volume control sit at the end of the bar  `(87/120)`
  4. Optionally hide the macOS Dock while Nexus runs; it comes back exactly as it was on quit  `(88/120)`
  5. VoiceOver labels on every element; Reduce Motion and Increase Contrast are respected  `(84/120)`
- **Media:** `01-hero.png`

### 2. Find anything — `showcase`, background `tint`

- **Kicker:** Find anything  `(13/40)`
- **Title:** Get to any app, window or file  `(30/70)`
- **Description:** A search palette, a grid of every open window, and groups and folders kept on the bar. Each is one shortcut or one click away.  `(126/320)`
- **Tiles:**
  1. **Search palette  `(14/40)`** — picture `02-search.png`
     Caption: ⌥Space searches apps, open windows, files, folders and System Settings panes, ranked by what you use.  `(101/120)`
  2. **Window switcher  `(15/40)`** — picture `03-window-switcher.png`
     Caption: ⌃⌥W shows every window as a card. Type to filter, Return to open, ⌘W to close.  `(78/120)`
  3. **Groups  `(6/40)`** — picture `04-groups.png`
     Caption: Drop one app on another to make a group. Rename it, give it a colour and an emoji.  `(82/120)`
  4. **Folder stacks  `(13/40)`** — picture `05-folder-stack.png`
     Caption: Drag a folder from Finder onto the bar. Click it to see what is inside, folders first.  `(86/120)`

### 3. Your layout — `split`, background `dark`, side `left`

- **Kicker:** Your layout  `(11/40)`
- **Title:** Any edge, any display, set up your way  `(38/70)`
- **Description:** Put the bar on the left, right, top or bottom. Run one bar on the main display, one that follows the pointer, or one on every monitor. Every setting applies as you change it.  `(174/320)`
- **Bullets:**
  1. Width, icon size, spacing, corner radius and opacity are all adjustable  `(71/120)`
  2. Auto-hide with an edge reveal, or keep the bar visible and move windows off it  `(78/120)`
  3. The bar hides on a display showing a full-screen app, as the Dock does  `(70/120)`
  4. Nine settings tabs, with a search field above them  `(50/120)`
  5. ⌃⌥Space puts the keyboard on the bar: arrows to move, Return to open, Escape to leave  `(85/120)`
- **Media:** `07-bottom-edge.png`, `06-settings.png`

### 4. How it works — `cards`, background `plain`, numbered `yes`

- **Kicker:** How it works  `(12/40)`
- **Title:** From download to a working bar  `(30/70)`
- **Description:** Nexus is one app with no installer and no account. Setup has six steps, and you can skip every one of them and still have a working launcher.  `(141/320)`
- **Cards:**
  1. **Install  `(7/40)`**
     Drag Nexus to Applications. The first time, right-click it and choose Open: the app is not notarised, so macOS asks once.  `(121/200)`
  2. **Set up  `(6/40)`**
     Choose a search shortcut, set up the bar, decide whether to hide the macOS Dock, and grant permissions only for the window features you want.  `(141/200)`
  3. **Arrange  `(7/40)`**
     Drag apps onto the bar and into order. Drop one app on another to group them. Drag folders in from Finder.  `(106/200)`
  4. **Use the shortcuts  `(17/40)`**
     ⌥Space opens search, ⌃⌥W opens the window switcher, ⌃⌥Space puts the keyboard on the bar. All three can be changed.  `(115/200)`

### 5. Privacy and permissions — `cards`, background `tint`, numbered `no`

- **Kicker:** Privacy and permissions  `(23/40)`
- **Title:** Local, quiet, and asks for little  `(33/70)`
- **Description:** Nexus has no account and makes no network connections. Permissions are requested only by the features that need them, never at launch, and never asked for twice.  `(161/320)`
- **Cards:**
  1. **Nothing leaves your Mac  `(23/40)`**
     No sign-in, no analytics, no network code. Your setup is stored in macOS preferences on this Mac.  `(97/200)`
  2. **Works with nothing granted  `(26/40)`**
     The bar, launching, pinning, window counts, and app and file search all work with every permission denied.  `(106/200)`
  3. **Accessibility for windows  `(25/40)`**
     Window lists, titles, raising a window and window search need Accessibility. Thumbnails can use Screen Recording; without it you get titles.  `(140/200)`
  4. **Light on the system  `(19/40)`**
     Measured on Apple silicon: no CPU use at idle, about 60 MB of memory, and app and window search in under 50 ms.  `(111/200)`
  5. **Leaves the Dock intact  `(22/40)`**
     Hiding the Dock changes four Dock preferences, saved first and restored exactly. Nothing is patched and SIP stays on.  `(117/200)`

## FAQ

1. **What is Nexus?  `(14/120)`**
   Nexus is a macOS app that puts a dock-style bar on any edge of your screen and adds a search palette. The bar holds apps, groups, folders, the Trash, a clock and a volume control, and shows each app's windows on hover. The palette finds apps, open windows, files, folders and System Settings panes. A window switcher (⌃⌥W) shows every open window at once.  `(355/600)`

2. **Who is it for?  `(14/120)`**
   People who keep many apps and windows open and find the Dock and ⌘Tab too limited: you want a vertical bar on a wide display, folders of apps, a way to reach a specific window rather than an app, or one shortcut that searches apps, windows and files together.  `(259/600)`

3. **Which Macs does it run on?  `(26/120)`**
   macOS 14 Sonoma or later. The download is built for Apple silicon (M-series) Macs. It works with one display or several, and the bar can sit on any edge of any of them.  `(168/600)`

4. **What does it cost, and what is the licence?  `(43/120)`**
   Nexus is open source under the MIT licence. The source code is on GitHub at github.com/kael-wanderer/nexus, so you can also build it yourself.  `(142/600)`

5. **Where is my data stored? Is anything sent online?  `(49/120)`**
   Everything stays on your Mac. Your pinned apps, groups and settings are stored in macOS preferences for this Mac. Nexus has no account, no analytics and no network code. File search uses Spotlight's existing index on your Mac.  `(226/600)`

6. **Does it work offline, and does it sync between Macs?  `(52/120)`**
   It works fully offline; nothing in it needs a connection. There is no sync: each Mac keeps its own setup, and permissions such as Accessibility are granted separately on each Mac.  `(179/600)`

7. **How do I install and update it?  `(31/120)`**
   Open the disk image and drag Nexus to Applications. The app is not notarised, so the first time macOS will block it: right-click Nexus, choose Open, then confirm. macOS remembers after that. Nexus does not check for updates itself; to update, download the new version and replace the app in Applications. Your settings are kept.  `(328/600)`

8. **Can I import or export my setup?  `(32/120)`**
   There is no import or export button. Your setup lives in macOS preferences under com.congbui.nexus, so you can back it up in Terminal with "defaults export com.congbui.nexus nexus.plist" and restore it with "defaults import".  `(225/600)`

9. **How is it different from the macOS Dock and Spotlight?  `(54/120)`**
   The Dock is a single row that knows little about windows; Nexus shows each app's windows on hover, groups apps into folders, can sit vertically, and adds a clock, volume and Trash in reach. Spotlight finds files and apps but cannot bring a specific window forward; Nexus's palette can. You can keep the Dock, or let Nexus hide it while it runs.  `(344/600)`

10. **Which permissions does it need?  `(31/120)`**
   None to start. The bar, launching apps, window counts, and app and file search work with every permission denied. Accessibility adds window lists, titles, raising a window and window search. Screen Recording is optional and only used for window thumbnails. Nexus never asks at launch and never asks again after you say no.  `(322/600)`

11. **If I hide the Dock and then remove Nexus, is my Dock broken?  `(60/120)`**
   No. Nexus saves your Dock settings before changing four of them and restores them exactly whenever it quits, so quitting and deleting it leaves the Dock as it was. If Nexus is force-killed, start it again or press ⌥⌘D to bring the Dock back.  `(241/600)`

12. **How do I report a bug or ask for a feature?  `(43/120)`**
   Open an issue on GitHub at github.com/kael-wanderer/nexus/issues. Include your macOS version, which edge and display setup you use, and what you did just before the problem.  `(173/600)`

## Release note

**Version 0.2.0** (build 2, 2026-09-02)

What's new:

- Window switcher: ⌃⌥W shows every window as a card; filter, sort, group, close, or turn a selection into a group
- A clock with a month calendar and a volume control at the end of the bar
- Groups open as a grid or a list, take a colour and an emoji, and are renamed inline
- Settings search, and one Shortcuts tab for all three global shortcuts
- App badges such as unread counts mirrored onto the bar; the bar hides over full-screen apps
- Dragging to reorder or group is reliable now, with a caret where the app will land

## Questions for owner

1. Price: the page says MIT and open source but not whether the download is free. Is it free, and should the price field say so?
2. Intel Macs: only an arm64 disk image exists (build/Nexus-0.2.0-arm64.dmg). Do you want to ship an Intel or universal build, or keep "Apple Silicon" in the requirements?
3. Tested macOS versions: Info.plist says macOS 14 minimum, but the only recorded test runs are on macOS 26.6. Has it been run on 14 or 15?
4. Bug reports: the FAQ points to GitHub issues on kael-wanderer/nexus. Is the repository public with issues turned on, or should reports go somewhere else (the site's comments, email)?
5. Download: where will the DMG be hosted? The install FAQ assumes a disk image downloaded from this page.
6. Pronunciation: left blank. Add one if you want it (e.g. NEK-suhs).

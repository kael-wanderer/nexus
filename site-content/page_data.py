"""Copy for the Nexus page on kael.io.vn. `build.py` turns this into Nexus-page.md and
Nexus-sections.json and checks every field against the admin's limits."""

CATALOG = {
    "name": "Nexus",
    "summary": (
        "A vertical dock and a search palette for macOS in one menu-bar app. Pin and group apps, "
        "see every window, and find apps, windows and files from one shortcut."
    ),
    "details": (
        "Nexus replaces the macOS Dock with a bar on any screen edge and adds a search palette. "
        "The bar holds your apps, groups, folders, the Trash, a clock and a volume control. Hover "
        "an app to see its windows, or press ⌃⌥W to see every window on the Mac at once. The "
        "palette (⌥Space) searches apps, open windows, files and System Settings panes. It all "
        "runs locally: no account, no network, and your Dock settings are put back exactly when "
        "Nexus quits."
    ),
    "category": "Utilities",
    "tags": ["dock", "launcher", "window switcher", "search", "menu bar", "productivity"],
    "platform": "macOS",
    "license": "MIT",
    "requirements": "macOS 14 Sonoma or later · Apple Silicon",
    "accent": "#8A5A1C",
}

SCREENSHOTS = [
    ("01-hero.png", "The bar on the right edge, an app's windows on hover"),
    ("02-search.png", "Search palette: windows and files for one query"),
    ("03-window-switcher.png", "Window switcher filtered to one app, two cards selected"),
    ("04-groups.png", "A group of developer tools opened from the bar"),
    ("05-folder-stack.png", "A project folder opened as a stack from the bar"),
    ("06-settings.png", "Settings, Bar tab: what the bar shows"),
    ("07-bottom-edge.png", "The bar on the bottom edge, with window previews"),
]

FEATURES = [
    {
        "background": "plain",
        "kicker": "What it is",
        "title": "A dock that knows about your windows",
        "description": (
            "Nexus puts a bar on the edge of your screen with your apps, groups and folders, and "
            "opens a search palette from one shortcut. It runs from the menu bar, never takes focus "
            "from what you are typing, and changes no system setting unless you ask it to."
        ),
        "layout": "split",
        "bullets": [
            "Pin, reorder, group and launch apps; running apps show a dot and a window count",
            "Hover an app to see its windows as thumbnails, then click one to bring it forward",
            "The Trash, a clock with a month calendar and a volume control sit at the end of the bar",
            "Optionally hide the macOS Dock while Nexus runs; it comes back exactly as it was on quit",
            "VoiceOver labels on every element; Reduce Motion and Increase Contrast are respected",
        ],
        "side": "right",
        "media": {"pictures": ["01-hero.png"]},
    },
    {
        "background": "tint",
        "kicker": "Find anything",
        "title": "Get to any app, window or file",
        "description": (
            "A search palette, a grid of every open window, and groups and folders kept on the bar. "
            "Each is one shortcut or one click away."
        ),
        "layout": "showcase",
        "tiles": [
            {
                "title": "Search palette",
                "caption": "⌥Space searches apps, open windows, files, folders and System Settings panes, ranked by what you use.",
                "picture": "02-search.png",
            },
            {
                "title": "Window switcher",
                "caption": "⌃⌥W shows every window as a card. Type to filter, Return to open, ⌘W to close.",
                "picture": "03-window-switcher.png",
            },
            {
                "title": "Groups",
                "caption": "Drop one app on another to make a group. Rename it, give it a colour and an emoji.",
                "picture": "04-groups.png",
            },
            {
                "title": "Folder stacks",
                "caption": "Drag a folder from Finder onto the bar. Click it to see what is inside, folders first.",
                "picture": "05-folder-stack.png",
            },
        ],
    },
    {
        "background": "dark",
        "kicker": "Your layout",
        "title": "Any edge, any display, set up your way",
        "description": (
            "Put the bar on the left, right, top or bottom. Run one bar on the main display, one "
            "that follows the pointer, or one on every monitor. Every setting applies as you change it."
        ),
        "layout": "split",
        "bullets": [
            "Width, icon size, spacing, corner radius and opacity are all adjustable",
            "Auto-hide with an edge reveal, or keep the bar visible and move windows off it",
            "The bar hides on a display showing a full-screen app, as the Dock does",
            "Nine settings tabs, with a search field above them",
            "⌃⌥Space puts the keyboard on the bar: arrows to move, Return to open, Escape to leave",
        ],
        "side": "left",
        "media": {"pictures": ["07-bottom-edge.png", "06-settings.png"]},
    },
    {
        "background": "plain",
        "kicker": "How it works",
        "title": "From download to a working bar",
        "description": (
            "Nexus is one app with no installer and no account. Setup has six steps, and you can "
            "skip every one of them and still have a working launcher."
        ),
        "layout": "cards",
        "numbered": True,
        "cards": [
            {
                "title": "Install",
                "text": "Drag Nexus to Applications. The first time, right-click it and choose Open: the app is not notarised, so macOS asks once.",
            },
            {
                "title": "Set up",
                "text": "Choose a search shortcut, set up the bar, decide whether to hide the macOS Dock, and grant permissions only for the window features you want.",
            },
            {
                "title": "Arrange",
                "text": "Drag apps onto the bar and into order. Drop one app on another to group them. Drag folders in from Finder.",
            },
            {
                "title": "Use the shortcuts",
                "text": "⌥Space opens search, ⌃⌥W opens the window switcher, ⌃⌥Space puts the keyboard on the bar. All three can be changed.",
            },
        ],
    },
    {
        "background": "tint",
        "kicker": "Privacy and permissions",
        "title": "Local, quiet, and asks for little",
        "description": (
            "Nexus has no account and makes no network connections. Permissions are requested only "
            "by the features that need them, never at launch, and never asked for twice."
        ),
        "layout": "cards",
        "numbered": False,
        "cards": [
            {
                "title": "Nothing leaves your Mac",
                "text": "No sign-in, no analytics, no network code. Your setup is stored in macOS preferences on this Mac.",
            },
            {
                "title": "Works with nothing granted",
                "text": "The bar, launching, pinning, window counts, and app and file search all work with every permission denied.",
            },
            {
                "title": "Accessibility for windows",
                "text": "Window lists, titles, raising a window and window search need Accessibility. Thumbnails can use Screen Recording; without it you get titles.",
            },
            {
                "title": "Light on the system",
                "text": "Measured on Apple silicon: no CPU use at idle, about 60 MB of memory, and app and window search in under 50 ms.",
            },
            {
                "title": "Leaves the Dock intact",
                "text": "Hiding the Dock changes four Dock preferences, saved first and restored exactly. Nothing is patched and SIP stays on.",
            },
        ],
    },
]

FAQ = [
    (
        "What is Nexus?",
        "Nexus is a macOS app that puts a dock-style bar on any edge of your screen and adds a "
        "search palette. The bar holds apps, groups, folders, the Trash, a clock and a volume "
        "control, and shows each app's windows on hover. The palette finds apps, open windows, "
        "files, folders and System Settings panes. A window switcher (⌃⌥W) shows every open window "
        "at once.",
    ),
    (
        "Who is it for?",
        "People who keep many apps and windows open and find the Dock and ⌘Tab too limited: you "
        "want a vertical bar on a wide display, folders of apps, a way to reach a specific window "
        "rather than an app, or one shortcut that searches apps, windows and files together.",
    ),
    (
        "Which Macs does it run on?",
        "macOS 14 Sonoma or later. The download is built for Apple silicon (M-series) Macs. It works "
        "with one display or several, and the bar can sit on any edge of any of them.",
    ),
    (
        "What does it cost, and what is the licence?",
        "Nexus is open source under the MIT licence. The source code is on GitHub at "
        "github.com/kael-wanderer/nexus, so you can also build it yourself.",
    ),
    (
        "Where is my data stored? Is anything sent online?",
        "Everything stays on your Mac. Your pinned apps, groups and settings are stored in macOS "
        "preferences for this Mac. Nexus has no account, no analytics and no network code. File "
        "search uses Spotlight's existing index on your Mac.",
    ),
    (
        "Does it work offline, and does it sync between Macs?",
        "It works fully offline; nothing in it needs a connection. There is no sync: each Mac keeps "
        "its own setup, and permissions such as Accessibility are granted separately on each Mac.",
    ),
    (
        "How do I install and update it?",
        "Open the disk image and drag Nexus to Applications. The app is not notarised, so the first "
        "time macOS will block it: right-click Nexus, choose Open, then confirm. macOS remembers "
        "after that. Nexus does not check for updates itself; to update, download the new version "
        "and replace the app in Applications. Your settings are kept.",
    ),
    (
        "Can I import or export my setup?",
        "There is no import or export button. Your setup lives in macOS preferences under "
        "com.congbui.nexus, so you can back it up in Terminal with "
        "\"defaults export com.congbui.nexus nexus.plist\" and restore it with \"defaults import\".",
    ),
    (
        "How is it different from the macOS Dock and Spotlight?",
        "The Dock is a single row that knows little about windows; Nexus shows each app's windows "
        "on hover, groups apps into folders, can sit vertically, and adds a clock, volume and "
        "Trash in reach. Spotlight finds files and apps but cannot bring a specific window "
        "forward; Nexus's palette can. You can keep the Dock, or let Nexus hide it while it runs.",
    ),
    (
        "Which permissions does it need?",
        "None to start. The bar, launching apps, window counts, and app and file search work with "
        "every permission denied. Accessibility adds window lists, titles, raising a window and "
        "window search. Screen Recording is optional and only used for window thumbnails. Nexus "
        "never asks at launch and never asks again after you say no.",
    ),
    (
        "If I hide the Dock and then remove Nexus, is my Dock broken?",
        "No. Nexus saves your Dock settings before changing four of them and restores them exactly "
        "whenever it quits, so quitting and deleting it leaves the Dock as it was. If Nexus is "
        "force-killed, start it again or press ⌥⌘D to bring the Dock back.",
    ),
    (
        "How do I report a bug or ask for a feature?",
        "Open an issue on GitHub at github.com/kael-wanderer/nexus/issues. Include your macOS "
        "version, which edge and display setup you use, and what you did just before the problem.",
    ),
]

RELEASE = {
    "version": "0.2.0",
    "date": "2026-09-02",
    "build": "2",
    "whats_new": [
        "Window switcher: ⌃⌥W shows every window as a card; filter, sort, group, close, or turn a selection into a group",
        "A clock with a month calendar and a volume control at the end of the bar",
        "Groups open as a grid or a list, take a colour and an emoji, and are renamed inline",
        "Settings search, and one Shortcuts tab for all three global shortcuts",
        "App badges such as unread counts mirrored onto the bar; the bar hides over full-screen apps",
        "Dragging to reorder or group is reliable now, with a caret where the app will land",
    ],
}

QUESTIONS = [
    "Price: the page says MIT and open source but not whether the download is free. Is it free, and should the price field say so?",
    "Intel Macs: only an arm64 disk image exists (build/Nexus-0.2.0-arm64.dmg). Do you want to ship an Intel or universal build, or keep \"Apple Silicon\" in the requirements?",
    "Tested macOS versions: Info.plist says macOS 14 minimum, but the only recorded test runs are on macOS 26.6. Has it been run on 14 or 15?",
    "Bug reports: the FAQ points to GitHub issues on kael-wanderer/nexus. Is the repository public with issues turned on, or should reports go somewhere else (the site's comments, email)?",
    "Download: where will the DMG be hosted? The install FAQ assumes a disk image downloaded from this page.",
    "Pronunciation: left blank. Add one if you want it (e.g. NEK-suhs).",
]

# Nexus

## Project Foundation & MVP Specification

### 1. Project Overview

**Nexus** is a native macOS productivity and workspace command center.

The long-term vision is to combine the best ideas from:

- Sidebar — vertical Dock, window management, stacks, previews, customization
- uBar — taskbar-style app/window management, multi-monitor support, productivity features
- Docky — modern native macOS UI, widgets, smart stacks, extensibility
- Spotlight / Raycast / Alfred — fast keyboard-driven search and command execution

Nexus should not be treated as "just another Dock replacement".

The long-term product positioning is:

> **Nexus — The command center for your Mac.**

The core principle is:

> Everything on your Mac should be one interaction away.

Nexus should eventually provide:

- Application launcher
- Running application manager
- Window manager
- File search
- Workspace launcher
- System information
- Quick actions
- Automation
- Extensible widgets
- Keyboard-first command palette
- Optional AI-powered commands

---

# 2. MVP Goal

Build a working native macOS MVP that replaces the basic Dock experience with a customizable vertical sidebar.

The MVP should prove these core concepts:

1. A persistent vertical sidebar can replace the traditional Dock.
2. Applications can be launched from Nexus.
3. Running applications and their windows can be displayed.
4. Windows can be grouped by application.
5. Window previews can be displayed.
6. Nexus can be opened quickly using a keyboard shortcut.
7. Nexus provides a fast application/file/window search experience.
8. Nexus supports multiple monitors.
9. Nexus has a clean architecture that allows future features to be added without rewriting the core.

Do NOT attempt to implement the entire long-term vision in the MVP.

---

# 3. Target Platform

## Required

- macOS 14+
- Apple Silicon
- Native macOS application
- Swift
- SwiftUI where practical
- AppKit where required for system integration

The application should feel like a native macOS application.

Avoid Electron unless there is a compelling technical reason.

The MVP should prioritize:

- Performance
- Low memory usage
- Fast startup
- Smooth animations
- Native macOS behavior
- Accessibility
- Maintainable architecture

---

# 4. Product Philosophy

Nexus should feel:

- Native
- Fast
- Minimal
- Powerful
- Keyboard-friendly
- Customizable
- Non-intrusive

It should not feel like a Windows taskbar port.

The UI should follow modern macOS design principles while allowing more customization than Apple's Dock.

---

# 5. MVP UI

## 5.1 Vertical Sidebar

Nexus should provide a vertical sidebar positioned on either:

- Left side of the screen
- Right side of the screen

The user should be able to configure:

- Position
- Width
- Icon size
- Icon spacing
- Corner radius
- Opacity/transparency
- Auto-hide
- Always visible
- Show on hover
- Show running applications
- Show favorite applications

Example conceptual UI:

```text
┌───────┐
│   N   │
│   V   │
│   G   │
│   S   │
│   F   │
│   ─   │
│   💻  │
│   🔍  │
└───────┘
The visual design does not need to match this exactly.

Use native macOS visual language.

6. Application Launcher

The sidebar should contain application icons.

Users should be able to:

Launch applications
Quit applications
Pin applications
Unpin applications
Reorder applications
Drag applications
Display running state
Display number of windows

Example:
VS Code        ●
Ghostty        ● 2
Safari         ● 5
Slack          ● 3
Finder         ●

The running indicator should be subtle.

The number indicates the number of windows belonging to that application.

7. Running Applications

Nexus should detect running applications using native macOS APIs.

Use appropriate AppKit APIs such as:

NSWorkspace
NSRunningApplication

The implementation should avoid aggressive polling.

Prefer event-driven updates where practical.

When an application launches or terminates, Nexus should update automatically.

8. Window Management

Nexus should display windows grouped by application.

Example:
VS Code
├── Bugler
├── Nexus
└── Helpdesk Dashboard

Clicking a window should activate that window.

Required MVP functionality:

List application windows
Activate a window
Group windows by application
Display window count
Show window title when useful
Basic window preview if technically feasible

Window preview can initially be implemented as a lightweight preview or snapshot.

Do not over-engineer window thumbnails in the first implementation.

9. Search

Search is a CORE feature of Nexus.

Nexus should provide a global command/search interface.

The user should be able to trigger it using a configurable keyboard shortcut.

Default:

Command + Space

If possible, Nexus should provide a preference to change this shortcut.

Search should not attempt to completely replace Spotlight at the MVP stage.

Instead, build a focused and fast search engine.

10. Search Categories

The MVP search should support:

Applications

Example:
code
Result:

Visual Studio Code
Application

Press Enter to launch.

Running Applications

Example:

slack

Possible results:

Slack
Application


Slack — General
Window


Slack — Engineering
Window
Windows

Search window titles.

Example:

bugler

Possible result:

VS Code — Bugler
Ghostty — ~/Projects/Bugler
Safari — GitHub / Bugler

Selecting a result activates the window.

Files

The MVP may use macOS Spotlight / NSMetadataQuery as the underlying indexing mechanism.

Do NOT build a complete filesystem indexing engine in the MVP.

Use the operating system's existing indexing capabilities where possible.

Example:

bugler.swift

Result:

Bugler.swift
~/Projects/Nexus/

Press Enter to open using the default application.

11. Search UI

The search UI should feel similar to a command palette.

Concept:
┌─────────────────────────────────────────────┐
│ 🔍  Search apps, files, windows...          │
├─────────────────────────────────────────────┤
│                                             │
│  Visual Studio Code                         │
│  Application                                │
│                                             │
│  Bugler.swift                               │
│  ~/Projects/Bugler/                         │
│                                             │
│  VS Code — Bugler                            │
│  Window                                     │
│                                             │
└─────────────────────────────────────────────┘
Required keyboard behavior:

Type to search
Up/down to navigate
Enter to execute
Escape to close
Command+Space to open
Search results should update immediately
The first result should be selected by default

The search interface should be keyboard-first.

Mouse interaction should also work.

12. Search Architecture

Create a provider-based search architecture.

Concept:
SearchEngine
    │
    ├── ApplicationProvider
    ├── WindowProvider
    ├── FileProvider
    └── ActionProvider

Each provider should return a common search result model.

Example conceptual model:

SearchResult {
    title
    subtitle
    icon
    category
    relevance
    action
}

This architecture is important because future providers may include:

WorkspaceProvider
SystemProvider
GitProvider
DockerProvider
AutomationProvider
AIProvider
PluginProvider

Do not hard-code search logic into the UI.

13. Quick Actions

The MVP should establish the concept of Actions.

Examples:

Quit Safari
Open Terminal
Open Downloads
Open System Settings
Show Desktop
Lock Screen

Actions can initially be limited.

Create an ActionProvider abstraction even if only a few actions are implemented.

Future actions may include:

Restart Docker
Start Ollama
Connect VPN
Run Git Pull
Open Development Workspace
Run Shell Script
14. Multi-Monitor Support

Nexus must support multiple displays.

At minimum:

Detect connected displays
Allow Nexus sidebar on the main display
Allow configuration per display where practical
Keep Nexus stable when displays are connected/disconnected

Future versions should support completely independent Nexus instances/configurations per monitor.

Do not make multi-monitor architecture impossible to extend.

15. Settings

The MVP should have a basic Settings window.

Settings categories:

General
Launch Nexus at login
Show in menu bar
Enable global keyboard shortcut
Appearance
Sidebar position
Icon size
Sidebar width
Opacity
Auto-hide
Animation
Behavior
Show running applications
Show window count
Show favorites
Click behavior
Search
Global shortcut
Search applications
Search windows
Search files
Search actions

Settings should be persisted using an appropriate native macOS mechanism.

Do not build an unnecessarily complicated settings system.

16. Data Persistence

Persist:

Pinned applications
Application ordering
Sidebar configuration
Search configuration
Keyboard shortcuts
User preferences

Use a simple and native persistence mechanism.

The architecture should allow migration/versioning of preferences in the future.

17. Accessibility

Nexus should support:

Keyboard navigation
VoiceOver where practical
Accessible labels
High contrast
Reduce Motion
Respect macOS accessibility settings

Do not sacrifice accessibility for visual effects.

18. Performance Requirements

Performance is a first-class requirement.

Nexus should:

Start quickly
Consume minimal CPU when idle
Avoid constant polling
Avoid unnecessary filesystem scanning
Avoid excessive window screenshot generation
Avoid memory leaks
Avoid retaining large image buffers unnecessarily

The sidebar should remain responsive even when many applications/windows are running.

Search should feel instantaneous for application/window search.

File search may have a small delay because it relies on system indexing.

19. Architecture

Use a modular architecture.

Suggested structure:

Nexus
├── App
│
├── Core
│   ├── Models
│   ├── Services
│   ├── EventBus
│   └── Utilities
│
├── Applications
│   ├── ApplicationService
│   └── ApplicationMonitor
│
├── Windows
│   ├── WindowService
│   ├── WindowMonitor
│   └── WindowPreview
│
├── Search
│   ├── SearchEngine
│   ├── SearchProvider
│   ├── ApplicationProvider
│   ├── WindowProvider
│   ├── FileProvider
│   └── ActionProvider
│
├── Sidebar
│   ├── SidebarView
│   ├── SidebarController
│   └── SidebarConfiguration
│
├── Settings
│
└── Resources

The exact folder structure may be adjusted if there is a better Swift architecture.

The important requirement is separation of concerns.

20. Future Architecture

Design the MVP so these future components can be added:

Nexus
│
├── Launcher
├── Window Manager
├── Search
├── Workspaces
├── System Monitor
├── Automation
├── Widgets
├── Plugins
└── AI

Do not implement these future systems now unless required by the MVP.

21. Future Workspace System

The long-term vision includes Workspaces.

Example:

Development
├── VS Code
├── Ghostty
├── GitHub
├── Docker
└── Project folders

AI
├── Claude
├── ChatGPT
├── LM Studio
├── Ollama
└── VS Code

Helpdesk
├── Slack
├── Browser
├── Jira
├── Confluence
└── Terminal

A workspace should eventually be able to:

Launch applications
Open URLs
Open folders
Restore window positions
Assign windows to monitors
Run automation
Run shell commands

Do not implement full Workspaces in MVP.

Create architecture that does not prevent it.

22. Future System Widgets

Nexus should eventually support widgets such as:

CPU
GPU
RAM
Disk
Network
Battery
Temperature
Fan
Bluetooth
Wi-Fi
VPN
Now Playing
Calendar
Weather
Docker
Ollama

The widget architecture should eventually be plugin-based.

Do not implement the full widget system in MVP.

23. Future Automation Engine

Long-term Nexus should expose actions through:

Shell commands
AppleScript
macOS Shortcuts
HTTP requests
Webhooks
Custom scripts

Example:

Development Workspace
    ↓
Open VS Code
    ↓
Open Ghostty
    ↓
Start Docker
    ↓
Start Ollama
    ↓
Open project

This is intentionally out of MVP scope.

24. Future AI Layer

AI should NOT be required for the MVP.

However, the architecture should allow a future AI provider.

Potential future interaction:

"Open my development environment"

Nexus could translate that into:

Open VS Code
Open Ghostty
Start Docker
Open ~/Projects/Nexus

Another example:

"Show me everything related to Nexus"

Nexus could search:

Applications
Windows
Files
Workspaces
Actions

AI should be an optional layer on top of deterministic search/actions.

Do not make basic functionality dependent on an AI service.

25. Security

Nexus will require macOS permissions for some functionality.

Handle permissions carefully.

Potential permissions include:

Accessibility
Automation
Files and Folders

Do not request permissions unnecessarily.

Only request a permission when a feature actually requires it.

Clearly explain to the user why the permission is needed.

Never collect or transmit user data without explicit user action.

Search data should remain local by default.

26. Privacy

Nexus should be local-first.

The MVP should not require:

Cloud account
Telemetry
Remote server
User registration
Internet connection

Application/window/file search should remain local.

If analytics are added in the future, they must be opt-in.

27. Visual Design

The UI should be:

Modern
Native
Minimal
Elegant
Dark-mode friendly
Light-mode friendly
Customizable

Avoid copying the exact UI of Sidebar, uBar, or Docky.

Use those products only as inspiration.

Nexus should develop its own visual identity.

Potential visual concept:

Normal:

     ┌─────┐
     │  V  │
     │  G  │
     │  S  │
     │  F  │
     │  ─  │
     │  🔍 │
     └─────┘

Hover:

     ┌─────────────────────┐
     │ Nexus                │
     │ 🔍 Search            │
     ├─────────────────────┤
     │ ⭐ Favorites         │
     │ VS Code         3    │
     │ Ghostty         2    │
     │ Safari          5    │
     │ Slack           4    │
     ├─────────────────────┤
     │ 🗂 Workspaces        │
     │ 💻 System            │
     └─────────────────────┘

     This is only a conceptual direction.

28. MVP Scope
MUST HAVE
Native macOS application
Vertical sidebar
Left/right positioning
App launcher
Running application detection
Launch applications
Quit applications
Pin applications
Reorder applications
Window grouping
Activate windows
Window count
Basic window preview if feasible
Global keyboard shortcut
Search UI
Application search
Window search
Basic file search
Basic actions
Settings
Persistence
Multi-monitor awareness
Dark/light mode
Keyboard navigation
Accessibility basics
SHOULD HAVE
Auto-hide
Hover expand
Drag and drop
Smooth animations
Custom icon size
Custom sidebar width
Custom opacity
Recent applications
Window title preview
NICE TO HAVE
Advanced window thumbnails
Folder stacks
Multiple sidebar configurations
Per-monitor configuration
OUT OF MVP
AI
Full automation engine
Plugin marketplace
Full widget system
Workspace restoration
Cloud synchronization
Account system
Telemetry
Remote control
29. MVP Milestones
Milestone 1 — Foundation

Create the native macOS application.

Implement:

Swift project
Basic architecture
App lifecycle
Configuration model
Logging
Settings persistence

Acceptance criteria:

Application launches successfully
No crashes
Basic settings can be persisted
Milestone 2 — Sidebar

Implement:

Vertical sidebar
Left/right positioning
Icon rendering
App launching
Pinning
Ordering
Auto-hide

Acceptance criteria:

User can use Nexus as a basic Dock replacement.
Milestone 3 — Running Apps

Implement:

Running application detection
Running indicator
Window count
Application quit

Acceptance criteria:

Sidebar updates automatically when applications launch/quit.
Milestone 4 — Windows

Implement:

Window discovery
Window grouping
Window activation
Window titles
Basic preview

Acceptance criteria:

User can manage application windows from Nexus.
Milestone 5 — Search

Implement:

Command+Space
Search window
Application provider
Window provider
File provider
Keyboard navigation
Enter action
Escape close

Acceptance criteria:

Command + Space
→ type "code"
→ Visual Studio Code
→ Enter
→ VS Code launches/activates
And:

Command + Space
→ type "bugler.swift"
→ file appears
→ Enter
→ file opens
Milestone 6 — Settings

Implement:

Appearance
Behavior
Search
Keyboard shortcut
Launch at login

Acceptance criteria:

Settings persist after restart.
Milestone 7 — Polish

Improve:

Animation
Performance
Accessibility
Multi-monitor behavior
Error handling
Permission handling
Memory usage
CPU usage
30. Developer Experience

The project should include:

README.md
LICENSE
CONTRIBUTING.md
CHANGELOG.md

Use a permissive open-source license unless otherwise specified.

Recommended default:

MIT License

The README should explain:

What Nexus is
Why it exists
Screenshots/placeholders
Features
Installation
Development setup
Architecture
Roadmap
Contributing
31. Coding Standards

Prioritize:

Small focused types
Protocol-oriented abstractions where useful
Dependency injection where useful
Clear naming
No unnecessary global state
No massive View files
No business logic inside SwiftUI views
Unit-testable services
Structured logging
Graceful failure

Avoid premature abstraction.

Do not create an elaborate framework for features that do not exist yet.

32. Important Engineering Rule

Do not blindly implement every idea in this document.

This document describes the product direction.

For the MVP:

Build the smallest useful version.
Keep the architecture extensible.
Avoid unnecessary dependencies.
Prefer native macOS APIs.
Prefer simple solutions.
Do not implement future features unless they are needed for the current milestone.
Keep the application stable and usable after every milestone.

If a technical decision is ambiguous, prefer the simplest native macOS solution that preserves future extensibility.

33. Definition of Done

The MVP is considered successful when a user can:

Launch Nexus.
See a vertical Dock/sidebar.
Pin applications.
Launch applications.
See running applications.
See window counts.
View application windows.
Activate a specific window.
Press Command+Space.
Search for an application.
Search for a running window.
Search for a file.
Execute a basic action.
Configure the sidebar.
Restart Nexus and retain configuration.
Use Nexus across multiple displays.
Use Nexus comfortably with keyboard navigation.

The final MVP should feel like a real daily-use macOS utility, not a technical prototype.

34. First Task for the Coding Agent

Before writing significant code:

Inspect the repository.
Determine whether the repository is empty or already contains code.
Propose the project structure.
Identify the minimum macOS APIs required.
Identify any permissions required.
Create a concise implementation plan.
Implement Milestone 1.
Run/build/test the application.
Fix build errors.
Only then proceed to Milestone 2.

Do not implement the entire specification in one pass.

Work incrementally.

After each milestone:

Build the application.
Run tests.
Check for compiler warnings.
Check for obvious memory/performance issues.
Summarize what was implemented.
Identify the next milestone.

35. Product Identity

Product name:

Nexus

Product category:

macOS Command Center / Workspace Launcher

Tagline:

The command center for your Mac.

Core concepts:

Apps
Windows
Search
Workspaces
System
Automation

Long-term vision:

Nexus should become the fastest and most customizable way to interact with a Mac without getting in the user's way.

Nexus should evolve beyond being a Dock replacement.

The Dock/sidebar is the visual entry point, but the long-term product should become a unified command center for applications, windows, files, system controls, workspaces, and automation.

36. Long-Term Product Vision

The long-term vision can be summarized in three concepts:

Discover → Control → Automate

Discover

Help the user quickly find:

Applications
Files
Windows
Workspaces
System information
Commands
Actions
Automations
Control

Allow the user to control:

Applications
Windows
Displays
Audio devices
Network
VPN
System state
Workspaces
Automate

Allow the user to automate:

Repetitive tasks
Development environments
IT workflows
Shell commands
AppleScript
macOS Shortcuts
HTTP requests
Webhooks
Custom scripts

Nexus should gradually evolve from:

Dock Replacement
       ↓
Launcher
       ↓
Command Palette
       ↓
Workspace Manager
       ↓
System Control Center
       ↓
Automation Platform
37. Universal Command Center

The long-term search experience should become a universal command interface.

Instead of asking:

"Where is this application?"

the user should be able to ask:

"What do I want to do?"

Examples:

restart docker
connect vpn
open my development environment
show large files
kill chrome
mute microphone
switch audio to AirPods
show CPU usage
open Jira

Nexus should determine whether the request corresponds to:

Application
File
Window
System
Action
Workspace
Automation
AI

Conceptual architecture:

                    Nexus Command
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
      Search            Action           Workspace
        │                 │                 │
        ├── Apps          ├── System       ├── Work
        ├── Files         ├── Network      ├── AI
        ├── Windows       ├── Audio        ├── Personal
        └── Data          └── Automation   └── Custom
The deterministic command system should remain the foundation.

AI may eventually interpret natural language, but basic Nexus functionality must never depend on AI.

38. System Control Center

Nexus should eventually provide a lightweight system control interface.

Example:

NEXUS
────────────────
CPU       21%
RAM       48%
GPU       13%
Disk      72%
Network   ↓ 2 MB/s
Battery   87%
Temp      51°C
────────────────
Wi-Fi     Connected
VPN       Connected
Audio     AirPods
Mic       On

Potential system controls:

Wi-Fi
Bluetooth
VPN
Tailscale
Audio output
Audio input
Microphone state
Display information
Battery
Power state
Focus mode
Do Not Disturb
System volume

System information should be read-only unless the user explicitly invokes a control action.

39. System Diagnostics

Nexus may eventually provide developer and IT diagnostics.

Potential information:

CPU
GPU
Memory
Disk
Network
Processes
Services
Launch Agents
Ports
Docker
Thermal information
Battery health
System uptime

Example command:

> what's using port 3000?

Possible result:

Port 3000


Process: node
PID: 18291
Path: ~/Projects/Nexus

Another example:

> what's using my memory?

Nexus could show the top memory-consuming processes.

This functionality should be local and should not require a cloud service.

40. Workspace System

Workspaces should become one of the primary concepts in Nexus.

A workspace represents a user's current context rather than simply a collection of applications.

Example:
Development
├── VS Code
├── Ghostty
├── GitHub
├── Docker
└── Project folders

AI
├── Claude
├── ChatGPT
├── LM Studio
├── Ollama
└── VS Code

Helpdesk
├── Slack
├── Browser
├── Jira
├── Confluence
└── Terminal
A workspace may eventually contain:

Applications
Windows
URLs
Folders
Terminal sessions
Window positions
Display assignments
Automation actions
Environment configuration
41. Workspace Restoration

A future workspace should support restoring a working context.

Example:

Development Workspace


1. Open VS Code
2. Open Ghostty
3. Open project folder
4. Open GitHub
5. Start Docker
6. Restore window positions
7. Assign windows to the correct monitor

The user should eventually be able to select:

Continue Development

and Nexus should restore the relevant environment.

This feature should be implemented only after the core workspace architecture is stable.

42. Context-Aware Workspaces

Nexus may eventually support rules based on context.

Examples:

IF
weekday = Monday-Friday
AND
time = 08:00-18:00


THEN
activate Work workspace

Another example:

IF
external monitor is connected
AND
weekday = Monday-Friday


THEN
activate Development workspace

Rules should be deterministic and user-controlled.

Do not require AI for context detection.

43. Profiles

Nexus may eventually support profiles.

Example:

Nexus Profiles


Minimal
Developer
IT Admin
Creative
Gaming
Custom

A profile could control:

Sidebar layout
Applications
Widgets
Search providers
Actions
Workspaces
Theme
Keyboard shortcuts

Profiles should allow users to maintain different Nexus configurations without manually changing every setting.

44. Plugin Architecture

The long-term architecture should support plugins.

Possible plugin types:

Nexus Plugin
├── Search Provider
├── Action Provider
├── Widget
├── Workspace Provider
├── Automation
└── Integration

Example community plugins:

nexus-docker
nexus-github
nexus-kubernetes
nexus-ollama
nexus-homeassistant
nexus-jira
nexus-slack

Plugins should be isolated from the Nexus core as much as practical.

The core should remain stable even if plugins are installed or removed.

45. Widget System

Nexus should eventually support lightweight widgets.

Potential widgets:

CPU
GPU
RAM
Disk
Network
Battery
Temperature
Fan
Bluetooth
Wi-Fi
VPN
Now Playing
Calendar
Weather
Docker
Ollama
Git

Widgets should be:

Small
Fast
Optional
Local-first
Configurable

The widget system should eventually support third-party widgets.

Avoid turning Nexus into a dashboard that constantly consumes screen space.

The default experience should remain minimal.

46. Automation Platform

Nexus should eventually expose an automation layer.

Supported automation mechanisms may include:

Shell commands
AppleScript
macOS Shortcuts
HTTP requests
Webhooks
Custom scripts

Example:

Development Workspace
        ↓
Open VS Code
        ↓
Open Ghostty
        ↓
Start Docker
        ↓
Start Ollama
        ↓
Open project

Automations should be executable from:

Search
Sidebar
Workspace
Keyboard shortcut
Context menu

Future versions may provide an automation editor.

47. Automation Marketplace

If the project becomes a community-driven open-source platform, Nexus could eventually support shared automation packages.

Example categories:

Developer
DevOps
IT Administration
Productivity
Creative
System Maintenance
AI
Networking

Examples:

Start Development Environment
Clean Docker
Restart VPN
Open Helpdesk
Setup New Employee
Deploy Project
Flush DNS
Restart Network Services

This should be considered a future ecosystem feature, not an MVP requirement.

48. AI Layer

AI should be optional.

Nexus should remain fully useful without an AI provider.

Potential future interaction:

"Open my development environment"

Nexus could interpret this as:

Open VS Code
Open Ghostty
Start Docker
Open ~/Projects/Nexus

Another example:

"Show me everything related to Nexus"

Nexus could search:

Applications
Windows
Files
Workspaces
Actions


AI should produce an intent or action plan.


Execution should remain controlled by Nexus's deterministic action system.


Conceptually:


```text
User Request
     ↓
AI Interpretation
     ↓
Intent
     ↓
Action Plan
     ↓
Optional Confirmation
     ↓
Nexus Action Engine
     ↓
Execute

The AI layer must not become a single point of failure for normal Nexus operations.

49. Nexus Lenses

A future concept called Lenses may provide focused views of Nexus.

Potential lenses:

Apps Lens
Windows Lens
Files Lens
System Lens
Network Lens
Workspace Lens
Automation Lens
AI Lens

The user should not need to manually select a lens in most cases.

Nexus Search should determine the appropriate provider automatically.

Examples:

> chrome

Potential providers:

Applications
Windows

Another:

> cpu

Potential provider:

System

Another:

> development

Potential provider:

Workspace

The Lens concept is primarily an architectural and UX abstraction.

It does not need to appear as a visible UI element.

50. Activity and History

Nexus may eventually provide local activity history.

Example:

Today


09:02  Opened VS Code
09:04  Started Docker
09:10  Opened Nexus
10:32  Switched to Slack
11:15  Opened Bugler.swift

This could power:

Recent items
Frequently used applications
Recently used workspaces
Continue where I left off
Search history
Usage insights

Privacy is critical.

Activity history should be:

Local
Optional
Clearable
Disabled by default if the data is sensitive

Nexus should never transmit activity history without explicit user consent.

51. Continue Where I Left Off

Nexus may eventually allow users to restore a previous working context.

Example:

Yesterday
Development Workspace


VS Code
Ghostty
Chrome
Docker

The user can choose:

Continue Development

Nexus attempts to restore the environment.

This should build on top of the Workspace system rather than becoming a separate subsystem.

52. Theme Engine

Nexus should eventually support a theme system.

Potential built-in themes:

Nexus Dark
Nexus Light
Everforest
Nord
Dracula
Catppuccin
Solarized

Users may eventually customize:

Sidebar Background
Accent
Icon
Hover
Active State
Separator
Transparency
Blur

The theme system should be designed around semantic colors rather than hard-coded UI colors.

Example:

background
secondaryBackground
accent
active
hover
textPrimary
textSecondary
separator

This allows themes to evolve without rewriting UI components.

53. IT / Developer Mode

Nexus may eventually provide a dedicated IT / Developer profile.

Example:

NEXUS
─────────────────
System
  CPU       21%
  RAM       48%
  Disk      72%

Network
  Wi-Fi     ✓
  VPN       ✓
  Tailscale ✓

Docker
  Containers 8

AI
  Ollama    ✓
  LM Studio ✓

Tools
  Terminal
  SSH
  RDP
  RustDesk

  This mode is especially useful for developers, system administrators, DevOps engineers, and IT professionals.

It should remain optional.

54. Security and Permission Center

Because Nexus may eventually interact with:

Accessibility
Automation
Files
Shell commands
Network
System controls

Nexus should provide a clear permission model.

Example:

Nexus Permissions


Accessibility       ✓
Automation          ✓
File Access         ✓
Shell               ✓
Network             ✓

For each permission, Nexus should explain:

Why it is required
Which feature requires it
What Nexus can do with it
How to revoke it

Do not request permissions until they are actually needed.

Plugins should not automatically inherit unlimited permissions.

55. Privacy Principles

Nexus should be local-first.

The long-term product should avoid requiring:

Cloud account
User registration
Remote server
Telemetry
Internet connection

for core functionality.

Application, window, and file search should remain local.

If cloud services or AI providers are supported in the future:

They must be optional.
The user must explicitly enable them.
The UI should clearly indicate when data leaves the Mac.
Sensitive local data should not be transmitted silently.

Privacy should be part of the product identity, not an afterthought.

56. Cross-Device Future

A future version may support synchronization between Macs.

Example:

Mac Studio
     ↕
   Nexus
     ↕
MacBook Pro

Potentially synchronized:

Preferences
Themes
Search configuration
Workspaces
Automations
Plugins
Shortcuts

Window state and display-specific configuration should remain device-specific when necessary.

Possible future technologies include:

iCloud
CloudKit
Local network synchronization

This is explicitly out of scope for the MVP.

57. Long-Term Product Architecture

The long-term architecture can evolve toward:

                              NEXUS
                    Command Center for macOS
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
       LAUNCH                  MANAGE                 SEARCH
          │                       │                       │
        Apps                   Windows                 Apps
        Files                  Displays                Files
        Folders                Spaces                  Windows
                                                       Actions
          │                       │                       │
          └───────────────────────┼───────────────────────┘
                                  │
                             WORKSPACES
                                  │
                        ┌─────────┴─────────┐
                        │                   │
                     SYSTEM             AUTOMATION
                        │                   │
                    CPU/RAM             Scripts
                    Network             Shortcuts
                    Docker              Webhooks
                    Audio               Actions
                        │                   │
                        └─────────┬─────────┘
                                  │
                               PLUGINS
                                  │
                                  AI

This is the long-term direction.

The MVP should implement only the foundations required to make this architecture possible.

58. Competitive Positioning

Nexus should not compete solely on:

"More customizable Dock."

That is too narrow.

Instead, the product should differentiate through:

1. Unified Search

Apps + windows + files + actions in one interface.

2. Workspace Context

Nexus understands the user's working context.

3. System Awareness

Nexus can expose useful system information and controls.

4. Automation

Nexus can execute useful workflows instead of only launching applications.

5. Extensibility

Plugins can add new search providers, widgets, actions, and integrations.

6. Local-first Privacy

Core functionality works without cloud services.

7. Open Source

The community can inspect, modify, and extend the application.

59. Long-Term UX Principle

Nexus should always follow this rule:

Power should be available, but never forced on the user.

A new user should be able to use Nexus as a simple Dock replacement.

A power user should be able to turn Nexus into a complete command center.

Conceptually:
Simple User

Nexus
├── Apps
└── Search


Power User

Nexus
├── Apps
├── Windows
├── Search
├── Workspaces
├── System
├── Automation
└── Plugins

The product should grow with the user.

60. Final Long-Term Vision

The ultimate goal of Nexus is not to build a better Dock.

The goal is to create a native macOS command center that makes the Mac feel faster, more organized, more customizable, and more powerful.

Nexus should provide a single place where users can:

Find
Launch
Switch
Control
Organize
Automate

The long-term experience should feel like:

The Dock + Window Manager + Spotlight + Command Palette + Workspace Manager + System Control Center + Automation Layer

while remaining:

Native
Fast
Local-first
Privacy-conscious
Extensible
Keyboard-friendly
Beautiful
Lightweight

The guiding principle remains:

Nexus — The command center for your Mac.


# 61. Product Principles

Nexus should follow these principles throughout its development.

## Native First

Prefer native macOS technologies and APIs whenever possible.

Use:

- Swift
- SwiftUI
- AppKit
- CoreServices
- NSWorkspace
- Accessibility APIs
- macOS system frameworks

Avoid unnecessary third-party dependencies.

A dependency should be introduced only when it provides significant value that would otherwise require excessive complexity.

---

## Local First

Core functionality should work entirely on the local Mac.

The user should not need:

- An account
- A subscription
- An internet connection
- A cloud backend

for basic Nexus functionality.

---

## Fast First

Nexus is a utility that runs continuously.

Therefore:

> Performance is a feature.

Nexus should prioritize:

- Fast startup
- Low idle CPU
- Low memory usage
- Fast search
- Responsive UI
- Smooth animations
- Minimal background work

---

## Keyboard First

Mouse interaction should be supported, but keyboard interaction should be first-class.

Almost every important operation should eventually be possible without touching the mouse.

---

## Progressive Complexity

The default Nexus experience should remain simple.

Advanced functionality should be discoverable rather than forced upon the user.

---

# 62. Architecture Principles

The architecture should optimize for long-term evolution without introducing unnecessary complexity.

## Separation of Concerns

UI components should not directly own system-level logic.

For example:

```text
SwiftUI View
     ↓
ViewModel / Controller
     ↓
Service
     ↓
macOS API

Avoid putting application discovery, window management, search logic, or shell execution directly inside views.

Protocol-Based Services

Where appropriate, define protocols for major services.

Example:

protocol ApplicationService {
    func runningApplications() -> [Application]
    func launch(_ application: Application)
    func quit(_ application: Application)
}

This allows services to be mocked for testing.

Do not create protocols for every trivial type.

Use abstractions where they provide real architectural value.

Event-Driven Architecture

Prefer events over polling.

Potential events:

ApplicationLaunched
ApplicationTerminated
WindowCreated
WindowClosed
WindowFocused
DisplayConnected
DisplayDisconnected
SettingsChanged
SearchQueryChanged

The exact event system may evolve during development.

63. Dependency Management

Keep external dependencies to a minimum.

Prefer:

Apple Framework
       ↓
Nexus Core
       ↓
Nexus Features

instead of:

Many Third-Party Libraries
       ↓
Nexus

Every dependency should be evaluated based on:

Maintenance
License
Security
Performance
Binary size
macOS compatibility
Long-term availability
64. Permissions Architecture

Permissions should be treated as capabilities.

Potential capabilities:

Accessibility
Automation
File Access
Shell Execution
Network
System Controls

Features should request only the capability they require.

Example:

Window Management
    → Accessibility


File Search
    → Spotlight / File access where required


Automation
    → Automation / AppleScript


Shell Actions
    → Shell execution

The permission system should remain modular so future plugins can declare their required capabilities.

65. Error Handling

Nexus should fail gracefully.

System-level operations can fail because:

Permissions are missing
An application is unavailable
A window disappears
A display disconnects
A process terminates
A file is moved
macOS denies an operation

The application should not crash because of these conditions.

Example:

Expected:
Window disappeared
     ↓
Refresh state
     ↓
Continue normally

Not:

Window disappeared
     ↓
Application crash
66. Logging

Nexus should use structured logging.

Logs should be useful for debugging but should not expose sensitive user data unnecessarily.

Suggested categories:

Nexus.App
Nexus.Sidebar
Nexus.Search
Nexus.Windows
Nexus.Applications
Nexus.System
Nexus.Automation
Nexus.Plugins
Nexus.Permissions

Avoid logging:

File contents
User passwords
Authentication tokens
Sensitive command output
Private URLs unless necessary for debugging
67. Testing Strategy

Testing should focus on the parts most likely to break.

Unit Tests

Test:

Search ranking
Search providers
Configuration
Persistence
Workspace models
Action resolution
Permission logic
Integration Tests

Test:

Application discovery
Search integration
Window management
Settings persistence
UI Tests

Test critical user flows:

Launch Nexus
    ↓
Open Sidebar
    ↓
Launch Application
    ↓
Open Search
    ↓
Search Application
    ↓
Activate Window

Testing should be incremental.

Do not attempt to create a massive test suite before the architecture stabilizes.

68. Performance Monitoring

Performance should eventually be measurable.

Track development metrics such as:

Startup time
Idle CPU
Idle memory
Search latency
Window update latency
Sidebar rendering latency

Example targets:

Cold start:
< 1 second where practical


Application search:
< 50 ms for indexed local data


Window search:
< 50 ms


Idle CPU:
Near zero when no work is required

These are engineering targets, not absolute guarantees.

Measure before optimizing.

69. Accessibility Requirements

Accessibility should not be postponed until the end.

Nexus should support:

VoiceOver
Keyboard navigation
Accessibility labels
Focus management
Reduce Motion
Increase Contrast
Dynamic system appearance

Every interactive element should have a meaningful accessibility label.

Example:

VS Code

instead of:

Button 42
70. Internationalization

The initial MVP may ship in English only.

However, user-facing strings should not be hard-coded directly into UI components if practical.

Future localization may include:

English
Vietnamese
Japanese
Korean
Chinese
German
French
Spanish

Design UI layouts so longer translated strings do not break the interface.

71. Open Source Strategy

Nexus should be designed as an open-source project from the beginning.

The repository should be understandable to a new contributor.

The project should provide:

README.md
LICENSE
CONTRIBUTING.md
CODE_OF_CONDUCT.md
SECURITY.md
CHANGELOG.md

The documentation should explain:

Project goals
Architecture
Development setup
Build instructions
Contribution workflow
Plugin development
Security considerations
72. Contribution Model

Contributors should be able to work on individual areas without understanding the entire codebase.

Potential areas:

Core
UI
Search
Window Management
System Integration
Accessibility
Themes
Plugins
Automation
Documentation
Testing

Issues should be labeled clearly.

Example:

area:search
area:ui
area:window-management
area:system
area:automation
area:plugin
area:documentation
73. Plugin Security Model

Plugins are potentially dangerous because they may execute code or access user data.

Future plugin support must consider:

Permission isolation
Explicit user approval
Plugin identity
Version compatibility
Revocation
Sandboxing where practical
Secure updates

Never design a plugin marketplace that silently grants unrestricted system access.

74. Configuration Compatibility

Nexus configuration should be versioned.

Example:

Configuration Version 1
Configuration Version 2
Configuration Version 3

When the configuration format changes, Nexus should migrate old settings automatically where possible.

Avoid breaking existing users after every update.

75. Backward Compatibility

The project should define supported macOS versions explicitly.

If a newer macOS API is required:

if available:
    use modern API
else:
    use compatible fallback

Do not unnecessarily drop older supported macOS versions.

76. Release Channels

Future releases may use:

Stable
Beta
Nightly
Development

The MVP only needs a stable development build.

The release architecture should remain simple until the project has a real user base.

77. Update System

Nexus may eventually support automatic updates.

Requirements:

Secure update verification
Signed releases
User-controlled update behavior
Release notes
Rollback strategy where practical

Do not implement an update mechanism in the MVP unless required.

78. Telemetry Philosophy

Telemetry should not be enabled by default.

If telemetry is ever introduced:

Opt-in
Local explanation
Minimal data
Anonymous
Transparent
Disable anytime

The product should remain fully functional without telemetry.

79. Data Ownership

The user owns the data generated by Nexus.

Examples:

Configuration
Workspaces
Automations
Search history
Activity history
Plugin configuration

Users should eventually be able to:

Export
Backup
Restore
Delete

their Nexus data.

80. Backup and Restore

Future Nexus versions should support configuration backup.

Example:

Export Nexus Configuration
        ↓
nexus-config.json

Possible contents:

Themes
Pinned Apps
Sidebar Settings
Keyboard Shortcuts
Workspaces
Actions
Automations
Plugin Configuration

Sensitive credentials should never be stored directly in plain-text configuration files.

81. Command and Action Model

The Action system should become one of the most important internal abstractions.

Conceptually:

protocol NexusAction {
    var id: String { get }
    var title: String { get }
    var subtitle: String? { get }
    var icon: String? { get }


    func execute() async throws
}

Examples:

LaunchApplicationAction
ActivateWindowAction
OpenFileAction
OpenURLAction
QuitApplicationAction
ShellCommandAction
WorkspaceAction
SystemAction

Search results may point directly to actions.

This creates a unified model:

Search
   ↓
Result
   ↓
Action
   ↓
Execute

82. Command Palette as the Core Interaction Model

The command palette should eventually become more than a search box.

It should support:

Search
Actions
Navigation
Workspaces
Automation
System Controls

Example:

⌘ Space


> restart docker
⌘ Space


> open development
⌘ Space


> mute microphone
⌘ Space


> vscode

The same interaction model should work across all Nexus features.

83. Context Menus

The sidebar should provide useful context menus.

Example:

VS Code
──────────────
Open
New Window
Show Windows
Quit
──────────────
Pin to Nexus
Remove from Nexus

For files:

Project.swift
──────────────
Open
Reveal in Finder
Copy Path
Open With

Context menus should expose useful actions without overwhelming the user.

84. Drag and Drop

Future Nexus versions should support drag and drop where appropriate.

Examples:

Application → Sidebar
Application → Workspace
File → Application
File → Workspace
Folder → Workspace

Drag and drop should feel native to macOS.

85. Smart Stacks

Nexus may eventually support dynamic stacks.

Examples:

Downloads
Recent Files
Projects
Screenshots
Documents

A stack may display:

Downloads
├── file.pdf
├── image.png
├── report.docx
└── archive.zip

The implementation should avoid copying Finder's entire UI.

The goal is quick access, not full file management.

86. Recent and Frequently Used Items

Nexus should eventually provide intelligent ordering.

Possible sections:

Favorites
Running
Recent
Frequently Used
Suggested

The user should always be able to disable intelligent ordering.

Do not make the interface unpredictable.

87. Focus and Attention Management

Future Nexus versions may help manage application attention.

Examples:

Slack       ● 3
Mail        ● 2
Messages    ● 1

Nexus could eventually aggregate notifications or unread indicators.

However, notification management must remain respectful of macOS system behavior.

Nexus should not attempt to replace the entire Notification Center.

88. Window Management Extensions

The long-term window manager may support:

Tile Left
Tile Right
Maximize
Center
Move to Display
Move to Workspace
Resize
Restore Position

Potential keyboard shortcuts:

⌃⌥←
⌃⌥→
⌃⌥↑
⌃⌥↓

Shortcuts must be fully configurable.

Do not conflict with common macOS shortcuts by default.

89. Display Awareness

Nexus should eventually understand:

Built-in Display
External Display
Resolution
Scale
Orientation
Position
Primary Display

This information could be used by:

Workspace restoration
Window management
System widgets
Multi-monitor layouts
90. Developer Experience

Nexus should eventually provide a developer mode for debugging the application itself.

Potential tools:

Nexus Debug
├── Event Monitor
├── Search Provider Inspector
├── Window Inspector
├── Plugin Inspector
├── Permission Inspector
└── Performance Monitor

This should only be available in development builds or behind an advanced setting.

91. Documentation Strategy

Documentation should grow alongside the project.

Suggested structure:

docs/
├── architecture/
├── development/
├── search/
├── window-management/
├── workspaces/
├── automation/
├── plugins/
├── security/
└── troubleshooting/

Documentation should explain concepts rather than only API details.

92. Roadmap Philosophy

The roadmap should prioritize foundational capabilities.

Recommended order:

Phase 1
Core + Sidebar


Phase 2
Applications + Windows


Phase 3
Search + Actions


Phase 4
Settings + Multi-monitor


Phase 5
Performance + Accessibility + Polish


Phase 6
Workspaces


Phase 7
System Controls


Phase 8
Automation


Phase 9
Plugins


Phase 10
AI Integration

This order may change based on user feedback and technical discoveries.

93. Avoid Feature Creep

Nexus should not attempt to become:

A full Finder replacement
A full Terminal replacement
A full Window Manager replacement
A full Notification Center replacement
A full Calendar replacement
A full AI assistant
A full automation IDE

Nexus should integrate with these systems rather than replace everything.

Its role is to become the command layer connecting them together.

94. Core Product Boundary

A useful rule:

If a feature helps the user quickly find, launch, switch, control, organize, or automate something on the Mac, it probably belongs in Nexus.

If a feature requires building an entirely separate productivity application inside Nexus, reconsider it.

95. Success Metrics

The project should eventually measure success through user experience rather than feature count.

Potential metrics:

Time to launch an application
Time to find a window
Time to find a file
Time to execute an action
Search response latency
Nexus startup time
Idle CPU usage
Memory usage
Crash rate

The most important qualitative question is:

Does Nexus make the Mac feel faster?

If the answer is no, adding more features is not the solution.

96. MVP-to-Vision Mapping

The MVP should establish foundations for the long-term architecture.

MVP Feature	Long-Term Capability
Sidebar	Command Center UI
App Launcher	Application Management
Running Apps	Context Awareness
Window Management	Workspace System
Search	Universal Command
Actions	Automation Engine
Settings	Profiles
Multi-monitor	Display-aware Workspaces
File Search	Universal Search
Architecture	Plugin Ecosystem

The MVP should therefore be intentionally small but architecturally meaningful.

97. What Nexus Should Feel Like

The ideal user experience is:

I want something
      ↓
⌘ Space
      ↓
Type naturally
      ↓
Nexus understands
      ↓
Select result
      ↓
Action happens

For visual interaction:

Move to edge
      ↓
Nexus appears
      ↓
See apps / windows / workspace
      ↓
Click
      ↓
Continue working

For power users:

Workspace
      ↓
Command
      ↓
Automation
      ↓
System Control
      ↓
Back to Work

The user should spend less time managing the Mac and more time using it.

98. Final Design Principle

Nexus should always ask:

Can this interaction be made faster without making the product more complicated?

If yes, do it.

If making an interaction faster requires adding unnecessary UI, reconsider the design.

Nexus should prefer:

One shortcut
One search
One action

over:

Open menu
Open submenu
Open settings
Find feature
Click button
Confirm
99. Final Engineering Principle

Build the simplest system that can support the next meaningful capability.

Do not build the entire future architecture today.

Do not create abstractions merely because they might be useful someday.

However, do not make architectural decisions that unnecessarily prevent future capabilities such as:

Workspaces
Plugins
Automation
System controls
AI
Multi-monitor support

The balance is:

Simple now, extensible later.

100. Final Project Statement

Nexus is an open-source native macOS command center designed to make everyday Mac interaction faster and more powerful.

It starts as a customizable Dock replacement.

It evolves into a launcher.

Then a universal search interface.

Then a workspace manager.

Then a system control layer.

Then an automation platform.

Eventually, Nexus becomes a unified interaction layer between the user and macOS.

The product should remain lightweight, local-first, privacy-conscious, extensible, and native throughout that evolution.

The final vision is:

                    NEXUS

             THE COMMAND CENTER
                   FOR MAC
                     │
       ┌─────────────┼─────────────┐
       │             │             │
     DISCOVER      CONTROL      AUTOMATE
       │             │             │
      Apps         Windows       Scripts
      Files        System        Workflows
      Windows      Displays      Actions
      Data         Network       Shortcuts
       │             │             │
       └─────────────┼─────────────┘
                     │
                  WORKSPACES
                     │
                  PLUGINS
                     │
                    AI

Nexus should make the Mac feel like it has a command center.

# 101. Non-Goals

Nexus should explicitly avoid becoming an application that tries to replace every macOS system application.

Nexus is NOT intended to become:

- A Finder replacement
- A Terminal replacement
- A full IDE
- A full browser
- A full email client
- A full calendar application
- A full notification center
- A complete AI operating system
- A cloud operating system
- A general-purpose desktop environment

Nexus should integrate with existing macOS applications instead of unnecessarily replacing them.

The goal is to provide a better interaction layer between the user and the existing Mac environment.

---

# 102. Decision-Making Framework

When deciding whether a feature belongs in Nexus, evaluate it using the following questions:

1. Does it make common Mac interactions faster?
2. Does it reduce repetitive user actions?
3. Does it improve discoverability?
4. Does it help users manage context?
5. Does it provide meaningful automation?
6. Does it integrate naturally with macOS?
7. Can it remain lightweight?
8. Can it be implemented without compromising privacy?

If most answers are "no", the feature should probably not be part of Nexus.

---

# 103. Feature Priority Framework

Features should be prioritized using four dimensions:

```text
User Value
Engineering Complexity
Performance Impact
Long-Term Strategic Value

A simple priority model:

High Value + Low Complexity
    → Build early

High Value + High Complexity
    → Plan carefully

Low Value + Low Complexity
    → Consider later

Low Value + High Complexity
    → Avoid
```

> **Editor note:** Sections 104–110 from the original ChatGPT conversation belong here. Paste them between this note and Section 111 below.

---

# 111. Technical Constraints & Decisions (Review Addendum)

This section was added during project review (2026-08-22) and updated with decisions made the same day. It records macOS platform realities and decisions that the design document must implement. Where this section conflicts with anything earlier in the document, this section wins.

## 111.1 Global Shortcut Strategy (DECIDED)

macOS reserves **Command+Space for Spotlight**. Nexus cannot programmatically take it or disable it.

Decision (2026-08-22): support both shortcuts; the user chooses during first-launch onboarding (see 111.6):

- **Option A — Command+Space:** onboarding shows a step-by-step guide to disable the Spotlight keyboard shortcut in System Settings → Keyboard → Keyboard Shortcuts → Spotlight, with a button that deep-links to that pane. Nexus cannot do this step for the user.
- **Option B — Option+Space (default, preselected):** Spotlight stays untouched.

Additional requirements:

- Shortcut remains fully rebindable in Settings; the Spotlight-conflict guide re-appears if the user selects Command+Space later.
- Until onboarding exists (Milestone 6), development builds default to Option+Space.
- Implementation: a supported global hotkey mechanism (e.g. `RegisterEventHotKey` from the Carbon HotKey API, still supported, or a modern wrapper). Global hotkeys do NOT require Accessibility permission.

## 111.2 Permission Reality Matrix

| Capability | macOS API | Required permission | Notes |
|---|---|---|---|
| List running apps | `NSWorkspace` / `NSRunningApplication` | None | Event-driven via KVO/notifications |
| Launch / quit apps | `NSWorkspace` | None | Quit other apps politely via `NSRunningApplication.terminate()` |
| Enumerate windows + titles | Accessibility (AX) API | **Accessibility** | Primary mechanism for window list, titles, activation |
| Activate a specific window | AX API (`AXUIElementPerformAction`) | **Accessibility** | |
| Window previews / thumbnails | ScreenCaptureKit | **Screen Recording** | macOS 15+ re-prompts periodically; treat previews as optional and degrade gracefully |
| File search | `NSMetadataQuery` (Spotlight index) | None for user-scope queries | Sandboxed apps get limited scope — see 111.3 |
| Launch at login | `SMAppService` | None (user-visible in System Settings) | macOS 13+ API |

Rules:

- Milestones 1–3 must require **zero permissions**.
- Milestone 4 (Windows) is the first Accessibility touchpoint — a contextual explain-and-grant screen ships with Milestone 4. The full onboarding wizard (111.6) ships with Milestone 6 and reuses the same permission screens.
- Window previews require Screen Recording. If the user declines, show title-only window lists. Previews are already "if feasible" in scope — this is the feasibility boundary.

## 111.3 Signing & Distribution (DECIDED)

The Accessibility API is **incompatible with the App Sandbox**, so Mac App Store distribution is off the table regardless of signing.

Decision (2026-08-22): no paid Apple Developer account for now — **self-signed local builds**.

- Sign with a free Apple ID "Apple Development" certificate (Personal Team), NOT ad-hoc signing. Reason: macOS TCC ties Accessibility / Screen Recording grants to the code signature; ad-hoc signatures change on every build, so granted permissions would reset on each rebuild. A stable development certificate plus a stable bundle identifier keeps grants sticky across builds.
- App Sandbox: disabled. Hardened Runtime: not required for local builds.
- Consequence: builds run on the developer's own Mac(s); other users would hit Gatekeeper blocks. Acceptable for the MVP.
- Public distribution later requires Developer ID + notarization (and a Homebrew cask). Revisit at first public release. Auto-updates via Sparkle stay out of MVP, consistent with Section 77.

## 111.4 Baseline Technical Decisions for the Design Document

The design document must fix these choices (recommended defaults in parentheses):

1. Project format (Xcode project generated or maintained by hand; SwiftPM for any internal modules).
2. Minimum deployment target (macOS 14.0, per Section 3).
3. UI hosting model (SwiftUI views inside `NSPanel`/`NSWindow` for sidebar and search palette — borderless, non-activating panels; AppKit `NSHostingView` where needed).
4. Settings persistence (`UserDefaults` with a versioned `Codable` configuration struct, per Sections 16 and 74).
5. Logging (`os.Logger` with subsystem `com.<team>.nexus` and categories from Section 66).
6. Test framework (Swift Testing for unit tests; XCUITest only for the critical flows in Section 67).
7. Concurrency model (Swift Concurrency / actors for services; main-actor isolation for UI state).
8. No third-party dependencies in the MVP unless a specific blocker is documented.

## 111.5 Known Spec Duplications (resolve during doc split)

The following section pairs cover the same ground and must be merged when this document is split into ROADMAP.md / ARCHITECTURE.md / FEATURES.md: 21↔40–41, 22↔45, 23↔46, 24↔48, 57↔100, 93↔101. Until the split, sections 36–103 take precedence over 21–27 where they conflict.

## 111.6 First-Launch Onboarding (DECIDED — added to MVP scope)

A mini walkthrough shown on first open. Ships with Milestone 6 (Settings), reusing the same configuration UI. Before Milestone 6, contextual permission prompts cover the gap (first use of window features at Milestone 4 triggers the Accessibility explain-and-grant screen).

Steps:

1. **Welcome** — one screen, what Nexus is.
2. **Search shortcut** — choose Command+Space (with the disable-Spotlight guide and deep link to System Settings, per 111.1) or Option+Space (default, preselected).
3. **Permissions** — explain Accessibility (window management — required for window features) and Screen Recording (window previews — optional, skippable). Buttons open the exact System Settings panes. Nexus polls grant status live and shows a checkmark once granted.
4. **Sidebar basics** — pick position (left/right) and pin first applications (offer currently running applications as candidates).
5. **Done** — sidebar appears. Onboarding never shows again unless relaunched from Settings.

Rules:

- Every step skippable; skipping applies safe defaults (Option+Space, no permissions granted).
- Nexus must remain functional with zero permissions (launcher, pinned apps, application search).
- Re-entry: Settings → "Run setup again"; each permission screen is also reachable individually from Settings.
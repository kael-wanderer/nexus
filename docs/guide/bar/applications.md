---
title: Applications
summary: Pin, reorder, launch, hide and quit apps, and drop files onto them.
---

Every app on the bar is a row with its icon. Pinned apps stay on the bar; running apps that are not pinned sit below them and go away when you quit them.

![The bar on the right edge with pinned and running apps, a group, a folder and the Trash](../images/start-here/first-five-minutes/bar.png)

## When to use it

- You want your usual apps one click away.
- You want to open a file in a particular app by dropping it on that app.
- You want to hide or quit an app without switching to it first.

## How to use it

### Pin and unpin an app

1. Right-click a running app that is not pinned and choose **Pin**.
2. Or drag an app from Finder, for example from the Applications folder, onto the bar.
3. Or drag a running app from the lower section up among the pinned ones. Dragging across the separator pins or unpins.
4. To unpin, right-click the app and choose **Unpin**, or drag it off the bar. It disappears with the same puff of smoke the Dock uses. A running app that is not pinned just stays where it is.

### Reorder the bar

1. Drag a row over another row. The other rows move aside as you drag.
2. Aim at the middle of the row under the pointer to group the two apps (see [Groups](groups.md)). Aim at the top or bottom end, or the left or right end on a horizontal bar, to place yours before or after it. A line shows where it will land.
3. Let go inside the bar to keep the new place.

You can also right-click a pinned app and choose **Move Up**, **Move Down** or **Move to End**.

### Edit mode

1. Press and hold a pinned row for about 600 ms (0.6 seconds).
2. The pinned rows get a minus badge and wobble slightly.
3. Click a minus badge to remove that row.
4. Click anywhere else, move the pointer off the bar, or wait about twenty seconds to leave edit mode.

With Reduce Motion on, the badges show but nothing wobbles.

### Launch and switch

- Click a row to open the app, or to bring it forward if it is running. While an app is starting its icon dims and hops.
- If you set **Clicking an icon** to **Shows its windows** in Settings > Behavior, a click shows the window flyout instead. See [Windows on the bar](windows.md).
- <kbd>⌥</kbd>-click a row to open the app and hide the app you were in.

### What the row shows

- A small dot beside the icon means the app is running. The dot is brighter for the frontmost app.
- A number on the icon is how many windows the app has. It only shows for two or more, and you can turn it off with **Window count badges** in Settings > Bar.
- A red badge is the same badge the app puts on its Dock icon, such as unread mail. It needs Accessibility. Without it, no badges show. A group shows a badge when any member has one.

### Right-click menu

For a running app the menu lists its windows, then:

- **Open**
- **Show All Windows**
- **Hide** and **Hide Others**. **Hide Others** brings this app forward and hides every other app.
- **Unpin** or **Pin**, **Move Up**, **Move Down**, **Move to End**
- **Remove from Group**, when the app is in a group
- **Show in Finder**
- **Quit** and **Force Quit**

**Quit** asks the app to close, the same as Quit in its own menu. Use **Force Quit** only if the app has stopped responding, because unsaved work is lost.

### Drop files on an app

1. Drag one or more files from Finder over an app row. The row is outlined.
2. Let go. The files open in that app. If the app is not running, Nexus starts it.

Some drops do something else:

- A drop that includes an app (a `.app`) pins that app.
- A drop of folders and nothing else pins each folder as a stack. See [Folder stacks](folder-stacks.md). Hold <kbd>⌥</kbd> while you drop to open the folders in the app instead.
- A drop of more than 64 files is refused, and so is anything that is not an existing file.

## What it will not do

- Window counts, the running dot and launching need no permission. Window lists, titles and Dock badges need Accessibility.
- It never quits an app unless you choose **Quit** or **Force Quit**.
- Two copies of the same app opened side by side show as one row.
- Hide and Hide Others only hide windows. Nothing is closed.

## Next steps

- [Groups](groups.md)
- [Folder stacks](folder-stacks.md)
- [Windows on the bar](windows.md)
- [Tidy a crowded bar](../recipes/tidy-the-bar.md)
- [Keyboard control](../windows/keyboard-control.md)
- [Privacy and permissions](../reference/privacy-and-permissions.md)

# Woosh

One menu bar app doing the job of a dozen Mac utilities. Free, open source, and everything runs locally on your Mac.

---

## Install Only What You Use

Nobody needs every utility active all the time, and Woosh is built around that. The **Features** hub lets you install and uninstall whole features with one click: what you uninstall disappears from the app and stops loading, consuming zero CPU, memory, or energy. Nothing is deleted, and re-enabling a feature immediately restores your previous settings.

First setup offers curated bundles (Essentials, Windows, and Battery), plus a visual picker for choosing individual features. Only the permissions required by your selections are requested.

---

## Everything It Does

### Windows and the Dock

- **Instant Spaces.** Instant desktop space switcher. Suppresses the slow system sliding animation to switch spaces immediately via 3-finger horizontal trackpad swipes or configurable global hotkeys (`⌥1` through `⌥9`). Includes an optional cutout space badge in the menu bar.
- **App switcher.** A richer take on pressing ⌘Tab, with adjustable live window thumbnails, minimized windows included, and multiple windows per app. Simple mode keeps every window and title without previews, with optional grouping to one entry per app.
- **Window layout.** Snap the active window to halves, thirds, sixths, corners, or center, maximize with or without margins, or move across displays. Supports live edge snapping previews and modifier-drag to move or resize anywhere on the window.
- **Dock Preview.** Hover over any Dock icon to inspect live window thumbnails with clear titles, and click to focus.
- **Dock clicks.** Click the Dock icon of the active app to minimize its windows, hide the app, or cycle through its open windows.
- **Maximize windows.** The green button fills the screen without creating a new Space, and restores on the next click.
- **Quit on close.** Chosen apps quit automatically when their last window closes.

### Sound

- **Volume mixer.** Adjust the Mac's overall volume or slide individual app volumes up or down, enter exact percentages, or boost quiet audio beyond 100%. Route system sounds through another output.
- **Per-app output.** Send music to speakers and a voice call to a headset simultaneously.
- **Output switcher.** Cycle through chosen audio outputs with a shortcut, and automatically drop volume when headphones disconnect.
- **Microphone tools.** Pin your preferred input device and mute all microphones at once with a click or shortcut.
- **Music app blocker.** Prevents Apple Music from launching automatically when headphones connect.

### System Monitor

- **System metrics.** Live CPU, GPU, memory, swap use, temperatures, and history graphs.
- **Fan control.** Continuous manual speeds, custom temperature curves, and live RPM readouts.
- **Menu bar readouts.** Display the metrics you care about directly in the menu bar, with numeric values or compact gauges (CPU, memory, battery time remaining, fan speed, network rates).
- **Network.** Live upload and download rates, session totals, and a built-in speed test.
- **Alerts.** Optional notifications for sustained CPU load, high temperature, memory pressure, low disk space, and low battery.

### Keyboard and Mouse

- **Smooth scrolling.** Gives mouse wheels the smooth inertial glide of a trackpad.
- **Scroll direction.** Invert mouse wheel direction vertically and horizontally without affecting the trackpad's natural scrolling.
- **Focus follows mouse.** Automatically raises the window under the pointer after an adjustable delay.
- **Side buttons & shortcuts.** Map mouse Back/Forward buttons and extra buttons to custom shortcuts or actions.
- **Middle click.** Three-finger tap or press acts as a native middle click.
- **Key debounce.** Filters out unintended duplicate keypresses from worn mechanical switches.
- **Super key.** Use Caps Lock as a universal modifier combination to trigger system-wide shortcuts easily.
- **Text snippets.** Expand abbreviations automatically or search snippets from a popup menu to paste at your cursor.

### Clipboard, Files and Links

- **Clipboard history.** Local history of copied text, images, and files with search, pinned favorites, and quick paste.
- **Auto-clear clipboard.** Automatically clear the system pasteboard after a set delay or when the Mac locks or sleeps.
- **Paste as plain text.** Shortcut to paste clean text stripped of styles, fonts, and colors.
- **Shelf.** Park files, images, or text near your cursor mid-drag or at screen edges, and drop them into place later.
- **Finder enhancements.** Cut and paste files with ⌘X / ⌘V, rename with F2, or paste copied images directly as files.
- **Clean URL.** Strips tracking parameters from copied web links automatically.
- **Disk image installer.** Mounts a DMG, installs the application to `/Applications`, unmounts, and cleans up in one click.

### Everyday Tools

- **Command Bar.** A universal launcher and action palette. Launch apps, run commands, trigger shortcuts, perform calculations, convert units, search files, and paste clipboard items.
- **Quick toggles.** Fast access to toggle Dark Mode, keyboard backlight, hide desktop icons, show hidden files, lock the screen, or empty Trash.
- **Radial menu.** Hold a shortcut or extra mouse button to bring up a radial wheel of frequent actions around the pointer.
- **Screen capture & recorder.** Capture screenshots or record areas, windows, or full screen with system audio and microphone inputs. Built-in editor for annotations, crops, redactions, stickers, and export.
- **Copy text from screen (OCR).** Select any on-screen area to extract text or read QR codes directly to the clipboard.
- **Color picker.** Inspect and copy hex, RGB, HSL, or SwiftUI color values from anywhere on your screens.
- **Camera preview.** Floating mirror overlay to check your framing and lighting before calls.
- **Scratchpad.** Floating markdown-friendly scratchpads for quick notes.
- **App updates.** Unified view of outdated apps from Homebrew and the App Store.
- **Cleaner & uninstaller.** Safely clear system caches, temporary files, and completely remove applications with their leftover preferences and support files.
- **Media tools.** Compress videos, convert image formats in batches, and create animated GIFs locally.
- **Cleaning Mode.** Temporarily locks keyboard and screen input while wiping down your Mac.

### Energy and Display

- **Keep awake.** Prevent sleep indefinitely or on a timer, with support for closed-lid mode with external displays.
- **Display controls.** Adjust brightness per display or turn individual monitors off.
- **Extra brightness.** Leverages HDR headroom on Apple Silicon XDR displays to push peak brightness higher outdoors.

---

## Private by Default

Woosh runs 100% locally on your machine. There are no user accounts, no telemetry, and no background tracking. Network access is strictly limited to user-requested actions (such as checking for updates, speed tests, or Homebrew package operations).

### Permissions Overview

Every permission is optional and requested only when you enable a feature that requires it:

| Permission | Used By | What Happens Without It |
|---|---|---|
| **Accessibility** | Instant Spaces, App Switcher, Window Layout, Mouse/Keyboard features, Snippets, Finder Cut & Paste | Those features remain disabled |
| **Screen Recording** | Window thumbnails, Screenshots, Screen Recording, Screen OCR | Visual capture features remain unavailable |
| **System Audio** | Per-app volume mixer and routing | Apps route audio normally |
| **Microphone** | Optional microphone track during screen recording | Recordings save without microphone audio |
| **Notifications** | Alerts for battery, temperatures, and system monitors | Alerts stay silent |
| **Full Disk Access** (Optional) | Deep cleaner and complete uninstaller scans | Only accessible user folders are scanned |

---

## Requirements

- Mac with Apple Silicon (M1/M2/M3/M4 or newer)
- macOS 14 Sonoma or newer (macOS 15 Sequoia supported)

---

## Building from Source

To compile and run Woosh locally using Xcode Command Line Tools:

```sh
# Compile and assemble the signed .app bundle
./build.sh

# Or compile and install directly into /Applications
./build.sh --install
```

To run the standalone unit test suite:

```sh
./build.sh --test
```

---

## License

Distributed under the [GNU General Public License v3.0 or later](LICENSE).

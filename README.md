# DiskUsage

<p align="right">
  <a href="README.zh-CN.md">中文</a> | English
</p>

DiskUsage is a native macOS disk usage browser inspired by the classic DiskWave app. It is built for quickly finding large files, large folders, and unexpected storage usage. After you choose a volume, folder, or common location, DiskUsage recursively measures allocated disk size and presents the result in Finder-style columns.

The project is currently built with Swift Package Manager. The UI is implemented with AppKit, and the main application code lives in `Sources/DiskUsage/main.swift`. The app does not scan automatically on launch; scans start only after the user selects a location from the sidebar or the toolbar.

## Features

- Native AppKit macOS app with a desktop-style window, toolbar, sidebar, and table interaction model.
- Scan mounted volumes, common user folders, or any folder selected through Open.
- Recursively calculate allocated disk size for files and folders, including hidden files returned by the file system.
- Finder-style column browser: each folder level appears as a separate fixed-width column with horizontal scrolling.
- Fast keyboard navigation: up/down changes selection, right arrow, Return, or double click enters a folder, and left arrow returns to the previous column.
- Live scan progress with completed top-level item count, scanned file/folder count, scanned bytes, and the current item.
- Cancellable scans; cancelled partial results are not written to cache.
- Completed scans are cached, while Refresh forces a rescan.
- Sort by size, name, kind, or modified date.
- Toolbar actions for Open, Refresh, Trash, Quick Look, Reveal, and sort selection.
- Move selected files to Trash, preview with Quick Look, or reveal selected items in Finder.
- Sidebar shows volume capacity, used space, and available space, with per-location refresh.
- Unreadable or permission-limited items are visually muted so permission boundaries are clear.

## Build And Run

Run during development:

```sh
swift run DiskUsage
```

Build the release executable:

```sh
swift build -c release
```

The repository also contains a manually generated app bundle. A typical bundle update flow is:

```sh
cp .build/release/DiskUsage build/DiskUsage.app/Contents/MacOS/DiskUsage
chmod +x build/DiskUsage.app/Contents/MacOS/DiskUsage
codesign --force --deep --sign - build/DiskUsage.app
ditto -c -k --keepParent build/DiskUsage.app build/DiskUsage.app.zip
codesign --verify --deep --strict --verbose=2 build/DiskUsage.app
```

Run the app bundle:

```sh
open build/DiskUsage.app
```

If `open` does not show the app window, run the executable directly to inspect launch behavior:

```sh
build/DiskUsage.app/Contents/MacOS/DiskUsage
```

## macOS Permissions

macOS may block access to protected locations such as Desktop, Documents, external volumes, or the system root. For broader scans, grant Full Disk Access in:

```text
System Settings -> Privacy & Security -> Full Disk Access
```

Grant access to DiskUsage, Xcode, Terminal, or whichever host process you use to launch the app.

# DiskUsage

DiskUsage is a native macOS disk usage browser inspired by the original DiskWave. It scans folders and volumes, calculates allocated disk size recursively, and presents the results in Finder-style columns for fast keyboard navigation.

## Run

```sh
swift run DiskUsage
```

You can also open `Package.swift` in Xcode and run the `DiskUsage` executable target.

## Current Features

- Native AppKit macOS app.
- Sidebar with mounted volumes and common places.
- Recursive size scanning, including hidden files returned by the file system.
- Finder-style column browser.
- Sort by size, name, kind, or modified date.
- Keyboard navigation: up/down selects rows, right enters a folder, left returns to the previous column.
- Toolbar actions: Open folder, Refresh, Trash, Quick Look, and Reveal in Finder.

## macOS Permissions

macOS may block access to protected folders such as Desktop, Documents, external volumes, or the full system root until permission is granted. For full-machine scans, grant the built app Full Disk Access in:

System Settings -> Privacy & Security -> Full Disk Access

When running from Xcode or SwiftPM during development, grant access to Xcode, Terminal, or the app host you use to launch DiskUsage.

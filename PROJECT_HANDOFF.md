# DiskUsage Project Handoff

Last updated: 2026-05-13, Asia/Shanghai.

## Project Goal

Build a native macOS app, now named **DiskUsage**, inspired by the old DiskWave app.

Core goal:

- Scan a selected folder or volume.
- Recursively calculate disk usage for files and folders, including hidden files when macOS permissions allow it.
- Present results in classic Finder-style columns.
- Support fast keyboard navigation: up/down selects rows, right enters a folder, left returns to the previous column.
- Cache completed scans and only rescan when the user refreshes.
- Show progress while scanning and allow cancellation.

Original references given by the user:

- https://diskwave.barthe.ph
- https://www.appinn.com/diskwave-for-osx/

## Current Workspace

The current workspace path before migration:

```text
/Users/treason/Documents/Projects/DiskWave‌2
```

Important current files:

```text
Package.swift
Sources/DiskUsage/main.swift
README.md
PROJECT_HANDOFF.md
build/DiskUsage.app
build/DiskUsage.app.zip
```

The repository directory may still contain the old folder name `DiskWave‌2`; that is only the filesystem workspace name. The app/project/product name has been changed to **DiskUsage**.

## Current Implementation

Technology:

- Swift Package Manager project.
- Native AppKit app.
- Main code lives in `Sources/DiskUsage/main.swift`.
- Target/product in `Package.swift` is `DiskUsage`.
- App bundle currently generated manually under `build/DiskUsage.app`.

Main components:

- `AppDelegate`: AppKit app lifecycle.
- `MainWindowController`: main window, toolbar, scan task coordination, sorting, refresh/cancel behavior.
- `DiskScanner`: actor that recursively scans directories, caches completed directory contents and sizes, and reports progress.
- `SidebarController`: left sidebar with mounted volumes and common places.
- `BrowserController`: Finder-style column browser.
- `FileColumnController`: one file-list column.
- `LoadingCell`: scanning/progress/cancel/placeholder UI cell.

## Behavior Already Implemented

- App does not auto-scan on launch.
- User starts a scan by clicking a sidebar location or choosing Open.
- Scans show progress, including completed top-level items, scanned file/folder count, scanned bytes, and current item.
- Completed scans are cached.
- Refresh forces a rescan.
- Cancel stops current scan and avoids writing partial results into cache.
- Toolbar actions:
  - Open
  - Refresh
  - Trash
  - Quick Look
  - Reveal
  - Sort dropdown
- The old top toolbar Cancel button was removed.
- Cancel is intended to appear inside the scanning progress card, to the right of the progress bar.
- Sort label text under the popup was removed.
- Reveal icon was changed to use Finder.app icon because the previous `finder` SF Symbol did not render.
- Sidebar default width is about 280 px and should be draggable.
- Initial placeholder/cancel/failure states should not show a progress bar.
- Right arrow/Return/double click enters a folder.
- Left arrow returns to the previous column.
- Up/down should only change selection, not trigger scanning.
- After entering a folder and scan completes, the new column auto-selects the first row and focuses it.

## Recent Important Fixes

### Auto Scan Removed

Earlier versions selected the first volume and scanned immediately on launch. This was changed so launch only shows a placeholder:

```text
Choose a folder or volume
Select a location on the left, or use Open, to start scanning.
```

### Partial Scan Data Fixed

Earlier versions showed partial/inaccurate results if scanning was still progressing or got cancelled. Current design:

- Only complete scans are cached.
- Cancelled tasks should not update the UI with partial results.
- A `scanGeneration` guard prevents old tasks from updating a newer view.

### Keyboard Navigation Fixed

Earlier, simply selecting a directory triggered scanning. Current intended behavior:

- Selection only selects.
- Right/Return/double-click opens.
- New column auto-selects first item after scan completes.

### Rename

The project was first created as `DiskWave2`, briefly interrupted while renaming to `DiskUsed`, then final decision was **DiskUsage**.

Current completed renames:

- `Sources/DiskUsed` was moved to `Sources/DiskUsage`.
- `Package.swift` uses package/product/target name `DiskUsage`.
- Window title is `DiskUsage`.
- Toolbar identifiers use `DiskUsage.*`.
- README uses `DiskUsage`.
- `build/DiskUsage.app` exists.
- `build/DiskUsage.app.zip` exists.
- `Info.plist` inside the app bundle was updated:
  - `CFBundleExecutable = DiskUsage`
  - `CFBundleIdentifier = ph.barthe.diskusage.local`
  - `CFBundleName = DiskUsage`
  - `CFBundleDisplayName = DiskUsage`

Old app artifact `build/DiskWave2.app` was moved to `build/DiskUsage.app`.
Old executable inside bundle was removed.

## Current Build Commands

Build release binary:

```sh
swift build -c release
```

Manual app bundle update flow:

```sh
cp .build/release/DiskUsage build/DiskUsage.app/Contents/MacOS/DiskUsage
chmod +x build/DiskUsage.app/Contents/MacOS/DiskUsage
codesign --force --deep --sign - build/DiskUsage.app
ditto -c -k --keepParent build/DiskUsage.app build/DiskUsage.app.zip
codesign --verify --deep --strict --verbose=2 build/DiskUsage.app
```

Run:

```sh
open build/DiskUsage.app
```

## Current Packaging Status

Before this handoff, `swift build -c release` succeeded after the rename:

```text
Compiling DiskUsage main.swift
Linking DiskUsage
Build complete
```

`build/DiskUsage.app` was signed and verified successfully:

```text
build/DiskUsage.app: valid on disk
build/DiskUsage.app: satisfies its Designated Requirement
```

Potential issue:

- A final `osascript` check failed to find process `DiskUsage`:

```text
System Events ... cannot get process "DiskUsage" (-1728)
```

This may mean the app did not launch, launched under a different process name, exited quickly, or macOS blocked/has not registered the renamed app yet. This should be checked first in the new workspace.

Suggested next check:

```sh
open build/DiskUsage.app
ps aux | rg 'DiskUsage|DiskWave'
build/DiskUsage.app/Contents/MacOS/DiskUsage
```

Running the executable directly may reveal startup errors.

## Known Current User-Reported Bug Before Rename

The user reported that even after an attempted fix:

1. When repeatedly using right arrow to enter deeper directories, the overall app window still grows wider.
2. Two-finger horizontal swipe across expanded columns still does not scroll the column structure.

Attempted fix:

- `BrowserController` was changed from `NSStackView` to a custom frame-managed document view:
  - `ColumnDocumentView: NSView`
  - column layout via manual frames
  - `NSScrollView.documentView = documentView`
  - each column gets fixed frame width `360`

This compiled and was packaged before the rename. However, after the rename, launch verification did not succeed, so the fix still needs real UI verification.

If the window still grows, likely places to inspect:

- `BrowserController.build()`
- `BrowserController.updateDocumentFrame()`
- Auto Layout constraints involving `browser.view`, `mainStack`, and `NSSplitView`
- Whether document view/frame is accidentally participating in Auto Layout
- Whether `NSScrollView` content hugging/compression resistance is allowing it to expand the window

Possible next technical direction:

- Ensure `browser.view` does not impose a large fitting size on parent.
- Set horizontal compression resistance/hugging of `browser.view` lower.
- Wrap browser scroll view in a container with fixed constraints to content view.
- Override document view intrinsic size to no intrinsic metric, already attempted:

```swift
final class ColumnDocumentView: NSView {
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
```

For horizontal trackpad scrolling:

- Confirm `NSScrollView.hasHorizontalScroller = true`.
- Confirm document width is larger than clip view width.
- Confirm `view.usesPredominantAxisScrolling = false`.
- Consider subclassing `NSScrollView` or clip view if trackpad events are not producing horizontal scroll.

## Permissions Notes

For full disk scanning on macOS, the app or launch host needs Full Disk Access:

```text
System Settings -> Privacy & Security -> Full Disk Access
```

During development, grant permission to Xcode, Terminal, or the final app depending on how it is launched.

## Earlier Directory Comparison Task

The user asked for read-only comparison of:

```text
/Volumes/SS970EP/--BACKUP-private
/Volumes/SS970EP/------WDSN550/TreNAS2/private
```

Important results:

- Both were scanned read-only.
- Left had `186543` files.
- Right had `186541` files.
- Both had `878` directories.
- Both were about `498.47 GiB`.
- Read errors: `0`.
- Left had 2 extra AppleDouble files:

```text
21-shasha-photo/IMG-202206/._IMG_20220615_201734.jpg
21-shasha-photo/IMG-202207/._IMG_20220730_114105.jpg
```

- Main real content difference found:

```text
00-treason-data/-TRE/Canon-Archive-2012.dmg
```

Left:

```text
/Volumes/SS970EP/--BACKUP-private/00-treason-data/-TRE/Canon-Archive-2012.dmg
size=16000020480
mtime=2022-04-26 19:07:38
sha256=782bf816ad5fecf3ef10ae5d1e7017465adaecaa14e32f0be56cc1fc912a57f6
```

Right:

```text
/Volumes/SS970EP/------WDSN550/TreNAS2/private/00-treason-data/-TRE/Canon-Archive-2012.dmg
size=16000020480
mtime=2022-04-26 19:07:40
sha256=f6d0c1100bfd5ce9a02a5fa1dd171674586713ca8d1d9733b4255719c74ff94c
```

Conclusion from that task:

- `TreNAS2/private` appears to be the newer copy overall.
- The only important non-AppleDouble content difference found was `Canon-Archive-2012.dmg`, with the right side newer by 2 seconds and different SHA-256.

## User Preferences / Product Direction

The user wants a practical native macOS utility, not a landing page or decorative UI.

UI should feel like old DiskWave/Finder:

- Dense and functional.
- Fast keyboard navigation.
- Classic columns.
- No unnecessary explanatory text in the main working UI.
- Friendly progress/cancel states only where useful.

When iterating, the user prefers direct implementation and repackaging over long proposals.

## Immediate Recommended Next Steps After Workspace Move

1. Open the new workspace.
2. Read this `PROJECT_HANDOFF.md`.
3. Run:

```sh
swift build -c release
```

4. Try launching directly:

```sh
build/DiskUsage.app/Contents/MacOS/DiskUsage
```

5. If direct launch works, regenerate and open app bundle:

```sh
cp .build/release/DiskUsage build/DiskUsage.app/Contents/MacOS/DiskUsage
codesign --force --deep --sign - build/DiskUsage.app
open build/DiskUsage.app
```

6. Verify the latest unresolved UI behavior:

- Window must not grow when repeatedly entering columns.
- Two-finger horizontal swipe should scroll column area.
- Right arrow into a folder should scroll to the loading/new column.


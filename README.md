# DiskUsage

<p align="right">
  <a href="#中文">中文</a> | <a href="#english">English</a>
</p>

---

<table width="100%">
  <tr>
    <td><h2 id="中文">中文</h2></td>
    <td align="right"><a href="#中文">中文</a> | <a href="#english">English</a></td>
  </tr>
</table>

DiskUsage 是一个原生 macOS 磁盘占用浏览器，灵感来自经典的 DiskWave。它面向需要快速定位大文件、大文件夹和异常占用空间的用户：选择一个磁盘、文件夹或常用位置后，DiskUsage 会递归统计已分配磁盘空间，并用类似 Finder 栏目视图的方式展示结果。

项目当前使用 Swift Package Manager 构建，界面基于 AppKit，主实现位于 `Sources/DiskUsage/main.swift`。应用不会在启动时自动扫描，用户可以从侧边栏或工具栏主动选择扫描位置。

### 功能介绍

- 原生 AppKit macOS 应用，窗口、工具栏、侧边栏和列表交互遵循 macOS 桌面体验。
- 支持扫描挂载卷、常用目录和通过 Open 手动选择的文件夹。
- 递归计算文件与文件夹的已分配磁盘大小，包括文件系统返回的隐藏文件。
- Finder 风格栏目浏览：每一层文件夹显示为独立列，支持水平滚动。
- 快速键盘导航：上下键移动选择，右键、Return 或双击进入文件夹，左键返回上一列。
- 扫描进度展示：显示顶层完成数量、已扫描文件/文件夹数量、已扫描字节数和当前项目。
- 支持取消扫描，取消后的部分结果不会写入缓存。
- 完整扫描结果会被缓存；刷新时可强制重新扫描。
- 支持按大小、名称、类型或修改时间排序。
- 工具栏提供 Open、Refresh、Trash、Quick Look、Reveal 和排序选择。
- 支持将选中文件移入废纸篓、Quick Look 预览以及在 Finder 中定位。
- 侧边栏显示磁盘容量、已用空间和可用空间，并支持刷新单个位置。
- 不可读或受权限限制的项目会以较弱样式显示，避免误以为扫描失败。

### 构建与运行

开发时可以直接运行：

```sh
swift run DiskUsage
```

构建 release 可执行文件：

```sh
swift build -c release
```

当前仓库也包含手动生成的 app bundle。更新 bundle 的常用流程：

```sh
cp .build/release/DiskUsage build/DiskUsage.app/Contents/MacOS/DiskUsage
chmod +x build/DiskUsage.app/Contents/MacOS/DiskUsage
codesign --force --deep --sign - build/DiskUsage.app
ditto -c -k --keepParent build/DiskUsage.app build/DiskUsage.app.zip
codesign --verify --deep --strict --verbose=2 build/DiskUsage.app
```

运行 app bundle：

```sh
open build/DiskUsage.app
```

如果 `open` 没有启动窗口，可直接运行可执行文件来查看启动状态：

```sh
build/DiskUsage.app/Contents/MacOS/DiskUsage
```

### macOS 权限

macOS 可能会限制 Desktop、Documents、外置磁盘、系统根目录等受保护路径。若要进行更完整的磁盘扫描，请在：

```text
System Settings -> Privacy & Security -> Full Disk Access
```

为 DiskUsage、Xcode、Terminal 或实际启动应用的宿主程序授予 Full Disk Access。

---

<table width="100%">
  <tr>
    <td><h2 id="english">English</h2></td>
    <td align="right"><a href="#中文">中文</a> | <a href="#english">English</a></td>
  </tr>
</table>

DiskUsage is a native macOS disk usage browser inspired by the classic DiskWave app. It is built for quickly finding large files, large folders, and unexpected storage usage. After you choose a volume, folder, or common location, DiskUsage recursively measures allocated disk size and presents the result in Finder-style columns.

The project is currently built with Swift Package Manager. The UI is implemented with AppKit, and the main application code lives in `Sources/DiskUsage/main.swift`. The app does not scan automatically on launch; scans start only after the user selects a location from the sidebar or the toolbar.

### Features

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

### Build And Run

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

### macOS Permissions

macOS may block access to protected locations such as Desktop, Documents, external volumes, or the system root. For broader scans, grant Full Disk Access in:

```text
System Settings -> Privacy & Security -> Full Disk Access
```

Grant access to DiskUsage, Xcode, Terminal, or whichever host process you use to launch the app.

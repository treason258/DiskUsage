# DiskUsage

<p align="right">
  中文 | <a href="README.md">English</a>
</p>

DiskUsage 是一个原生 macOS 磁盘占用浏览器，灵感来自经典的 DiskWave。它面向需要快速定位大文件、大文件夹和异常占用空间的用户：选择一个磁盘、文件夹或常用位置后，DiskUsage 会递归统计已分配磁盘空间，并用类似 Finder 栏目视图的方式展示结果。

项目当前使用 Swift Package Manager 构建，界面基于 AppKit，主实现位于 `Sources/DiskUsage/main.swift`。应用不会在启动时自动扫描，用户可以从侧边栏或工具栏主动选择扫描位置。

## 功能介绍

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

## 构建与运行

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

## macOS 权限

macOS 可能会限制 Desktop、Documents、外置磁盘、系统根目录等受保护路径。若要进行更完整的磁盘扫描，请在：

```text
System Settings -> Privacy & Security -> Full Disk Access
```

为 DiskUsage、Xcode、Terminal 或实际启动应用的宿主程序授予 Full Disk Access。

import AppKit
import QuickLookUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        controller = MainWindowController()
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

enum SortMode: String, CaseIterable {
    case name = "Sort by Name"
    case size = "Sort by Size"
    case kind = "Sort by Kind"
    case modified = "Sort by Modified"
}

struct FileItem: Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let size: Int64
    let modified: Date?
    let isReadable: Bool
    let error: String?

    var canBrowse: Bool {
        isDirectory && !isPackage && isReadable
    }
}

struct LocationItem: Hashable {
    let url: URL
    let title: String
    let subtitle: String
    let icon: NSImage
    let isVolume: Bool
}

struct ScanProgress {
    let url: URL
    let currentItem: String
    let completedItems: Int
    let totalItems: Int
    let scannedDescendants: Int
    let scannedBytes: Int64

    var fraction: Double {
        guard totalItems > 0 else { return 0 }
        return min(1, Double(completedItems) / Double(totalItems))
    }

    var title: String {
        totalItems == 0 ? "Scanning..." : "Scanning \(completedItems)/\(totalItems)"
    }

    var detail: String {
        let scanned = "\(scannedDescendants.formatted()) files/folders"
        let size = MainWindowController.formatSize(scannedBytes)
        if currentItem.isEmpty {
            return "\(scanned), \(size)"
        }
        return "\(scanned), \(size) - \(currentItem)"
    }
}

struct ScanResult {
    let items: [FileItem]
    let fromCache: Bool
}

private struct ScanStats {
    let bytes: Int64
    let descendants: Int
}

struct LoadingState {
    let title: String
    let detail: String
    let fraction: Double
    let showsProgress: Bool
}

actor DiskScanner {
    private var directoryCache: [URL: [FileItem]] = [:]
    private var sizeCache: [URL: Int64] = [:]

    func clear(url: URL? = nil) {
        if let url {
            let key = canonical(url)
            directoryCache = directoryCache.filter { !$0.key.path.hasPrefix(key.path) }
            sizeCache = sizeCache.filter { !$0.key.path.hasPrefix(key.path) }
        } else {
            directoryCache.removeAll()
            sizeCache.removeAll()
        }
    }

    func contents(
        of url: URL,
        force: Bool = false,
        progress: @escaping (ScanProgress) async -> Void
    ) async throws -> ScanResult {
        let key = canonical(url)
        if !force, let cached = directoryCache[key] {
            return ScanResult(items: cached, fromCache: true)
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .localizedNameKey,
            .nameKey,
            .contentModificationDateKey,
            .isReadableKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]

        try Task.checkCancellation()
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return ScanResult(items: [], fromCache: false)
        }

        await progress(ScanProgress(url: url, currentItem: "", completedItems: 0, totalItems: children.count, scannedDescendants: 0, scannedBytes: 0))
        var items: [FileItem] = []
        var completedItems = 0
        var scannedDescendants = 0
        var scannedBytes: Int64 = 0

        for child in children {
            try Task.checkCancellation()
            let (item, stats) = try await item(
                for: child,
                keys: keys,
                force: force,
                rootURL: url,
                completedItems: completedItems,
                totalItems: children.count,
                baseScannedDescendants: scannedDescendants,
                baseScannedBytes: scannedBytes,
                progress: progress
            )
            items.append(item)
            completedItems += 1
            scannedDescendants += stats.descendants
            scannedBytes += stats.bytes
            await progress(ScanProgress(url: url, currentItem: item.name, completedItems: completedItems, totalItems: children.count, scannedDescendants: scannedDescendants, scannedBytes: scannedBytes))
        }

        try Task.checkCancellation()
        directoryCache[key] = items
        return ScanResult(items: items, fromCache: false)
    }

    private func item(
        for url: URL,
        keys: Set<URLResourceKey>,
        force: Bool,
        rootURL: URL,
        completedItems: Int,
        totalItems: Int,
        baseScannedDescendants: Int,
        baseScannedBytes: Int64,
        progress: @escaping (ScanProgress) async -> Void
    ) async throws -> (FileItem, ScanStats) {
        do {
            let values = try url.resourceValues(forKeys: keys)
            let isDirectory = values.isDirectory ?? false
            let isPackage = values.isPackage ?? false
            let isSymlink = values.isSymbolicLink ?? false
            let isReadable = values.isReadable ?? FileManager.default.isReadableFile(atPath: url.path)
            let stats: ScanStats

            if isDirectory && !isPackage && !isSymlink && isReadable {
                stats = try await directorySize(
                    url,
                    force: force,
                    rootURL: rootURL,
                    currentItem: values.localizedName ?? values.name ?? url.lastPathComponent,
                    completedItems: completedItems,
                    totalItems: totalItems,
                    baseScannedDescendants: baseScannedDescendants,
                    baseScannedBytes: baseScannedBytes,
                    progress: progress
                )
            } else {
                stats = ScanStats(bytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0), descendants: 1)
            }

            let item = FileItem(
                url: url,
                name: values.localizedName ?? values.name ?? url.lastPathComponent,
                isDirectory: isDirectory,
                isPackage: isPackage,
                size: stats.bytes,
                modified: values.contentModificationDate,
                isReadable: isReadable,
                error: nil
            )
            return (item, stats)
        } catch {
            if error is CancellationError {
                throw error
            }
            let item = FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: false,
                isPackage: false,
                size: 0,
                modified: nil,
                isReadable: false,
                error: error.localizedDescription
            )
            return (item, ScanStats(bytes: 0, descendants: 1))
        }
    }

    private func directorySize(
        _ url: URL,
        force: Bool,
        rootURL: URL,
        currentItem: String,
        completedItems: Int,
        totalItems: Int,
        baseScannedDescendants: Int,
        baseScannedBytes: Int64,
        progress: @escaping (ScanProgress) async -> Void
    ) async throws -> ScanStats {
        let key = canonical(url)
        if !force, let cached = sizeCache[key] {
            return ScanStats(bytes: cached, descendants: 1)
        }

        var total: Int64 = 0
        var descendants = 1
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isReadableKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return ScanStats(bytes: 0, descendants: 1)
        }

        for case let child as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try child.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    continue
                }
                descendants += 1
                if values.isDirectory == true && values.isPackage != true && values.isReadable == false {
                    enumerator.skipDescendants()
                    continue
                }
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                if descendants.isMultiple(of: 500) {
                    await progress(ScanProgress(
                        url: rootURL,
                        currentItem: currentItem,
                        completedItems: completedItems,
                        totalItems: totalItems,
                        scannedDescendants: baseScannedDescendants + descendants,
                        scannedBytes: baseScannedBytes + total
                    ))
                }
            } catch {
                continue
            }
        }

        try Task.checkCancellation()
        sizeCache[key] = total
        return ScanStats(bytes: total, descendants: descendants)
    }

    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

final class MainWindowController: NSWindowController {
    private let scanner = DiskScanner()
    private let sidebar = SidebarController()
    private let browser = BrowserController()
    private var pathControl = NSPathControl()
    private var statusLabel = NSTextField(labelWithString: "Ready")
    private var sortMode: SortMode = .size
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var isScanning = false
    private let sidebarDefaultWidth: CGFloat = 280

    private var selectedURL: URL? {
        browser.selectedURL ?? sidebar.selectedLocation?.url
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1260, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "DiskUsage"
        window.minSize = NSSize(width: 900, height: 520)
        window.toolbar = makeToolbar()
        window.titleVisibility = .visible
        buildUI()
        loadLocations()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let split = NSSplitView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.isVertical = true
        split.dividerStyle = .thin

        let sidebarView = sidebar.view
        sidebarView.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        sidebarView.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8
        topBar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        pathControl.pathStyle = .standard
        pathControl.isEditable = false
        pathControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingMiddle

        topBar.addArrangedSubview(pathControl)
        topBar.addArrangedSubview(statusLabel)

        mainStack.addArrangedSubview(topBar)
        mainStack.addArrangedSubview(browser.view)
        browser.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        split.addArrangedSubview(sidebarView)
        split.addArrangedSubview(mainStack)
        contentView.addSubview(split)
        let initialSidebarWidth = sidebarDefaultWidth
        DispatchQueue.main.async { [weak split] in
            split?.setPosition(initialSidebarWidth, ofDividerAt: 0)
        }

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            split.topAnchor.constraint(equalTo: contentView.topAnchor),
            split.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        sidebar.onSelect = { [weak self] location in
            self?.openRoot(location.url)
        }
        sidebar.onRefresh = { [weak self] location in
            self?.refresh(url: location.url)
        }
        browser.onSelectDirectory = { [weak self] url, column, force in
            self?.loadColumn(for: url, after: column, force: force)
        }
        browser.onSelectionChanged = { [weak self] url in
            self?.pathControl.url = url
        }
        browser.onCancelScan = { [weak self] in
            self?.cancelCurrentScan(resetLoading: true)
        }
    }

    private func loadLocations() {
        sidebar.locations = LocationProvider.locations()
        browser.showPlaceholder(
            title: "Choose a folder or volume",
            detail: "Select a location on the left, or use Open, to start scanning."
        )
        statusLabel.stringValue = "Ready"
    }

    private func openRoot(_ url: URL) {
        cancelCurrentScan(resetLoading: false)
        pathControl.url = url
        browser.reset(root: url)
        loadColumn(for: url, after: -1)
    }

    private func refresh(url: URL? = nil) {
        cancelCurrentScan(resetLoading: false)
        if let url {
            if url == sidebar.selectedLocation?.url {
                pathControl.url = url
                browser.reset(root: url)
                loadColumn(for: url, after: -1, force: true)
            } else {
                browser.reloadVisible(url: url, force: true)
            }
        } else if let root = sidebar.selectedLocation?.url {
            pathControl.url = root
            browser.reset(root: root)
            loadColumn(for: root, after: -1, force: true)
        }
        sidebar.locations = LocationProvider.locations()
    }

    private func loadColumn(for url: URL, after column: Int, force: Bool = false) {
        cancelCurrentScan(resetLoading: false)
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        window?.toolbar?.validateVisibleItems()
        statusLabel.stringValue = force ? "Refreshing \(url.path)" : "Scanning \(url.path)"
        browser.showLoading(after: column, title: force ? "Refreshing..." : "Scanning...", detail: url.path, fraction: 0)
        scanTask = Task { [weak self] in
            guard let self else { return }
            if force {
                await scanner.clear(url: url)
            }

            do {
                let result = try await scanner.contents(of: url, force: force) { [weak self] progress in
                    await MainActor.run {
                        guard let self, self.scanGeneration == generation else { return }
                        self.browser.updateLoading(after: column, progress: progress)
                        self.statusLabel.stringValue = "\(progress.title) - \(progress.detail)"
                    }
                }
                try Task.checkCancellation()
                let sorted = self.sorted(result.items)
                await MainActor.run {
                    guard self.scanGeneration == generation else { return }
                    self.isScanning = false
                    self.browser.set(items: sorted, for: url, after: column)
                    let source = result.fromCache ? "Loaded from cache" : "Scan complete"
                    self.statusLabel.stringValue = "\(source): \(sorted.count) items, \(Self.formatSize(sorted.reduce(0) { $0 + $1.size }))"
                    self.window?.toolbar?.validateVisibleItems()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.scanGeneration == generation else { return }
                    self.isScanning = false
                    self.browser.showCancelled(after: column)
                    self.statusLabel.stringValue = "Scan cancelled"
                    self.window?.toolbar?.validateVisibleItems()
                }
                return
            } catch {
                await MainActor.run {
                    guard self.scanGeneration == generation else { return }
                    self.isScanning = false
                    self.browser.showError(after: column, message: error.localizedDescription)
                    self.statusLabel.stringValue = "Scan failed"
                    self.window?.toolbar?.validateVisibleItems()
                }
            }
        }
    }

    private func cancelCurrentScan(resetLoading: Bool) {
        guard scanTask != nil || isScanning else { return }
        scanTask?.cancel()
        scanTask = nil
        scanGeneration += 1
        isScanning = false
        if resetLoading {
            browser.showCancelled()
            statusLabel.stringValue = "Scan cancelled"
        }
        window?.toolbar?.validateVisibleItems()
    }

    private func sorted(_ items: [FileItem]) -> [FileItem] {
        items.sorted { lhs, rhs in
            switch sortMode {
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                if lhs.size == rhs.size {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.size > rhs.size
            case .kind:
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .modified:
                return (lhs.modified ?? .distantPast) > (rhs.modified ?? .distantPast)
            }
        }
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "DiskUsage.Toolbar")
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        toolbar.delegate = self
        return toolbar
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder or volume to scan. DiskUsage can see protected areas only after macOS grants permission."
        if panel.runModal() == .OK, let url = panel.url {
            let item = LocationItem(url: url, title: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, subtitle: url.path, icon: NSWorkspace.shared.icon(forFile: url.path), isVolume: false)
            sidebar.addCustomLocation(item)
            sidebar.select(location: item)
            openRoot(url)
        }
    }

    @objc private func revealSelected() {
        guard let url = selectedURL else { return }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    @objc private func quickLookSelected() {
        guard selectedURL != nil else { return }
        QLPreviewPanel.shared()?.dataSource = self
        QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
    }

    @objc private func trashSelected() {
        guard let url = browser.selectedURL else { return }
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = url.path
        alert.addButton(withTitle: "Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            refresh(url: sidebar.selectedLocation?.url)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func sortChanged(_ sender: NSPopUpButton) {
        guard let mode = SortMode.allCases[safe: sender.indexOfSelectedItem] else { return }
        sortMode = mode
        browser.resortVisible(using: sorted)
    }

    @objc private func cancelScan() {
        cancelCurrentScan(resetLoading: true)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "DiskUsage"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    static func formatSize(_ size: Int64) -> String {
        if size == 0 { return "0 bytes" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: size)
    }
}

extension MainWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openFolder, .refreshAll, .trash, .quickLook, .reveal, .sort, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openFolder, .refreshAll, .flexibleSpace, .trash, .quickLook, .reveal, .sort]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .openFolder:
            return toolbarItem(itemIdentifier, label: "Open", image: NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil), action: #selector(chooseFolder))
        case .refreshAll:
            return toolbarItem(itemIdentifier, label: "Refresh", image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil), action: #selector(refreshToolbar))
        case .trash:
            return toolbarItem(itemIdentifier, label: "Trash", image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil), action: #selector(trashSelected))
        case .quickLook:
            return toolbarItem(itemIdentifier, label: "Quick Look", image: NSImage(systemSymbolName: "eye", accessibilityDescription: nil), action: #selector(quickLookSelected))
        case .reveal:
            return toolbarItem(itemIdentifier, label: "Reveal", image: NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"), action: #selector(revealSelected))
        case .sort:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 32), pullsDown: false)
            popup.addItems(withTitles: SortMode.allCases.map(\.rawValue))
            popup.selectItem(at: SortMode.allCases.firstIndex(of: sortMode) ?? 0)
            popup.target = self
            popup.action = #selector(sortChanged)
            item.label = ""
            item.paletteLabel = "Sort Order"
            item.view = popup
            return item
        default:
            return nil
        }
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier, label: String, image: NSImage?, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.image = image
        item.target = self
        item.action = action
        return item
    }

    @objc private func refreshToolbar() {
        refresh()
    }
}

extension MainWindowController: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        selectedURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        selectedURL as NSURL?
    }
}

extension NSToolbarItem.Identifier {
    static let openFolder = NSToolbarItem.Identifier("DiskUsage.OpenFolder")
    static let refreshAll = NSToolbarItem.Identifier("DiskUsage.Refresh")
    static let trash = NSToolbarItem.Identifier("DiskUsage.Trash")
    static let quickLook = NSToolbarItem.Identifier("DiskUsage.QuickLook")
    static let reveal = NSToolbarItem.Identifier("DiskUsage.Reveal")
    static let sort = NSToolbarItem.Identifier("DiskUsage.Sort")
}

final class SidebarController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSView()
    var onSelect: ((LocationItem) -> Void)?
    var onRefresh: ((LocationItem) -> Void)?

    var locations: [LocationItem] = [] {
        didSet { table.reloadData() }
    }

    var selectedLocation: LocationItem? {
        let row = table.selectedRow
        guard row >= 0, row < locations.count else { return nil }
        return locations[row]
    }

    private let table = NSTableView()

    override init() {
        super.init()
        build()
    }

    private func build() {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.86).cgColor

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let column = NSTableColumn(identifier: .init("location"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 64
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(openSelected)

        scroll.documentView = table
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func addCustomLocation(_ item: LocationItem) {
        if !locations.contains(where: { $0.url == item.url }) {
            locations.append(item)
        }
    }

    func select(location: LocationItem) {
        guard let index = locations.firstIndex(where: { $0.url == location.url }) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        locations.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = SidebarCell()
        let location = locations[row]
        cell.configure(with: location, refreshAction: { [weak self, location] in
            self?.onRefresh?(location)
        })
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let selectedLocation else { return }
        onSelect?(selectedLocation)
    }

    @objc private func openSelected() {
        guard let selectedLocation else { return }
        onSelect?(selectedLocation)
    }
}

final class SidebarCell: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()
    private var refreshAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        wantsLayer = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: nil)
        refreshButton.isBordered = false
        refreshButton.target = self
        refreshButton.action = #selector(refresh)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(refreshButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 38),
            iconView.heightAnchor.constraint(equalToConstant: 38),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -6),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 24),
            refreshButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    func configure(with item: LocationItem, refreshAction: @escaping () -> Void) {
        iconView.image = item.icon
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
        self.refreshAction = refreshAction
    }

    @objc private func refresh() {
        refreshAction?()
    }
}

final class BrowserController: NSObject {
    private let columnWidth: CGFloat = 360
    let view = NSScrollView()
    var onSelectDirectory: ((URL, Int, Bool) -> Void)?
    var onSelectionChanged: ((URL) -> Void)?
    var onCancelScan: (() -> Void)?
    var selectedURL: URL? {
        columns.compactMap { $0.selectedItem?.url }.last
    }

    private let documentView = ColumnDocumentView()
    private var columns: [FileColumnController] = []

    override init() {
        super.init()
        build()
    }

    private func build() {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hasHorizontalScroller = true
        view.hasVerticalScroller = false
        view.autohidesScrollers = false
        view.usesPredominantAxisScrolling = false
        view.borderType = .noBorder
        view.drawsBackground = false

        documentView.frame = NSRect(origin: .zero, size: NSSize(width: columnWidth, height: 1))
        view.documentView = documentView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: view.contentView
        )
    }

    func reset(root: URL) {
        columns.forEach { $0.view.removeFromSuperview() }
        columns.removeAll()
    }

    func showPlaceholder(title: String, detail: String) {
        columns.forEach { $0.view.removeFromSuperview() }
        columns.removeAll()
        let placeholder = FileColumnController(url: nil, items: [])
        placeholder.loadingState = LoadingState(title: title, detail: detail, fraction: 0, showsProgress: false)
        append(placeholder)
        scrollToStart()
    }

    func showLoading(after column: Int, title: String, detail: String, fraction: Double) {
        trim(after: column)
        let loading = FileColumnController(url: nil, items: [])
        loading.loadingState = LoadingState(title: title, detail: detail, fraction: fraction, showsProgress: true)
        loading.onCancel = { [weak self] in self?.onCancelScan?() }
        append(loading)
        scrollToEnd()
    }

    func updateLoading(after column: Int, progress: ScanProgress) {
        let loadingIndex = column + 1
        guard loadingIndex >= 0, loadingIndex < columns.count else { return }
        columns[loadingIndex].loadingState = LoadingState(title: progress.title, detail: progress.detail, fraction: progress.fraction, showsProgress: true)
    }

    func showError(after column: Int, message: String) {
        let loadingIndex = column + 1
        guard loadingIndex >= 0, loadingIndex < columns.count else { return }
        columns[loadingIndex].loadingState = LoadingState(title: "Scan failed", detail: message, fraction: 0, showsProgress: false)
    }

    func showCancelled(after column: Int? = nil) {
        if let column {
            let loadingIndex = column + 1
            guard loadingIndex >= 0, loadingIndex < columns.count else { return }
            columns[loadingIndex].loadingState = LoadingState(title: "Scan cancelled", detail: "Choose a folder or refresh to scan again.", fraction: 0, showsProgress: false)
        } else if let last = columns.last, last.loadingState != nil {
            last.loadingState = LoadingState(title: "Scan cancelled", detail: "Choose a folder or refresh to scan again.", fraction: 0, showsProgress: false)
        }
    }

    func set(items: [FileItem], for url: URL, after column: Int) {
        trim(after: column)
        let controller = FileColumnController(url: url, items: items)
        controller.onSelect = { [weak self, weak controller] item in
            guard let self, let controller, let index = self.columns.firstIndex(of: controller) else { return }
            self.onSelectionChanged?(item.url)
            self.trim(after: index)
        }
        controller.onOpen = { [weak self, weak controller] item in
            guard let self, let controller, let index = self.columns.firstIndex(of: controller) else { return }
            self.onSelectionChanged?(item.url)
            if item.canBrowse {
                self.onSelectDirectory?(item.url, index, false)
            } else {
                self.trim(after: index)
            }
        }
        append(controller)
        controller.selectFirstItem()
        controller.focus()
        scrollToEnd()
    }

    func reloadVisible(url: URL, force: Bool = false) {
        guard let index = columns.firstIndex(where: { $0.url == url }) else { return }
        trim(after: index - 1)
        onSelectDirectory?(url, index - 1, force)
    }

    func resortVisible(using sorter: ([FileItem]) -> [FileItem]) {
        for column in columns {
            column.items = sorter(column.items)
        }
    }

    private func append(_ controller: FileColumnController) {
        columns.append(controller)
        controller.onMoveLeft = { [weak self, weak controller] in
            guard let self, let controller, let index = self.columns.firstIndex(of: controller), index > 0 else { return }
            self.trim(after: index - 1)
            self.columns[index - 1].focus()
        }
        controller.onMoveRight = { [weak controller] in
            guard let item = controller?.selectedItem, item.canBrowse else { return }
            controller?.onOpen?(item)
        }
        controller.view.translatesAutoresizingMaskIntoConstraints = true
        controller.view.autoresizingMask = [.height]
        documentView.addSubview(controller.view)
        updateDocumentFrame()
    }

    private func trim(after column: Int) {
        let keepCount = max(0, column + 1)
        guard columns.count > keepCount else { return }
        let removed = columns.suffix(columns.count - keepCount)
        removed.forEach { $0.view.removeFromSuperview() }
        columns.removeLast(columns.count - keepCount)
        updateDocumentFrame()
    }

    private func scrollToStart() {
        updateDocumentFrame()
        view.contentView.scroll(to: NSPoint(x: 0, y: 0))
        view.reflectScrolledClipView(view.contentView)
    }

    private func scrollToEnd() {
        updateDocumentFrame()
        view.layoutSubtreeIfNeeded()
        let maxX = max(0, documentView.bounds.width - view.contentView.bounds.width)
        view.contentView.scroll(to: NSPoint(x: maxX, y: 0))
        view.reflectScrolledClipView(view.contentView)
    }

    private func updateDocumentFrame() {
        let visible = view.contentView.bounds.size
        let width = max(CGFloat(columns.count) * columnWidth, visible.width)
        let height = max(visible.height, 1)
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        for (index, column) in columns.enumerated() {
            column.view.frame = NSRect(x: CGFloat(index) * columnWidth, y: 0, width: columnWidth, height: height)
        }
    }

    @objc private func contentViewBoundsDidChange() {
        updateDocumentFrame()
    }
}

final class ColumnDocumentView: NSView {
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

final class FileColumnController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSScrollView()
    let url: URL?
    var onSelect: ((FileItem) -> Void)?
    var onOpen: ((FileItem) -> Void)?
    var onMoveLeft: (() -> Void)?
    var onMoveRight: (() -> Void)?
    var onCancel: (() -> Void)?
    var selectedItem: FileItem? {
        let row = table.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    var items: [FileItem] {
        didSet { table.reloadData() }
    }

    var loadingState: LoadingState? {
        didSet { table.reloadData() }
    }

    private let table = KeyTableView()

    init(url: URL?, items: [FileItem]) {
        self.url = url
        self.items = items
        super.init()
        build()
    }

    private func build() {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hasVerticalScroller = true
        view.hasHorizontalScroller = false
        view.autohidesScrollers = false
        view.borderType = .lineBorder

        let column = NSTableColumn(identifier: .init("file"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 24
        table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = false
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        table.onLeftArrow = { [weak self] in self?.onMoveLeft?() }
        table.onRightArrow = { [weak self] in self?.onMoveRight?() }
        table.onReturn = { [weak self] in self?.openSelected() }
        table.doubleAction = #selector(openSelected)
        view.documentView = table
    }

    func focus() {
        view.window?.makeFirstResponder(table)
    }

    func selectFirstItem() {
        guard loadingState == nil, !items.isEmpty else { return }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.scrollRowToVisible(0)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        loadingState == nil ? items.count : 1
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let loadingState {
            let cell = LoadingCell()
            cell.configure(with: loadingState, cancelAction: onCancel)
            return cell
        }
        let cell = FileCell()
        cell.configure(with: items[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let loadingState else { return 24 }
        return loadingState.showsProgress ? 96 : 68
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let selectedItem else { return }
        onSelect?(selectedItem)
    }

    @objc private func openSelected() {
        guard let item = selectedItem else { return }
        if item.canBrowse {
            onOpen?(item)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}

final class KeyTableView: NSTableView {
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onLeftArrow?()
        case 124:
            onRightArrow?()
        default:
            guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else {
                super.keyDown(with: event)
                return
            }
            switch Int(scalar.value) {
            case NSEnterCharacter, NSCarriageReturnCharacter:
                onReturn?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}

final class LoadingCell: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let cancelButton = NSButton()
    private var cancelAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byTruncatingMiddle

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        cancelButton.bezelStyle = .texturedRounded
        cancelButton.isBordered = false
        cancelButton.target = self
        cancelButton.action = #selector(cancel)

        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(progress)
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            progress.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            progress.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 10),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            cancelButton.centerYAnchor.constraint(equalTo: progress.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    func configure(with state: LoadingState, cancelAction: (() -> Void)?) {
        titleLabel.stringValue = state.title
        detailLabel.stringValue = state.detail
        progress.isHidden = !state.showsProgress
        cancelButton.isHidden = !state.showsProgress
        self.cancelAction = cancelAction
        progress.doubleValue = state.fraction
    }

    @objc private func cancel() {
        cancelAction?()
    }
}

final class FileCell: NSTableCellView {
    private let sizeLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let arrowLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.alignment = .right
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        sizeLabel.lineBreakMode = .byTruncatingMiddle

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 14)
        nameLabel.lineBreakMode = .byTruncatingMiddle

        arrowLabel.translatesAutoresizingMaskIntoConstraints = false
        arrowLabel.stringValue = "▶"
        arrowLabel.font = .systemFont(ofSize: 10)
        arrowLabel.alignment = .right

        addSubview(sizeLabel)
        addSubview(nameLabel)
        addSubview(arrowLabel)

        NSLayoutConstraint.activate([
            sizeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sizeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            sizeLabel.widthAnchor.constraint(equalToConstant: 96),
            nameLabel.leadingAnchor.constraint(equalTo: sizeLabel.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: arrowLabel.leadingAnchor, constant: -6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            arrowLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowLabel.widthAnchor.constraint(equalToConstant: 14)
        ])
    }

    func configure(with item: FileItem) {
        sizeLabel.stringValue = MainWindowController.formatSize(item.size)
        sizeLabel.textColor = Self.color(for: item.size)
        nameLabel.stringValue = item.name
        nameLabel.textColor = item.isReadable ? .labelColor : .tertiaryLabelColor
        arrowLabel.isHidden = !item.canBrowse
    }

    private static func color(for size: Int64) -> NSColor {
        let gb = Double(size) / 1_073_741_824
        switch gb {
        case 100...: return .systemRed
        case 10..<100: return .systemOrange
        case 1..<10: return .systemPurple
        case 0.001..<1: return .systemGreen
        default: return .secondaryLabelColor
        }
    }
}

enum LocationProvider {
    static func locations() -> [LocationItem] {
        var result: [LocationItem] = []
        let volumeKeys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]

        if let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: volumeKeys, options: [.skipHiddenVolumes]) {
            for volume in volumes {
                let values = try? volume.resourceValues(forKeys: Set(volumeKeys))
                let total = Int64(values?.volumeTotalCapacity ?? 0)
                let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
                let used = max(0, total - available)
                let title = values?.volumeName ?? volume.lastPathComponent
                let subtitle = "Capacity: \(MainWindowController.formatSize(total))   Used: \(MainWindowController.formatSize(used)), Available: \(MainWindowController.formatSize(available))"
                result.append(LocationItem(url: volume, title: title, subtitle: subtitle, icon: NSWorkspace.shared.icon(forFile: volume.path), isVolume: true))
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let places: [(String, URL)] = [
            ("Applications", URL(fileURLWithPath: "/Applications")),
            (NSUserName(), home),
            ("Desktop", home.appendingPathComponent("Desktop")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Music", home.appendingPathComponent("Music")),
            ("Movies", home.appendingPathComponent("Movies")),
            ("Pictures", home.appendingPathComponent("Pictures"))
        ]

        for (title, url) in places where FileManager.default.fileExists(atPath: url.path) {
            result.append(LocationItem(url: url, title: title, subtitle: url.path, icon: NSWorkspace.shared.icon(forFile: url.path), isVolume: false))
        }

        return result
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

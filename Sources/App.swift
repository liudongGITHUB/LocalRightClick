import Cocoa
import FinderSync
import ServiceManagement

@main struct LocalRightClickApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var status: NSTextField!
    private var loginToggle: NSButton!
    private var loginDescription: NSTextField!
    private let favorites = NSTableView()
    private var templateManager: TemplateManager?
    private var applicationManager: OpenApplicationManager?
    private var pageViews: [NSView] = []
    private var navigation: [NSButton] = []
    private var removeFavoriteButton: NSButton!
    private var openFavoriteButton: NSButton!
    private var settings = Settings.defaults
    private var busy = false
    private var processingRequest = false
    private var pendingRequests: [ActionRequest] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let loginLaunch = wasLaunchedAtLogin(NSAppleEventManager.shared().currentAppleEvent)
        setupMenu()
        var startupError: Error?
        do {
            settings = try SharedStore.load()
            try SharedStore.save(settings)
        } catch { startupError = error }
        buildWindow()
        refresh()
        if let startupError { showError(startupError) }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(requestReady), name: Notification.Name(SharedStore.notification), object: nil)
        if !drainRequests() && !loginLaunch { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !drainRequests() && !processingRequest && !busy { showSettings() }
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) { refreshStatus(); refreshLoginItem() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if busy { showMessage("文件操作进行中", "请等待操作完成后再退出。"); return .terminateCancel }
        return .terminateNow
    }
    private func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出轻右键", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        editItem.submenu = editMenu; main.addItem(editItem); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: "轻右键")
        let menu = NSMenu()
        let settingItem = menu.addItem(withTitle: "轻右键设置…", action: #selector(showSettings), keyEquivalent: "")
        settingItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出轻右键", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    private func label(_ text: String, size: CGFloat = 13, bold: Bool = false, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text)
        view.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        view.textColor = secondary ? .secondaryLabelColor : .labelColor
        return view
    }
    private func button(_ title: String, _ selector: Selector) -> NSButton {
        let view = NSButton(title: title, target: self, action: selector)
        view.bezelStyle = .rounded
        view.controlSize = .large
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal; stack.alignment = .centerY; stack.distribution = .fill; stack.spacing = 10
        return stack
    }
    private func column(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        return stack
    }
    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
    private func symbol(_ name: String, color: NSColor, size: CGFloat = 18) -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image.symbolConfiguration = .init(pointSize: size, weight: .medium)
        image.contentTintColor = color
        image.setAccessibilityElement(false)
        image.widthAnchor.constraint(equalToConstant: size + 4).isActive = true
        image.heightAnchor.constraint(equalToConstant: size + 4).isActive = true
        return image
    }
    private func iconTile(_ name: String, color: NSColor, size: CGFloat = 36) -> NSView {
        let box = NSBox()
        box.boxType = .custom; box.titlePosition = .noTitle; box.borderWidth = 0
        box.fillColor = color.withAlphaComponent(0.10); box.cornerRadius = size * 0.25
        box.contentViewMargins = .zero
        box.widthAnchor.constraint(equalToConstant: size).isActive = true
        box.heightAnchor.constraint(equalToConstant: size).isActive = true
        let image = symbol(name, color: color, size: size * 0.48)
        image.translatesAutoresizingMaskIntoConstraints = false
        box.contentView!.addSubview(image)
        NSLayoutConstraint.activate([image.centerXAnchor.constraint(equalTo: box.contentView!.centerXAnchor), image.centerYAnchor.constraint(equalTo: box.contentView!.centerYAnchor)])
        return box
    }
    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "轻右键"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 940, height: 580)
        window.backgroundColor = .windowBackgroundColor; window.isReleasedWhenClosed = false; window.center()
        let content = window.contentView!
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow; sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 200)
        ])
        let logo = NSImageView()
        logo.image = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
        logo.imageScaling = .scaleProportionallyDown
        logo.widthAnchor.constraint(equalToConstant: 44).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let brand = row([logo, column([label("轻右键", size: 20, bold: true), label("右键，更顺手", size: 11, secondary: true)])])
        let nav = column([brand], spacing: 7)
        nav.setCustomSpacing(28, after: brand)
        nav.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(nav)
        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 64),
            nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            nav.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14)
        ])
        for (index, item) in [("新建文件", "doc.badge.plus"), ("在此打开", "arrow.up.forward.app"), ("常用目录", "folder"), ("通用设置", "gearshape")].enumerated() {
            let control = NSButton(title: item.0, target: self, action: #selector(selectPage(_:)))
            control.image = NSImage(systemSymbolName: item.1, accessibilityDescription: nil)
            control.imagePosition = .imageLeading; control.alignment = .left
            control.font = .systemFont(ofSize: 14, weight: .medium)
            control.bezelStyle = .recessed; control.setButtonType(.pushOnPushOff)
            control.tag = index; control.setAccessibilityLabel(item.0)
            nav.addArrangedSubview(control)
            control.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true
            control.heightAnchor.constraint(equalToConstant: 38).isActive = true
            navigation.append(control)
        }
        status = label("", size: 12, bold: true)
        let sidebarFooter = column([status, label("设置自动保存", size: 11, secondary: true)], spacing: 7)
        sidebarFooter.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarFooter)
        NSLayoutConstraint.activate([
            sidebarFooter.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            sidebarFooter.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            sidebarFooter.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24)
        ])
        templateManager = TemplateManager(templates: settings.templates) { [unowned self] templates in
            var next = self.settings; next.templates = templates
            try self.persist(next)
        }
        applicationManager = OpenApplicationManager(applications: settings.applications) { [unowned self] applications in
            var next = self.settings; next.applications = applications
            try self.persist(next)
        }
        pageViews = [templateManager!.view, applicationManager!.view, buildFavoritesPage(), buildGeneralPage()]
        for page in pageViews {
            page.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
                page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                page.topAnchor.constraint(equalTo: content.topAnchor, constant: 38),
                page.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
        }
        showPage(0)
    }
    private func pageContent(_ title: String, subtitle: String) -> (NSView, NSStackView) {
        let page = NSView()
        let stack = column([label(title, size: 22, bold: true), label(subtitle, size: 13, secondary: true)], spacing: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 22)
        ])
        return (page, stack)
    }
    private func buildFavoritesPage() -> NSView {
        let (page, stack) = pageContent("常用目录", subtitle: "快速跳转，也可作为复制、移动文件的目的地。")
        favorites.delegate = self; favorites.dataSource = self
        favorites.rowHeight = 38; favorites.usesAlternatingRowBackgroundColors = true
        favorites.target = self; favorites.doubleAction = #selector(openFavorite)
        favorites.setAccessibilityLabel("常用目录列表")
        for (id, title, width) in [("icon", "", 36.0), ("name", "目录名称", 170.0), ("path", "位置", 470.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title; col.width = width; favorites.addTableColumn(col)
        }
        let scroll = NSScrollView()
        scroll.documentView = favorites; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        removeFavoriteButton = button("移除", #selector(removeFavorite))
        openFavoriteButton = button("在访达中打开", #selector(openFavorite))
        let controls = row([button("添加目录…", #selector(addFavorite)), openFavoriteButton, spacer(), removeFavoriteButton])
        stack.addArrangedSubview(controls)
        controls.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(label("双击列表打开目录；移除仅取消收藏，不删除文件。", size: 12, secondary: true))
        stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -20).isActive = true
        return page
    }
    private func buildGeneralPage() -> NSView {
        let (page, stack) = pageContent("通用设置", subtitle: "管理右键扩展与本机配置。")
        let extensionCard = row([
            iconTile("puzzlepiece.extension", color: .systemBlue),
            column([label("Finder 右键扩展", size: 15, bold: true), label("启用后，在访达右键菜单中使用轻右键。", size: 12, secondary: true)]),
            spacer(), button("管理扩展…", #selector(manageExtension))
        ])
        loginToggle = NSButton(checkboxWithTitle: "启用", target: self, action: #selector(toggleLoginItem(_:)))
        loginToggle.setAccessibilityLabel("登录时启动轻右键")
        loginDescription = label("", size: 12, secondary: true)
        let loginSettingsButton = button("系统登录项…", #selector(manageLoginItems))
        if #unavailable(macOS 13.0) { loginSettingsButton.isHidden = true }
        let loginRow = row([
            iconTile("power", color: .systemGreen),
            column([label("登录时启动", size: 15, bold: true), loginDescription]),
            spacer(), loginToggle, loginSettingsButton
        ])
        refreshLoginItem()
        let storageCard = row([
            iconTile("folder.badge.gearshape", color: .systemIndigo),
            column([label("配置与自定义模板", size: 15, bold: true), label("设置和导入模板保存在这台 Mac 上。", size: 12, secondary: true)]),
            spacer(), button("打开配置目录", #selector(openConfiguration))
        ])
        stack.setCustomSpacing(30, after: stack.arrangedSubviews.last!)
        for item in [extensionCard, loginRow, storageCard] {
            stack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let divider = NSBox(); divider.boxType = .separator
            stack.addArrangedSubview(divider)
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.setCustomSpacing(24, after: divider)
        }
        stack.addArrangedSubview(label("同名文件不覆盖 · 移动前确认", size: 12, secondary: true))
        stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -20).isActive = true
        return page
    }
    @objc private func selectPage(_ sender: NSButton) {
        guard window.makeFirstResponder(nil) else { return }
        showPage(sender.tag)
    }
    private func showPage(_ index: Int) {
        for (position, page) in pageViews.enumerated() {
            page.isHidden = position != index
            navigation[position].state = position == index ? .on : .off
            navigation[position].contentTintColor = position == index ? .controlAccentColor : .labelColor
        }
    }
    private func refresh() {
        let selected = favorites.selectedRow
        favorites.reloadData()
        if settings.favorites.indices.contains(selected) { favorites.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false) }
        removeFavoriteButton.isEnabled = settings.favorites.indices.contains(favorites.selectedRow)
        openFavoriteButton.isEnabled = removeFavoriteButton.isEnabled
        refreshStatus()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { settings.favorites.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let favorite = settings.favorites[row]
        let url = URL(fileURLWithPath: favorite.path)
        if tableColumn?.identifier.rawValue == "icon" {
            let image = NSImageView()
            image.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            image.contentTintColor = .systemBlue; image.imageScaling = .scaleProportionallyDown
            image.setAccessibilityElement(false)
            return image
        }
        let value = tableColumn?.identifier.rawValue == "name" ? (favorite.path == SharedStore.realHome.path ? "个人文件夹" : url.lastPathComponent) : favorite.path
        let field = NSTextField(labelWithString: value)
        field.lineBreakMode = .byTruncatingMiddle; field.toolTip = favorite.path
        return field
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        removeFavoriteButton?.isEnabled = settings.favorites.indices.contains(favorites.selectedRow)
        openFavoriteButton?.isEnabled = settings.favorites.indices.contains(favorites.selectedRow)
    }
    @objc private func openFavorite() {
        let index = favorites.selectedRow
        guard settings.favorites.indices.contains(index) else { return }
        do {
            let url = try favorite(settings.favorites[index].id)
            guard NSWorkspace.shared.open(url) else { throw UserError("无法打开目录。") }
        } catch { showError(error) }
    }
    private func refreshStatus() {
        guard let status else { return }
        if busy {
            status.stringValue = "正在处理文件…"
            status.textColor = .systemOrange
        } else {
            let enabled = FIFinderSyncController.isExtensionEnabled
            status.stringValue = enabled ? "●  右键扩展已启用" : "○  请启用右键扩展"
            status.textColor = enabled ? .systemGreen : .secondaryLabelColor
        }
    }
    private func refreshLoginItem() {
        guard let loginToggle, let loginDescription else { return }
        do {
            if try LegacyLoginItem.current.isEnabled() {
                loginToggle.state = .on
                loginDescription.stringValue = "已启用兼容登录项 · 下次登录时在菜单栏运行。"
                return
            }
        } catch {
            loginToggle.state = .off; loginDescription.stringValue = error.localizedDescription
            return
        }
        guard #available(macOS 13.0, *) else {
            loginToggle.state = .off
            loginDescription.stringValue = "未启用 · 勾选后下次登录自动启动，不弹出设置窗口。"
            return
        }
        let status = SMAppService.mainApp.status
        loginToggle.state = status == .enabled ? .on : .off
        switch status {
        case .enabled: loginDescription.stringValue = "已启用 · 登录后在菜单栏运行，不弹出设置窗口。"
        case .notRegistered: loginDescription.stringValue = "未启用 · 右键操作仍可按需启动轻右键。"
        case .requiresApproval: loginDescription.stringValue = "等待系统允许 · 请在“系统登录项”中开启。"
        case .notFound: loginDescription.stringValue = "尚未登记登录项 · 勾选“启用”自动配置。"
        @unknown default: loginDescription.stringValue = "请在“系统登录项”中检查启动状态。"
        }
    }
    @objc private func toggleLoginItem(_ sender: NSButton) {
        do {
            if #available(macOS 13.0, *) {
                if sender.state == .on {
                    if SMAppService.mainApp.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    } else if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) { try SMAppService.mainApp.unregister() }
                    try LegacyLoginItem.current.setEnabled(false)
                }
            } else {
                try LegacyLoginItem.current.setEnabled(sender.state == .on)
            }
        } catch { showError(error) }
        refreshLoginItem()
    }
    @objc private func manageLoginItems() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
    }
    @objc private func showSettings() { refreshStatus(); refreshLoginItem(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func manageExtension() { FIFinderSyncController.showExtensionManagementInterface() }
    @objc private func openConfiguration() { NSWorkspace.shared.open(SharedStore.base) }
    private func showMessage(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.runModal()
    }
    private func showError(_ error: Error) { showMessage("操作未完成", error.localizedDescription) }
    private func selectDirectory(_ title: String) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); panel.title = title; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
    private func persist(_ next: Settings) throws { try SharedStore.save(next); settings = next; refresh() }
    private func storeFavorite(_ url: URL) throws {
        try FileActions.requireDirectory(url)
        let path = url.standardizedFileURL.path
        if settings.favorites.contains(where: { $0.path == path }) { return }
        var next = settings; next.favorites.append(Favorite(id: UUID().uuidString, path: path)); try persist(next)
    }
    @objc private func addFavorite() {
        guard let url = selectDirectory("添加常用目录") else { return }
        do { try storeFavorite(url) } catch { showError(error) }
    }
    @objc private func removeFavorite() {
        guard settings.favorites.indices.contains(favorites.selectedRow) else { return }
        let id = settings.favorites[favorites.selectedRow].id
        do { var next = settings; next.favorites.removeAll { $0.id == id }; try persist(next) } catch { showError(error) }
    }
    @objc private func requestReady() { DispatchQueue.main.async { _ = self.drainRequests() } }
    @discardableResult private func drainRequests() -> Bool {
        do {
            pendingRequests += try SharedStore.takeRequests()
            guard !busy, !processingRequest else { return true }
            guard !pendingRequests.isEmpty else { return false }
            processingRequest = true
            while !busy, !pendingRequests.isEmpty {
                let request = pendingRequests.removeFirst()
                do { settings = try SharedStore.load(); try perform(request) } catch { showError(error) }
            }
            processingRequest = false
            return true
        } catch { processingRequest = false; showError(error); return true }
    }
    private func directory(for path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true ? url : url.deletingLastPathComponent()
    }
    private func favorite(_ id: String) throws -> URL {
        guard let favorite = settings.favorites.first(where: { $0.id == id }), favorite.path.hasPrefix("/"), !favorite.path.utf8.contains(0) else { throw UserError("常用目录已被移除，请重新打开菜单。") }
        let url = URL(fileURLWithPath: favorite.path); try FileActions.requireDirectory(url); return url
    }
    private func perform(_ request: ActionRequest) throws {
        // Freshness was checked when received; a long copy or dialog must not expire accepted work.
        try request.validate(checkFreshness: false)
        switch request.action {
        case .settings:
            if request.option == "applications" { showPage(1) }
            showSettings()
        case .copyPath:
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(request.paths.joined(separator: "\n"), forType: .string)
        case .favorite:
            guard let id = request.option else { throw UserError("缺少常用目录。") }
            guard NSWorkspace.shared.open(try favorite(id)) else { throw UserError("无法打开目录。") }
        case .addFavorite:
            let url = try directory(for: request.directory!)
            try storeFavorite(url); showMessage("已加入常用目录", url.path)
        case .create:
            guard let template = settings.enabledTemplates.first(where: { $0.id == request.option }) else { throw UserError("模板已停用或移除，请重新打开菜单。") }
            let dir = try directory(for: request.directory!)
            let panel = NSAlert(); panel.messageText = "新建文件"; panel.informativeText = "位置：\(dir.path)"
            panel.addButton(withTitle: "创建"); panel.addButton(withTitle: "取消")
            let input = NSTextField(string: template.filename); input.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
            panel.accessoryView = input; panel.window.initialFirstResponder = input
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .alertFirstButtonReturn else { return }
            let created = try template.create(in: dir, name: input.stringValue, base: SharedStore.base)
            NSWorkspace.shared.activateFileViewerSelecting([created])
        case .openApplication, .openTerminal, .openITerm, .openVSCode, .openCursor:
            let application = try settings.application(for: request)
            guard let app = application.installedURL else { throw UserError("未找到“\(application.name)”，请先安装，或在“在此打开”设置中重新添加。") }
            let urls: [URL]
            if application.opensDirectory {
                urls = try Array(Set(request.paths.map { try directory(for: $0) }))
            } else { urls = request.paths.map { URL(fileURLWithPath: $0) } }
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { DispatchQueue.main.async { self.showError(error) } }
            }
        case .copy, .move:
            let target: URL
            if let id = request.option { target = try favorite(id) }
            else { guard let selected = selectDirectory(request.action == .move ? "移动到文件夹" : "复制到文件夹") else { return }; target = selected }
            let sources = request.paths.map { URL(fileURLWithPath: $0) }
            _ = try FileActions.plannedTransfer(sources, to: target)
            if request.action == .move {
                let alert = NSAlert(); alert.messageText = "移动 \(sources.count) 个项目？"
                alert.informativeText = "目标：\(target.path)\n\n" + sources.prefix(6).map(\.lastPathComponent).joined(separator: "\n") + (sources.count > 6 ? "\n…" : "")
                alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "移动")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertSecondButtonReturn else { return }
            }
            busy = true; refreshStatus(); window.makeKeyAndOrderFront(nil)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try FileActions.transfer(sources, to: target, move: request.action == .move) }
                DispatchQueue.main.async {
                    self.busy = false; self.refreshStatus()
                    switch result {
                    case .success(let report):
                        if report.failures.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(report.completed) }
                        else { self.showMessage("部分操作未完成", "已完成 \(report.completed.count) 项，失败 \(report.failures.count) 项。失败项的原文件请保留；目标可能留有未完成的副本。\n\n" + report.failures.joined(separator: "\n")) }
                    case .failure(let error): self.showError(error)
                    }
                    _ = self.drainRequests()
                }
            }
        }
    }
}

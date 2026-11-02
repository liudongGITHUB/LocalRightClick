import Cocoa
import UniformTypeIdentifiers

extension OpenApplication {
    var installedURL: URL? {
        if let path {
            let url = URL(fileURLWithPath: path)
            if Bundle(url: url)?.bundleIdentifier == bundleIdentifier,
               let executable = Bundle(url: url)?.executableURL,
               FileManager.default.isExecutableFile(atPath: executable.path) { return url }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
    static func from(_ url: URL) throws -> OpenApplication {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let id = bundle.bundleIdentifier, let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw UserError("请选择有效的本机应用（.app）。") }
        let name = FileManager.default.displayName(atPath: url.path)
        let application = OpenApplication(id: UUID().uuidString, name: name.lowercased().hasSuffix(".app") ? (name as NSString).deletingPathExtension : name,
                                          bundleIdentifier: id, path: url.standardizedFileURL.path)
        try application.validate()
        return application
    }
}

final class OpenApplicationManager: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var applications: [OpenApplication]
    private let onChange: ([OpenApplication]) throws -> Void
    private let table = NSTableView()
    private let summary = NSTextField(labelWithString: "")
    private var upButton: NSButton!
    private var downButton: NSButton!
    private var removeButton: NSButton!

    init(applications: [OpenApplication], onChange: @escaping ([OpenApplication]) throws -> Void) {
        self.applications = applications; self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
        view = NSView()
        buildUI()
        refresh(selection: 0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        let title = NSTextField(labelWithString: "在此打开")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(title)
        summary.textColor = .secondaryLabelColor
        root.addArrangedSubview(summary)
        table.delegate = self; table.dataSource = self; table.rowHeight = 34
        table.usesAlternatingRowBackgroundColors = true
        table.setAccessibilityLabel("在此打开应用列表")
        for (id, title, width) in [("enabled", "启用", 44.0), ("icon", "", 32.0), ("name", "应用", 150.0), ("target", "打开对象", 110.0), ("path", "应用位置", 330.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        upButton = button("上移", #selector(moveApplicationUp))
        downButton = button("下移", #selector(moveApplicationDown))
        removeButton = button("移除", #selector(removeApplication))
        let gap = NSView(); gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [button("添加应用…", #selector(addApplication)), gap, upButton, downButton, removeButton])
        controls.spacing = 8
        root.addArrangedSubview(controls)
        controls.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let note = NSTextField(wrappingLabelWithString: "勾选后显示在右键菜单，上下移动可调整顺序。终端和 iTerm 打开所在目录；其他应用接收选中的文件或文件夹。移除不会卸载应用。")
        note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    func numberOfRows(in tableView: NSTableView) -> Int { applications.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let application = applications[row]
        switch tableColumn?.identifier.rawValue {
        case "enabled":
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleApplication(_:)))
            check.state = application.enabled ? .on : .off; check.tag = row
            check.setAccessibilityLabel("显示 " + application.name)
            return check
        case "icon":
            let image = NSImageView()
            image.image = application.installedURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            image.imageScaling = .scaleProportionallyDown; image.setAccessibilityElement(false)
            return image
        case "name": return NSTextField(labelWithString: application.name)
        case "target": return NSTextField(labelWithString: application.opensDirectory ? "所在目录" : "文件或文件夹")
        default:
            let path = application.installedURL?.path
            let field = NSTextField(labelWithString: path ?? "未找到应用，请安装或重新添加")
            field.textColor = path == nil ? .systemOrange : .secondaryLabelColor
            field.lineBreakMode = .byTruncatingMiddle; field.toolTip = path ?? application.path
            return field
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    private func updateButtons() {
        let index = table.selectedRow
        let selected = applications.indices.contains(index)
        upButton.isEnabled = selected && index > 0
        downButton.isEnabled = selected && index < applications.count - 1
        removeButton.isEnabled = selected
    }
    private func refresh(selection: Int) {
        table.reloadData()
        summary.stringValue = "已启用 \(applications.filter(\.enabled).count) / \(applications.count) 个应用 · 修改自动保存"
        if applications.indices.contains(selection) {
            table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
            table.scrollRowToVisible(selection)
        }
        updateButtons()
    }
    private func commit(_ next: [OpenApplication], selection: Int) throws {
        try onChange(next)
        applications = next
        refresh(selection: selection)
    }
    private func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "未能保存应用"; alert.informativeText = error.localizedDescription; alert.runModal()
    }
    @objc private func toggleApplication(_ sender: NSButton) {
        let index = sender.tag
        guard applications.indices.contains(index) else { return }
        var next = applications; next[index].enabled = sender.state == .on
        do { try commit(next, selection: index) }
        catch { refresh(selection: index); showError(error) }
    }
    @objc private func moveApplicationUp() { move(by: -1) }
    @objc private func moveApplicationDown() { move(by: 1) }
    private func move(by offset: Int) {
        let index = table.selectedRow, target = table.selectedRow + offset
        guard applications.indices.contains(index), applications.indices.contains(target) else { return }
        var next = applications; next.swapAt(index, target)
        do { try commit(next, selection: target) } catch { showError(error) }
    }
    @objc private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "添加到“在此打开”"; panel.message = "选择用于打开文件或文件夹的本机应用。"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let application = try OpenApplication.from(url)
            // Re-selecting an app repairs its location without losing its order or enabled state.
            if let index = applications.firstIndex(where: { $0.bundleIdentifier == application.bundleIdentifier }) {
                var next = applications; next[index].path = application.path
                try commit(next, selection: index)
            } else { try commit(applications + [application], selection: applications.count) }
        } catch { showError(error) }
    }
    @objc private func removeApplication() {
        let index = table.selectedRow
        guard applications.indices.contains(index) else { return }
        var next = applications; next.remove(at: index)
        do { try commit(next, selection: min(index, next.count - 1)) } catch { showError(error) }
    }
}

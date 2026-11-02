import Cocoa
import UniformTypeIdentifiers

final class TemplateManager: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var templates: [FileTemplate]
    private let onChange: ([FileTemplate]) throws -> Void
    private let table = NSTableView()
    private let summary = NSTextField(labelWithString: "")
    private var editButton: NSButton!
    private var removeButton: NSButton!
    private var upButton: NSButton!
    private var downButton: NSButton!

    init(templates: [FileTemplate], onChange: @escaping ([FileTemplate]) throws -> Void) {
        self.templates = templates
        self.onChange = onChange
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
        let title = NSTextField(labelWithString: "新建文件")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(title)
        summary.textColor = .secondaryLabelColor
        root.addArrangedSubview(summary)

        table.delegate = self; table.dataSource = self; table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.setAccessibilityLabel("新建文件模板列表")
        for (id, title, width) in [("enabled", "启用", 40.0), ("mainMenu", "主菜单", 60.0), ("icon", "", 28.0), ("name", "名称 · 双击编辑", 164.0), ("extension", "后缀", 50.0), ("filename", "默认文件名 · 双击编辑", 210.0), ("source", "来源", 50.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        upButton = button("上移", #selector(moveTemplateUp))
        downButton = button("下移", #selector(moveTemplateDown))
        editButton = button("编辑…", #selector(editTemplate))
        removeButton = button("移除", #selector(removeTemplate))
        let gap = NSView()
        gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [button("新建文本…", #selector(newTextTemplate)), button("导入模板…", #selector(importTemplate)), gap, upButton, downButton, editButton, removeButton])
        controls.spacing = 8
        root.addArrangedSubview(controls)
        controls.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let note = NSTextField(wrappingLabelWithString: "“启用”控制是否显示；勾选“主菜单”可直接显示在右键第一层，其余位于“轻右键 → 新建文件”。名称和文件名可双击编辑。")
        note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { templates.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let template = templates[row]
        switch tableColumn?.identifier.rawValue {
        case "enabled", "mainMenu":
            let mainMenu = tableColumn?.identifier.rawValue == "mainMenu"
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleTemplate(_:)))
            check.state = (mainMenu ? template.showsInMainMenu : template.isEnabled) ? .on : .off
            check.tag = row; check.identifier = tableColumn?.identifier
            check.setAccessibilityLabel((mainMenu ? "主菜单显示 " : "显示 ") + template.name)
            if mainMenu { check.toolTip = "启用后直接显示在 Finder 右键第一层" }
            return check
        case "icon":
            let image = NSImageView()
            image.image = NSWorkspace.shared.icon(for: UTType(filenameExtension: (template.filename as NSString).pathExtension) ?? .data)
            image.imageScaling = .scaleProportionallyDown
            image.setAccessibilityElement(false)
            return image
        case "name", "filename":
            let field = NSTextField(string: tableColumn?.identifier.rawValue == "name" ? template.name : template.filename)
            field.isBezeled = false; field.drawsBackground = false
            field.font = .systemFont(ofSize: 13)
            field.delegate = self; field.tag = row; field.identifier = tableColumn?.identifier
            field.lineBreakMode = .byTruncatingMiddle
            field.setAccessibilityLabel((tableColumn?.identifier.rawValue == "name" ? "菜单名称 " : "默认文件名 ") + template.name)
            return field
        case "extension": return NSTextField(labelWithString: (template.filename as NSString).pathExtension)
        default:
            let label = NSTextField(labelWithString: template.isBuiltIn ? "内置" : "自定义")
            label.textColor = .secondaryLabelColor
            return label
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, templates.indices.contains(field.tag) else { return }
        let index = field.tag
        var next = templates
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if field.identifier?.rawValue == "name" {
            guard value != next[index].name else { return }
            next[index].name = value
        } else {
            guard value != next[index].filename else { return }
            next[index].filename = value
        }
        do { try commit(next, selection: index) }
        catch { refresh(selection: index); showError(error) }
    }
    private func updateButtons() {
        let index = table.selectedRow
        let selected = templates.indices.contains(index)
        editButton.isEnabled = selected
        removeButton.isEnabled = selected && !templates[index].isBuiltIn
        upButton.isEnabled = selected && index > 0
        downButton.isEnabled = selected && index < templates.count - 1
    }
    private func refresh(selection: Int) {
        table.reloadData()
        summary.stringValue = "已启用 \(templates.filter(\.isEnabled).count) / \(templates.count) 种文件类型 · 修改自动保存"
        if templates.indices.contains(selection) {
            table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
            table.scrollRowToVisible(selection)
        }
        updateButtons()
    }
    private func commit(_ next: [FileTemplate], selection: Int) throws {
        for template in next { try template.validate() }
        try onChange(next)
        templates = next
        refresh(selection: selection)
    }
    private func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "未能保存模板"; alert.informativeText = error.localizedDescription; alert.runModal()
    }
    @objc private func toggleTemplate(_ sender: NSButton) {
        let index = sender.tag
        guard templates.indices.contains(index) else { return }
        var next = templates
        if sender.identifier?.rawValue == "mainMenu" { next[index].inMainMenu = sender.state == .on }
        else { next[index].enabled = sender.state == .on }
        do { try commit(next, selection: index) }
        catch { refresh(selection: index); showError(error) }
    }
    @objc private func moveTemplateUp() { move(by: -1) }
    @objc private func moveTemplateDown() { move(by: 1) }
    private func move(by offset: Int) {
        let index = table.selectedRow, target = table.selectedRow + offset
        guard templates.indices.contains(index), templates.indices.contains(target) else { return }
        var next = templates; next.swapAt(index, target)
        do { try commit(next, selection: target) } catch { showError(error) }
    }
    private func edit(_ template: FileTemplate, withContent: Bool) -> (FileTemplate, String)? {
        let alert = NSAlert()
        alert.messageText = withContent ? "新建文本模板" : "编辑模板"
        alert.informativeText = withContent ? "例如：会议记录、.env、配置文件或代码。只创建文件，不执行内容。" : "修改右键菜单中的名称和创建文件时的默认文件名。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        let height: CGFloat = withContent ? 290 : 110
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: height))
        let name = NSTextField(string: template.name)
        let filename = NSTextField(string: template.filename)
        for (title, field, y) in [("菜单名称", name, height - 46), ("默认文件名（含后缀）", filename, height - 100)] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 0, y: y + 28, width: 440, height: 18)
            field.frame = NSRect(x: 0, y: y, width: 440, height: 24)
            field.setAccessibilityLabel(title)
            view.addSubview(label); view.addSubview(field)
        }
        let content = NSTextView()
        if withContent {
            let label = NSTextField(labelWithString: "初始内容（可留空）")
            label.frame = NSRect(x: 0, y: 158, width: 440, height: 18); view.addSubview(label)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 152))
            scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            content.frame = scroll.bounds; content.isRichText = false
            content.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            content.isVerticallyResizable = true; content.autoresizingMask = [.width]
            content.setAccessibilityLabel("模板初始内容")
            scroll.documentView = content; view.addSubview(scroll)
        }
        alert.accessoryView = view; alert.window.initialFirstResponder = name
        while alert.runModal() == .alertFirstButtonReturn {
            var result = template
            result.name = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            result.filename = filename.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            do { try result.validate(); return (result, content.string) } catch { showError(error) }
        }
        return nil
    }
    @objc private func editTemplate() {
        let index = table.selectedRow
        guard templates.indices.contains(index), let (template, _) = edit(templates[index], withContent: false) else { return }
        var next = templates; next[index] = template
        do { try commit(next, selection: index) } catch { showError(error) }
    }
    @objc private func newTextTemplate() {
        let id = UUID().uuidString
        guard let (template, content) = edit(FileTemplate(id: id, name: "自定义文本", filename: "新建文件.txt", storedFile: id + ".template"), withContent: true) else { return }
        do {
            try SharedStore.prepare()
            let target = SharedStore.base.appendingPathComponent("Templates").appendingPathComponent(template.storedFile!)
            try Data(content.utf8).write(to: target, options: .withoutOverwriting)
            do { try commit(templates + [template], selection: templates.count) }
            catch { try? FileManager.default.removeItem(at: target); throw error }
        } catch { showError(error) }
    }
    @objc private func importTemplate() {
        let panel = NSOpenPanel()
        panel.title = "导入模板文件"; panel.message = "选择 20 MB 以内的真实文件；支持办公文档、设计文件及 iWork 文稿包。"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let template = try FileTemplate.importFile(url, into: SharedStore.base)
            do { try commit(templates + [template], selection: templates.count) }
            catch {
                if let stored = template.storedFile { try? FileManager.default.removeItem(at: SharedStore.base.appendingPathComponent("Templates").appendingPathComponent(stored)) }
                throw error
            }
        } catch { showError(error) }
    }
    @objc private func removeTemplate() {
        let index = table.selectedRow
        guard templates.indices.contains(index), !templates[index].isBuiltIn else { return }
        let template = templates[index]
        let alert = NSAlert(); alert.messageText = "移除“\(template.name)”？"
        alert.informativeText = "只从模板列表移除，原文件及已创建的文件不受影响。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "移除")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            try template.validate()
            var next = templates; next.remove(at: index)
            try commit(next, selection: min(index, next.count - 1))
            if let stored = template.storedFile { try FileManager.default.removeItem(at: SharedStore.base.appendingPathComponent("Templates").appendingPathComponent(stored)) }
        } catch { showError(error) }
    }
}

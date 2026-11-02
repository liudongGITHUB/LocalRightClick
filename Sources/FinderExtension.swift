import Cocoa
import FinderSync
import OSLog
import UniformTypeIdentifiers

@objc(LocalRightClickFinder) final class FinderExtension: FIFinderSync {
    private let logger = Logger(subsystem: "local.liudong.LocalRightClick", category: "Finder")
    private var requests: [Int: ActionRequest] = [:]
    private var nextTag = 1

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [SharedStore.realHome, URL(fileURLWithPath: "/Volumes"), URL(fileURLWithPath: "/private/tmp")]
        do {
            try SharedStore.prepare()
            try Data("\(Date()) pid=\(ProcessInfo.processInfo.processIdentifier)".utf8)
                .write(to: SharedStore.base.appendingPathComponent("extension-status.txt"), options: .atomic)
        } catch { logger.error("Extension storage unavailable: \(error.localizedDescription, privacy: .public)") }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        requests.removeAll()
        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL()
        let selection = menuKind == .contextualMenuForContainer ? [] : (controller.selectedItemURLs() ?? [])
        let paths = selection.isEmpty ? [target?.path].compactMap { $0 } : selection.map(\.path)
        let actionDirectory = selection.count == 1 ? selection[0].path : target?.path
        let menu = NSMenu(title: "轻右键")
        menu.autoenablesItems = false
        let settings: Settings
        do { settings = try SharedStore.load() }
        catch {
            logger.error("Cannot load settings: \(error.localizedDescription, privacy: .public)")
            add("设置读取失败，打开设置…", .settings, to: menu)
            return menu
        }
        let wrapper = NSMenu()
        wrapper.autoenablesItems = false
        if target != nil {
            let newMenu = submenu("新建文件", in: menu)
            for template in settings.enabledTemplates {
                let title = (template.showsInMainMenu ? "新建 " : "") + template.name
                let item = add(title, .create, directory: actionDirectory, option: template.id, to: template.showsInMainMenu ? wrapper : newMenu)
                let type = UTType(filenameExtension: (template.filename as NSString).pathExtension) ?? .data
                let icon = NSWorkspace.shared.icon(for: type).copy() as? NSImage
                icon?.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            if settings.enabledTemplates.isEmpty { add("选择要显示的文件类型…", .settings, to: newMenu) }
            if newMenu.items.isEmpty { menu.removeItem(at: 0) }
            add("拷贝路径", .copyPath, paths: paths, to: menu)
            let openMenu = submenu("在此打开", in: menu)
            for application in settings.enabledApplications {
                add(application.name, .openApplication, paths: paths, option: application.id, to: openMenu)
            }
            if settings.enabledApplications.isEmpty { add("添加或启用应用…", .settings, option: "applications", to: openMenu) }
            if menuKind != .contextualMenuForContainer && !paths.isEmpty {
                for (title, action) in [("复制到", Action.copy), ("移动到", .move)] {
                    let transferMenu = submenu(title, in: menu)
                    add("选择文件夹…", action, paths: paths, to: transferMenu)
                    for favorite in settings.favorites {
                        add(favoriteTitle(favorite), action, paths: paths, option: favorite.id, to: transferMenu)
                    }
                }
            }
        }
        let favorites = submenu("常用目录", in: menu)
        for favorite in settings.favorites { add(favoriteTitle(favorite), .favorite, option: favorite.id, to: favorites) }
        if target != nil {
            favorites.addItem(.separator())
            add("将此目录加入常用…", .addFavorite, directory: actionDirectory, to: favorites)
        }
        menu.addItem(.separator())
        add("轻右键设置…", .settings, to: menu)
        let root = NSMenuItem(title: "轻右键", action: nil, keyEquivalent: "")
        root.submenu = menu
        wrapper.addItem(root)
        return wrapper
    }

    private func favoriteTitle(_ favorite: Favorite) -> String {
        let url = URL(fileURLWithPath: favorite.path)
        return favorite.path == SharedStore.realHome.path ? "个人文件夹" : url.lastPathComponent
    }
    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
        return menu
    }
    @discardableResult private func add(_ title: String, _ action: Action, paths: [String] = [], directory: String? = nil, option: String? = nil, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        // Finder serializes tag, but does not preserve representedObject in action callbacks.
        item.tag = nextTag; nextTag += 1
        requests[item.tag] = ActionRequest(action: action, paths: paths, directory: directory, option: option)
        item.toolTip = option.flatMap { id in (try? SharedStore.load())?.favorites.first { $0.id == id }?.path }
        menu.addItem(item)
        return item
    }
    @objc private func performAction(_ sender: NSMenuItem) {
        do {
            guard var request = requests[sender.tag] else { throw UserError("菜单已更新，请重新右键操作。") }
            request.id = UUID(); request.createdAt = Date()
            if request.action == .copyPath {
                try request.validate()
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(request.paths.joined(separator: "\n"), forType: .string) else {
                    throw UserError("无法写入剪贴板。")
                }
                return
            }
            try SharedStore.submit(request)
            let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard wakeHostApplication(at: host) else { throw UserError("无法打开轻右键主应用，请从应用程序中打开后重试。") }
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(SharedStore.notification), object: nil, userInfo: nil, deliverImmediately: true)
        } catch {
            logger.error("Action failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(); alert.messageText = "轻右键"; alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

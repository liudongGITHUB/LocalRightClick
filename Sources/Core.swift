import Foundation
import Darwin

struct UserError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Action: String, Codable {
    case create, copyPath, openApplication, openTerminal, openITerm, openVSCode, openCursor
    case copy, move, favorite, addFavorite, settings
}

struct ActionRequest: Codable {
    var id = UUID()
    var createdAt = Date()
    var action: Action
    var paths: [String] = []
    var directory: String?
    var option: String?

    func validate(checkFreshness: Bool = true) throws {
        let age = Date().timeIntervalSince(createdAt)
        guard (!checkFreshness || (age >= -5 && age < 60)), paths.count <= 10000 else { throw UserError("操作请求已过期，请重新右键操作。") }
        for path in paths + [directory].compactMap({ $0 }) {
            guard path.hasPrefix("/"), !path.utf8.contains(0), path.utf8.count <= 32768 else {
                throw UserError("无效的文件路径。")
            }
        }
        if let option, option.utf8.count > 4096 { throw UserError("无效的菜单参数。") }
        if [.copy, .move, .copyPath, .openApplication, .openTerminal, .openITerm, .openVSCode, .openCursor].contains(action), paths.isEmpty {
            throw UserError("没有选中的文件或目录。")
        }
        if action == .openApplication, option?.isEmpty != false { throw UserError("缺少应用，请重新打开菜单。") }
        if [.create, .addFavorite].contains(action), directory == nil { throw UserError("没有目标目录。") }
    }
}

struct FileTemplate: Codable {
    var id: String
    var name: String
    var filename: String
    var storedFile: String?
    var enabled: Bool?
    var inMainMenu: Bool?

    var showsInMainMenu: Bool { inMainMenu ?? false }
    var isEnabled: Bool { enabled ?? true }
    var isBuiltIn: Bool { storedFile == nil && BuiltInTemplates.all.contains { $0.id == id } }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 100, name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw UserError("显示名称不能为空，不能包含换行，最多 100 个字符。")
        }
        try FileActions.validateName(filename)
        if let storedFile { try FileActions.validateName(storedFile) }
        if ["docx", "xlsx", "pptx"].contains(id), storedFile == nil,
           (filename as NSString).pathExtension.lowercased() != id {
            throw UserError("这个内置模板的文件名必须保留 .\(id) 后缀。")
        }
    }

    func contents(in base: URL, resources: URL? = Bundle.main.resourceURL) throws -> Data {
        if let storedFile {
            try FileActions.validateName(storedFile)
            return try Data(contentsOf: base.appendingPathComponent("Templates").appendingPathComponent(storedFile))
        }
        if let text = BuiltInTemplates.text[id] { return Data(text.utf8) }
        if ["docx", "xlsx", "pptx"].contains(id), let resources {
            return try Data(contentsOf: resources.appendingPathComponent("BuiltInTemplates/blank.\(id)"))
        }
        throw UserError("找不到这个文件模板，请重新添加。")
    }

    func createDefault(in directory: URL, base: URL, resources: URL? = Bundle.main.resourceURL) throws -> URL {
        try validate()
        try FileActions.requireDirectory(directory)
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var number = 1
        while true {
            let name = number == 1 ? filename : "\(stem) \(number)" + (ext.isEmpty ? "" : ".\(ext)")
            if !FileActions.exists(directory.appendingPathComponent(name)) {
                do { return try create(in: directory, name: name, base: base, resources: resources) }
                // Another process may create this name after the existence check.
                catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {}
            }
            number += 1
        }
    }

    func create(in directory: URL, name: String, base: URL, resources: URL? = Bundle.main.resourceURL) throws -> URL {
        try validate()
        if let storedFile {
            let source = base.appendingPathComponent("Templates").appendingPathComponent(storedFile)
            if try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                try FileActions.validateName(name)
                try FileActions.requireDirectory(directory)
                let target = directory.appendingPathComponent(name)
                guard !FileActions.exists(target) else { throw UserError("已有同名项目，未覆盖。") }
                try FileManager.default.copyItem(at: source, to: target)
                return target
            }
        }
        return try FileActions.createFile(in: directory, name: name, contents: contents(in: base, resources: resources))
    }

    static func importFile(_ url: URL, into base: URL) throws -> FileTemplate {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isSymbolicLink != true else { throw UserError("请选择实际模板文件，不要选择符号链接。") }
        var total = 0
        var enumerationError: Error?
        if values.isDirectory == true {
            guard ["pages", "numbers", "key"].contains(url.pathExtension.lowercased()),
                  let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in enumerationError = error; return false }) else {
                throw UserError("请选择模板文件，或 Pages、Numbers、Keynote 文稿包。")
            }
            var count = 0
            for case let file as URL in files {
                let item = try file.resourceValues(forKeys: keys)
                count += 1
                guard item.isSymbolicLink != true, item.isDirectory == true || item.isRegularFile == true, count <= 10000 else { throw UserError("模板包包含不支持的文件或项目过多。") }
                total += item.isRegularFile == true ? (item.fileSize ?? 20_000_001) : 0
                guard total <= 20_000_000 else { throw UserError("请选择 20 MB 以内的模板。") }
            }
            if let enumerationError { throw enumerationError }
        } else {
            guard values.isRegularFile == true else { throw UserError("请选择普通文件作为模板。") }
            total = values.fileSize ?? 20_000_001
        }
        guard total <= 20_000_000 else { throw UserError("请选择 20 MB 以内的模板。") }
        let id = UUID().uuidString
        let stored = id + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
        let template = FileTemplate(id: id, name: url.lastPathComponent, filename: url.lastPathComponent, storedFile: stored)
        try template.validate()
        let folder = base.appendingPathComponent("Templates")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(stored))
        return template
    }
}

enum BuiltInTemplates {
    static let text: [String: String] = [
        "txt": "", "md": "", "json": "{}\n", "rtf": "{\\rtf1\\ansi\\deff0 {\\fonttbl {\\f0 Helvetica;}}\\f0\\fs24 \\par}\n",
        "csv": "", "tsv": "", "xml": "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>\n",
        "html": "<!doctype html>\n<html lang=\"zh-CN\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>新建页面</title>\n</head>\n<body>\n</body>\n</html>\n",
        "css": "", "js": "", "ts": "", "py": "# -*- coding: utf-8 -*-\n", "sh": "#!/bin/sh\n",
        "yaml": "# YAML\n", "toml": "# TOML\n", "ini": "", "sql": "-- SQL\n", "swift": "import Foundation\n",
        "java": "", "svg": "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" height=\"600\" viewBox=\"0 0 800 600\"></svg>\n"
    ]
    static let all: [FileTemplate] = [
        FileTemplate(id: "txt", name: "文本文档 TXT", filename: "新建文本文档.txt"),
        FileTemplate(id: "md", name: "Markdown", filename: "新建文档.md"),
        FileTemplate(id: "json", name: "JSON", filename: "新建文件.json"),
        FileTemplate(id: "docx", name: "Word 文档", filename: "新建文档.docx"),
        FileTemplate(id: "xlsx", name: "Excel 工作簿", filename: "新建工作簿.xlsx"),
        FileTemplate(id: "pptx", name: "PowerPoint 演示文稿", filename: "新建演示文稿.pptx"),
        FileTemplate(id: "rtf", name: "富文本文档 RTF", filename: "新建文档.rtf"),
        FileTemplate(id: "csv", name: "CSV 表格", filename: "新建表格.csv"),
        FileTemplate(id: "xml", name: "XML", filename: "新建文件.xml"),
        FileTemplate(id: "html", name: "HTML 网页", filename: "新建网页.html"),
        FileTemplate(id: "yaml", name: "YAML 配置", filename: "新建配置.yaml", enabled: false),
        FileTemplate(id: "py", name: "Python", filename: "新建脚本.py", enabled: false),
        FileTemplate(id: "sh", name: "Shell 脚本", filename: "新建脚本.sh", enabled: false),
        FileTemplate(id: "js", name: "JavaScript", filename: "新建脚本.js", enabled: false),
        FileTemplate(id: "ts", name: "TypeScript", filename: "新建脚本.ts", enabled: false),
        FileTemplate(id: "css", name: "CSS 样式", filename: "新建样式.css", enabled: false),
        FileTemplate(id: "sql", name: "SQL", filename: "新建查询.sql", enabled: false),
        FileTemplate(id: "toml", name: "TOML 配置", filename: "新建配置.toml", enabled: false),
        FileTemplate(id: "ini", name: "INI 配置", filename: "新建配置.ini", enabled: false),
        FileTemplate(id: "tsv", name: "TSV 表格", filename: "新建表格.tsv", enabled: false),
        FileTemplate(id: "svg", name: "SVG 图形", filename: "新建图形.svg", enabled: false),
        FileTemplate(id: "swift", name: "Swift", filename: "新建文件.swift", enabled: false),
        FileTemplate(id: "java", name: "Java", filename: "NewClass.java", enabled: false)
    ]
}

struct OpenApplication: Codable {
    var id: String
    var name: String
    var bundleIdentifier: String
    var path: String?
    var enabled = true
    var opensDirectory: Bool { ["com.apple.Terminal", "com.googlecode.iterm2"].contains(bundleIdentifier) }

    func validate() throws {
        for value in [id, name, bundleIdentifier] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 512,
                  value.rangeOfCharacter(from: .controlCharacters) == nil else { throw UserError("应用名称或标识无效。") }
        }
        if let path {
            guard path.hasPrefix("/"), !path.utf8.contains(0), path.utf8.count <= 32768,
                  URL(fileURLWithPath: path).pathExtension.lowercased() == "app" else { throw UserError("请选择本机的 .app 应用。") }
        }
    }
    static let defaults = [
        OpenApplication(id: "openTerminal", name: "终端", bundleIdentifier: "com.apple.Terminal"),
        OpenApplication(id: "openITerm", name: "iTerm", bundleIdentifier: "com.googlecode.iterm2"),
        OpenApplication(id: "openVSCode", name: "VS Code", bundleIdentifier: "com.microsoft.VSCode"),
        OpenApplication(id: "openCursor", name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92")
    ]
}

struct Favorite: Codable { var id: String; var path: String }
struct Settings: Codable {
    var templates: [FileTemplate]
    var favorites: [Favorite]
    var templateCatalogVersion: Int?
    var openApplications: [OpenApplication]?
    // A missing key upgrades old settings; an explicit empty list stays empty.
    var applications: [OpenApplication] {
        get { openApplications ?? OpenApplication.defaults }
        set { openApplications = newValue }
    }
    var enabledApplications: [OpenApplication] { applications.filter(\.enabled) }
    func validateApplications() throws {
        for application in applications { try application.validate() }
        guard Set(applications.map(\.id)).count == applications.count,
              Set(applications.map(\.bundleIdentifier)).count == applications.count else { throw UserError("应用已在列表中，不能重复添加。") }
    }
    func application(for request: ActionRequest) throws -> OpenApplication {
        let id = request.action == .openApplication ? request.option : request.action.rawValue
        guard let application = enabledApplications.first(where: { $0.id == id }) else { throw UserError("应用已停用或移除，请重新打开菜单。") }
        try application.validate()
        return application
    }
    var enabledTemplates: [FileTemplate] { templates.filter(\.isEnabled) }

    mutating func migrateTemplates() {
        guard (templateCatalogVersion ?? 0) < 1 else { return }
        let existing = Set(templates.map(\.id))
        templates += BuiltInTemplates.all.filter { !existing.contains($0.id) }
        templateCatalogVersion = 1
    }
    static var defaults: Settings {
        Settings(templates: BuiltInTemplates.all, favorites: [Favorite(id: "home", path: SharedStore.realHome.path),
                       Favorite(id: "downloads", path: SharedStore.realHome.appendingPathComponent("Downloads").path)], templateCatalogVersion: 1)
    }
}

enum SharedStore {
    static let notification = "local.liudong.LocalRightClick.requestReady"
    // The sandbox home points into Containers; passwd identifies the account's real home.
    static var realHome: URL {
        guard let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir else { return FileManager.default.homeDirectoryForCurrentUser }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }
    static var base: URL { realHome.appendingPathComponent("Library/Application Support/LocalRightClick", isDirectory: true) }
    static var queue: URL { base.appendingPathComponent("Requests", isDirectory: true) }
    static func prepare() throws {
        for directory in [base, queue, base.appendingPathComponent("Templates")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
    static func load() throws -> Settings {
        let url = base.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        var settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
        settings.migrateTemplates()
        try settings.validateApplications()
        return settings
    }
    static func save(_ settings: Settings) throws {
        try settings.validateApplications()
        for template in settings.templates { try template.validate() }
        guard Set(settings.templates.map(\.id)).count == settings.templates.count else { throw UserError("模板标识重复，无法保存。") }
        try prepare()
        try JSONEncoder().encode(settings).write(to: base.appendingPathComponent("settings.json"), options: .atomic)
    }
    static func submit(_ request: ActionRequest) throws {
        try request.validate()
        try prepare()
        try JSONEncoder().encode(request).write(to: queue.appendingPathComponent(request.id.uuidString + ".json"), options: .atomic)
    }
    static func takeRequests() throws -> [ActionRequest] {
        try prepare()
        let files = try FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var requests: [ActionRequest] = []
        for file in files {
            let claimed = file.deletingPathExtension().appendingPathExtension("processing")
            do { try FileManager.default.moveItem(at: file, to: claimed) }
            catch { if !FileManager.default.fileExists(atPath: file.path) { continue }; throw error }
            defer { try? FileManager.default.removeItem(at: claimed) }
            guard (try claimed.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2_000_000 else { continue }
            guard let request = try? JSONDecoder().decode(ActionRequest.self, from: Data(contentsOf: claimed)),
                  (try? request.validate()) != nil else { continue }
            requests.append(request)
        }
        return requests.sorted { $0.createdAt < $1.createdAt }
    }
}

struct TransferResult {
    var completed: [URL] = []
    var failures: [String] = []
}

enum FileActions {
    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.utf8.contains(0),
              name.utf8.count <= 255 else { throw UserError("文件名不能为空，不能包含 /、: 或空字符，也不能超过 255 字节。") }
    }
    static func requireDirectory(_ url: URL) throws {
        guard url.isFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw UserError("目录不存在或不可访问：\(url.path)")
        }
    }
    static func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }
    static func createFile(in directory: URL, name: String, contents: Data) throws -> URL {
        try validateName(name)
        try requireDirectory(directory)
        let target = directory.appendingPathComponent(name)
        // withoutOverwriting uses exclusive creation, including existing dangling symlinks.
        try contents.write(to: target, options: .withoutOverwriting)
        return target
    }
    static func plannedTransfer(_ sources: [URL], to directory: URL) throws -> [(URL, URL)] {
        try requireDirectory(directory)
        guard !sources.isEmpty else { throw UserError("没有选中的文件。") }
        let targetDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        var destinations = Set<String>()
        var plan: [(URL, URL)] = []
        for source in sources {
            guard source.isFileURL, exists(source), source.path != "/" else { throw UserError("文件不存在或无法操作：\(source.path)") }
            let target = directory.appendingPathComponent(source.lastPathComponent)
            // Conservatively refuse case variants even on case-sensitive volumes.
            let nameKey = source.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()
            guard destinations.insert(nameKey).inserted, !exists(target) else { throw UserError("目标中有同名项目，未执行任何操作：\(target.lastPathComponent)") }
            let canonical = source.resolvingSymlinksInPath().standardizedFileURL
            if targetDirectory.path == canonical.path || targetDirectory.path.hasPrefix(canonical.path + "/") {
                throw UserError("不能把目录复制或移动到它自身或其子目录：\(source.lastPathComponent)")
            }
            for (other, _) in plan {
                let otherPath = other.resolvingSymlinksInPath().standardizedFileURL.path
                if canonical.path == otherPath || canonical.path.hasPrefix(otherPath + "/") || otherPath.hasPrefix(canonical.path + "/") {
                    throw UserError("选择中包含重复项目或父子目录，请分别操作。")
                }
            }
            plan.append((source, target))
        }
        return plan
    }
    static func transfer(_ sources: [URL], to directory: URL, move: Bool) throws -> TransferResult {
        let plan = try plannedTransfer(sources, to: directory)
        var result = TransferResult()
        for (source, target) in plan {
            do {
                if move { try FileManager.default.moveItem(at: source, to: target) }
                else { try FileManager.default.copyItem(at: source, to: target) }
                result.completed.append(target)
            } catch {
                result.failures.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return result
    }
}

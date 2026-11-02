import Foundation

@main struct CoreTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("LocalRightClick-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func check(_ value: @autoclosure () throws -> Bool) throws { let result = try value(); assert(result) }
        var count = 0
        func test(_ title: String, _ body: () throws -> Void) rethrows {
            try body(); count += 1; print("PASS \(title)")
        }
        func rejects(_ body: () throws -> Void) {
            do { try body(); fatalError("Expected rejection") } catch {}
        }
        let src = root.appendingPathComponent("source")
        let dst = root.appendingPathComponent("target")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        try test("create unicode, quotes, newline filename") {
            let u = try FileActions.createFile(in: src, name: "中文 ' \"\n.txt", contents: Data("hello".utf8))
            try check(try Data(contentsOf: u) == Data("hello".utf8))
        }
        try test("create refuses overwrite") {
            let u = try FileActions.createFile(in: src, name: "same.txt", contents: Data("original".utf8))
            rejects { _ = try FileActions.createFile(in: src, name: "same.txt", contents: Data()) }
            try check(try String(contentsOf: u, encoding: .utf8) == "original")
        }
        test("reject path traversal and invalid names") {
            for name in ["", " ", ".", "..", "../escape", "a/b", "a:b", "x\0y"] {
                rejects { _ = try FileActions.createFile(in: src, name: name, contents: Data()) }
            }
        }
        try test("copy and move preserve content") {
            let u = try FileActions.createFile(in: src, name: "copy.md", contents: Data("# test".utf8))
            let copied = try FileActions.transfer([u], to: dst, move: false)
            assert(copied.completed.count == 1 && copied.failures.isEmpty)
            assert(fm.fileExists(atPath: u.path))
            let moved = try FileActions.transfer(copied.completed, to: root, move: true)
            assert(moved.completed.count == 1 && moved.failures.isEmpty)
            assert(!fm.fileExists(atPath: copied.completed[0].path))
            try check(try String(contentsOf: moved.completed[0], encoding: .utf8) == "# test")
        }
        try test("preflight refuses entire batch when target exists") {
            let a = try FileActions.createFile(in: src, name: "a.txt", contents: Data())
            let b = try FileActions.createFile(in: src, name: "b.txt", contents: Data())
            _ = try FileActions.createFile(in: dst, name: "b.txt", contents: Data("keep".utf8))
            rejects { _ = try FileActions.transfer([a,b], to: dst, move: true) }
            assert(fm.fileExists(atPath: a.path) && fm.fileExists(atPath: b.path))
            assert(!fm.fileExists(atPath: dst.appendingPathComponent("a.txt").path))
        }
        try test("refuse copying directory into itself, including symlink destination") {
            let nested = src.appendingPathComponent("nested")
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            rejects { _ = try FileActions.transfer([src], to: nested, move: false) }
            let link = root.appendingPathComponent("link")
            try fm.createSymbolicLink(at: link, withDestinationURL: nested)
            rejects { _ = try FileActions.transfer([src], to: link, move: true) }
        }
        try test("dangling symlink counts as existing target") {
            let link = dst.appendingPathComponent("dangling.txt")
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "/nonexistent-lrc-target")
            let u = try FileActions.createFile(in: src, name: "dangling.txt", contents: Data())
            rejects { _ = try FileActions.transfer([u], to: dst, move: false) }
            rejects { _ = try FileActions.createFile(in: dst, name: "dangling.txt", contents: Data()) }
        }
        try test("templates preserve exact binary contents") {
            let bytes = Data([0, 1, 254, 255, 13, 10])
            let u = try FileActions.createFile(in: src, name: "template.bin", contents: bytes)
            let result = try FileActions.createFile(in: dst, name: "from-template.bin", contents: Data(contentsOf: u))
            try check(try Data(contentsOf: result) == bytes)
        }
        test("request validates action, timestamp and absolute paths") {
            let good = ActionRequest(action: .copy, paths: [src.path])
            assert((try? good.validate()) != nil)
            var stale = good; stale.createdAt = Date().addingTimeInterval(-120)
            rejects { try stale.validate() }
            var relative = good; relative.paths = ["../tmp"]
            rejects { try relative.validate() }
            var invalid = good; invalid.paths = ["/tmp/a\0b"]
            rejects { try invalid.validate() }
            let unknown = Data("{\"action\":\"shell\"}".utf8)
            rejects { _ = try JSONDecoder().decode(ActionRequest.self, from: unknown) }
        }
        try test("settings roundtrip and built-in templates") {
            let s = Settings.defaults
            let copy = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
            assert(["txt", "md", "json", "docx", "xlsx", "pptx", "rtf", "csv", "xml", "html", "py"].allSatisfy { id in copy.templates.contains { $0.id == id } }, "Missing common document templates")
            try check(try copy.templates[2].contents(in: root) == Data("{}\n".utf8))
        }
        try test("legacy migration preserves custom templates and does not duplicate on reload") {
            let old = Data(#"{"templates":[{"id":"custom","name":"工作记录","filename":"记录.md","storedFile":"custom.md"},{"id":"txt","name":"我的文本","filename":"备忘.txt"}],"favorites":[{"id":"keep","path":"/tmp"}]}"#.utf8)
            var settings = try JSONDecoder().decode(Settings.self, from: old)
            settings.migrateTemplates()
            assert(settings.templates[0].storedFile == "custom.md")
            assert(settings.templates[1].name == "我的文本")
            assert(settings.templates[0].isEnabled)
            assert(settings.favorites[0].id == "keep")
            let ids = settings.templates.map(\.id)
            settings.migrateTemplates()
            assert(settings.templates.map(\.id) == ids)
            assert(Set(ids).count == ids.count)
        }
        try test("disabled templates stay hidden and configured order survives reload") {
            var settings = Settings.defaults
            settings.templates[0].enabled = false
            settings.templates.swapAt(1, 2)
            let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
            assert(restored.enabledTemplates.prefix(2).map(\.id) == ["json", "md"])
            assert(!restored.enabledTemplates.contains { $0.id == "txt" })
        }
        try test("legacy app settings get defaults while an empty list stays empty") {
            let old = Data(#"{"templates":[],"favorites":[],"templateCatalogVersion":1}"#.utf8)
            var settings = try JSONDecoder().decode(Settings.self, from: old)
            assert(settings.applications.map(\.id) == ["openTerminal", "openITerm", "openVSCode", "openCursor"])
            settings.applications = []
            let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
            assert(restored.applications.isEmpty)
            assert(restored.templates.isEmpty && restored.favorites.isEmpty)
        }
        try test("app additions, disabled state and ordering survive reload") {
            var settings = Settings.defaults
            settings.applications.append(OpenApplication(id: "custom", name: "文本编辑", bundleIdentifier: "com.apple.TextEdit", path: "/System/Applications/TextEdit.app"))
            settings.applications[0].enabled = false
            settings.applications.swapAt(1, 4)
            let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
            try restored.validateApplications()
            assert(restored.enabledApplications.map(\.id) == ["custom", "openVSCode", "openCursor", "openITerm"])
            assert(restored.applications[1].path == "/System/Applications/TextEdit.app")
            assert(restored.applications[0].opensDirectory)
            assert(!restored.applications[1].opensDirectory)
        }
        try test("opening resolves only enabled configured apps including legacy requests") {
            var settings = Settings.defaults
            let request = ActionRequest(action: .openApplication, paths: [src.path], option: "openTerminal")
            try request.validate()
            try check(try settings.application(for: request).bundleIdentifier == "com.apple.Terminal")
            settings.applications[0].enabled = false
            rejects { _ = try settings.application(for: request) }
            rejects { _ = try settings.application(for: ActionRequest(action: .openTerminal, paths: [src.path])) }
            rejects { _ = try settings.application(for: ActionRequest(action: .openApplication, paths: [src.path], option: "/tmp/arbitrary.app")) }
            rejects { try ActionRequest(action: .openApplication, paths: [src.path]).validate() }
            rejects { try ActionRequest(action: .openApplication, option: "openTerminal").validate() }
        }
        test("app metadata rejects invalid paths, names and duplicate identities") {
            for path in ["relative.app", "/tmp/tool.sh", "/tmp/bad\0.app"] {
                rejects { try OpenApplication(id: "x", name: "App", bundleIdentifier: "test.app", path: path).validate() }
            }
            rejects { try OpenApplication(id: "x", name: " ", bundleIdentifier: "test.app").validate() }
            rejects { try OpenApplication(id: "x", name: "App", bundleIdentifier: "").validate() }
            var settings = Settings.defaults
            settings.applications.append(settings.applications[0])
            rejects { try settings.validateApplications() }
            settings.applications[4].id = "another"
            rejects { try settings.validateApplications() }
        }
        try test("legacy templates default to the grouped menu") {
            let old = Data(#"{"id":"txt","name":"文本","filename":"新建.txt"}"#.utf8)
            let template = try JSONDecoder().decode(FileTemplate.self, from: old)
            assert(template.isEnabled && !template.showsInMainMenu)
        }
        try test("template menu placement persists independently of enabled state and order") {
            var settings = Settings.defaults
            settings.templates[0].inMainMenu = true
            settings.templates[2].inMainMenu = true
            settings.templates[2].enabled = false
            settings.templates[3].inMainMenu = true
            settings.templates.swapAt(0, 3)
            let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
            let direct = restored.enabledTemplates.filter(\.showsInMainMenu)
            let grouped = restored.enabledTemplates.filter { !$0.showsInMainMenu }
            assert(direct.map(\.id) == ["docx", "txt"])
            assert(!grouped.contains { ["docx", "txt", "json"].contains($0.id) })
            assert(direct.count + grouped.count == restored.enabledTemplates.count)
            assert(restored.templates[2].showsInMainMenu && !restored.templates[2].isEnabled)
        }
        try test("every builtin creates a file using its real template") {
            let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
            let output = root.appendingPathComponent("builtins")
            try fm.createDirectory(at: output, withIntermediateDirectories: true)
            for template in Settings.defaults.templates {
                let file = try template.create(in: output, name: template.filename, base: root, resources: resources)
                let bytes = try Data(contentsOf: file)
                if ["docx", "xlsx", "pptx"].contains(template.id) { assert(bytes.starts(with: [0x50, 0x4b, 0x03, 0x04])) }
                if template.id == "json" { _ = try JSONSerialization.jsonObject(with: bytes) }
                if template.id == "rtf" { assert(String(decoding: bytes, as: UTF8.self).hasPrefix("{\\rtf1")) }
                assert(fm.fileExists(atPath: file.path))
            }
        }
        try test("imported files and iWork packages are independent copies and refuse overwrite") {
            let original = try FileActions.createFile(in: src, name: "自定义.wps", contents: Data([0, 255, 42]))
            let imported = try FileTemplate.importFile(original, into: root)
            try Data([1]).write(to: original)
            let created = try imported.create(in: dst, name: "新文档.wps", base: root)
            try check(try Data(contentsOf: created) == Data([0, 255, 42]))
            let package = src.appendingPathComponent("测试.pages")
            try fm.createDirectory(at: package, withIntermediateDirectories: true)
            _ = try FileActions.createFile(in: package, name: "Document.iwa", contents: Data([10, 20, 30]))
            let packaged = try FileTemplate.importFile(package, into: root)
            let result = try packaged.create(in: dst, name: "副本.pages", base: root)
            try check(try Data(contentsOf: result.appendingPathComponent("Document.iwa")) == Data([10, 20, 30]))
            rejects { _ = try packaged.create(in: dst, name: "副本.pages", base: root) }
            rejects { _ = try packaged.create(in: dst, name: "../escape.pages", base: root) }
        }
        test("template metadata rejects traversal and invalid office extensions") {
            rejects { try FileTemplate(id: "custom", name: "Test", filename: "../file.txt").validate() }
            rejects { try FileTemplate(id: "custom", name: "  ", filename: "file.txt").validate() }
            rejects { try FileTemplate(id: "custom", name: "Test", filename: "file.txt", storedFile: "../escape").validate() }
            rejects { try FileTemplate(id: "docx", name: "Word", filename: "fake.txt").validate() }
        }
        try test("accepted request stays valid while waiting behind long operation") {
            var request = ActionRequest(action: .copy, paths: [src.path])
            try request.validate()
            request.createdAt = Date().addingTimeInterval(-120)
            rejects { try request.validate() }
            try request.validate(checkFreshness: false)
            request.paths = ["../escape"]
            rejects { try request.validate(checkFreshness: false) }
        }
        try test("partial failure reports successful and unreadable files") {
            let good = try FileActions.createFile(in: src, name: "readable.txt", contents: Data("keep".utf8))
            let blocked = try FileActions.createFile(in: src, name: "unreadable.txt", contents: Data("private".utf8))
            try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
            defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: blocked.path) }
            let report = try FileActions.transfer([good, blocked], to: dst, move: false)
            assert(report.completed.count == 1 && report.failures.count == 1)
            assert(fm.fileExists(atPath: good.path) && fm.fileExists(atPath: blocked.path))
        }
        print("\(count) tests passed")
    }
}

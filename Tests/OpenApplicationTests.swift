import Cocoa

@main struct OpenApplicationTests {
    static func main() throws {
        let editor = try OpenApplication.from(URL(fileURLWithPath: "/System/Applications/TextEdit.app"))
        assert(editor.bundleIdentifier == "com.apple.TextEdit")
        assert(editor.installedURL?.path == "/System/Applications/TextEdit.app")
        assert(!editor.opensDirectory)
        var moved = editor; moved.path = "/nonexistent/TextEdit.app"
        assert(moved.installedURL != nil, "Registered apps should survive a stale path")
        let missing = OpenApplication(id: "missing", name: "Missing", bundleIdentifier: "local.lrc.nonexistent-test", path: "/System/Applications/TextEdit.app")
        assert(missing.installedURL == nil, "A different bundle at the old path must not be launched")
        print("PASS installed application identity and stale-path resolution")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LRC-app-test-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for url in [root, URL(fileURLWithPath: "/bin/sh"), URL(fileURLWithPath: "/nonexistent.app")] {
            do { _ = try OpenApplication.from(url); fatalError("Invalid app accepted") } catch {}
        }
        print("PASS app picker rejects scripts, missing apps and invalid bundles")
    }
}

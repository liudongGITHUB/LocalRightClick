import Foundation

@main struct LegacyLoginItemTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LRC-login-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let item = LegacyLoginItem(directory: root, appURL: URL(fileURLWithPath: "/Applications/轻右键 ' $ 测试.app"))
        func check(_ value: @autoclosure () throws -> Bool) throws { let result = try value(); assert(result) }
        try check(!item.isEnabled())
        try item.setEnabled(true)
        try check(item.isEnabled())
        let original = try Data(contentsOf: item.url)
        let plist = try PropertyListSerialization.propertyList(from: original, format: nil) as! [String: Any]
        assert(plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "-g", item.appURL.path, "--args", "--login"])
        assert(plist["KeepAlive"] == nil && plist["RunAtLoad"] as? Bool == true)
        try item.setEnabled(true)
        try check(item.isEnabled())
        try item.setEnabled(false)
        try item.setEnabled(false)
        try check(!item.isEnabled())
        print("PASS legacy login registration, exact arguments, repeat enable and disable")
        let unrelated = Data("not our login configuration".utf8)
        try unrelated.write(to: item.url)
        for enabled in [true, false] {
            do { try item.setEnabled(enabled); fatalError("Unrelated file was changed") } catch {}
            try check(Data(contentsOf: item.url) == unrelated)
        }
        try FileManager.default.removeItem(at: item.url)
        let target = root.appendingPathComponent("original.plist")
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: item.url, withDestinationURL: target)
        do { try item.setEnabled(false); fatalError("Symlink was accepted") } catch {}
        try check(Data(contentsOf: target) == original)
        print("PASS legacy login refuses unrelated files and symlinks")
    }
}

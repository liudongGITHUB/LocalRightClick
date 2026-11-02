import Foundation

// macOS 12 uses a per-user, one-shot LaunchAgent; macOS 13+ uses SMAppService.
struct LegacyLoginItem {
    static let label = "local.liudong.LocalRightClick.login"
    let directory: URL
    let appURL: URL
    var url: URL { directory.appendingPathComponent(Self.label + ".plist") }
    static var current: LegacyLoginItem {
        LegacyLoginItem(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),
                        appURL: Bundle.main.bundleURL)
    }
    private func configuration() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let data = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any],
              data["Label"] as? String == Self.label,
              data["LocalRightClickLoginItemVersion"] as? Int == 1 else {
            throw NSError(domain: Self.label, code: 1, userInfo: [NSLocalizedDescriptionKey: "登录项配置不属于轻右键或已损坏，未修改该文件。"])
        }
        return data
    }
    func isEnabled() throws -> Bool {
        guard let data = try configuration() else { return false }
        return data["RunAtLoad"] as? Bool == true && data["ProgramArguments"] as? [String] == arguments
    }
    private var arguments: [String] { ["/usr/bin/open", "-g", appURL.path, "--args", "--login"] }
    func setEnabled(_ enabled: Bool) throws {
        let existing = try configuration()
        if !enabled {
            if existing != nil { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data: [String: Any] = ["Label": Self.label, "ProgramArguments": arguments,
                                 "RunAtLoad": true, "LimitLoadToSessionType": "Aqua", "LocalRightClickLoginItemVersion": 1]
        let bytes = try PropertyListSerialization.data(fromPropertyList: data, format: .xml, options: 0)
        try bytes.write(to: url, options: .atomic)
    }
}

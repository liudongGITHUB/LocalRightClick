import Cocoa

// Only replace LaunchServices calls; keep the running application's real identity.
final class TestWorkspace: NSWorkspace {
    var applications: [NSRunningApplication] = []
    var openResult = false
    var opened: [URL] = []
    override var runningApplications: [NSRunningApplication] { applications }
    override func open(_ url: URL) -> Bool {
        opened.append(url)
        return openResult
    }
}

@main struct HostLaunchTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String = "Unexpected host launch result") {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
    static func main() {
        _ = NSApplication.shared
        let workspace = TestWorkspace()
        let host = Bundle.main.bundleURL
        check(NSRunningApplication.current.bundleURL == host, "Run this test inside its app bundle")
        workspace.applications = [.current]
        check(wakeHostApplication(at: host, workspace: workspace), "An already running host must remain usable when LaunchServices denies opening it")
        check(workspace.opened.isEmpty, "Do not reopen the running host")
        print("PASS running host bypasses a denied launch")

        let other = host.deletingLastPathComponent().appendingPathComponent("Other.app")
        check(!wakeHostApplication(at: other, workspace: workspace), "A different running app must not hide a launch failure")
        check(workspace.opened == [other])
        workspace.applications = []
        workspace.openResult = true
        check(wakeHostApplication(at: host, workspace: workspace))
        check(workspace.opened == [other, host])
        print("PASS stopped host launches and launch failures are preserved")
    }
}

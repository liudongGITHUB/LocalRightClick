import Cocoa

func wakeHostApplication(at url: URL, workspace: NSWorkspace = .shared) -> Bool {
    // Reopening a running host can be denied to a sandboxed Finder extension on older macOS.
    if workspace.runningApplications.contains(where: {
        !$0.isTerminated && $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
    }) { return true }
    return workspace.open(url)
}

func wasLaunchedAtLogin(_ event: NSAppleEventDescriptor?, arguments: [String] = CommandLine.arguments) -> Bool {
    arguments.contains("--login") || event?.eventID == kAEOpenApplication &&
        event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
}

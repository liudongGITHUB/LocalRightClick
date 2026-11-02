import Cocoa

func wasLaunchedAtLogin(_ event: NSAppleEventDescriptor?, arguments: [String] = CommandLine.arguments) -> Bool {
    arguments.contains("--login") || event?.eventID == kAEOpenApplication &&
        event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
}

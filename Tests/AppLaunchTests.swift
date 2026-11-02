import Cocoa

@main struct AppLaunchTests {
    static func main() {
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication,
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        assert(!wasLaunchedAtLogin(nil, arguments: []))
        assert(wasLaunchedAtLogin(nil, arguments: ["LocalRightClick", "--login"]))
        assert(!wasLaunchedAtLogin(event))
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        assert(wasLaunchedAtLogin(event))
        let reopen = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEReopenApplication,
                                           targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        reopen.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        assert(!wasLaunchedAtLogin(reopen), "Manual reopen must continue to show settings")
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsServiceItem), forKeyword: keyAEPropData)
        assert(!wasLaunchedAtLogin(event))
        print("PASS login launch detection distinguishes manual launch, reopen and service events")
    }
}

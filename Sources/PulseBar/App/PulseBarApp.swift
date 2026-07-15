import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.showSettings()
        return true
    }
}

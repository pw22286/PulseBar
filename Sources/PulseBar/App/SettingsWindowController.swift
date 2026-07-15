import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let preferences: WaveformPreferences

    init(preferences: WaveformPreferences) {
        self.preferences = preferences

        let content = SettingsView(preferences: preferences)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PulseBar 设置"
        window.contentViewController = NSHostingController(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        preferences.refreshLoginItemStatus()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

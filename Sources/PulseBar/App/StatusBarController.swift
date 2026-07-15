import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let capture = AudioCaptureService()
    private let preferences = WaveformPreferences()
    private let statusItem = NSStatusBar.system.statusItem(withLength: 38)
    private var cancellables = Set<AnyCancellable>()
    private lazy var settingsWindow = SettingsWindowController(
        preferences: preferences
    )

    override init() {
        super.init()

        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "PulseBar"

        capture.$levels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levels in self?.updateIcon(levels) }
            .store(in: &cancellables)

        capture.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenu() }
            .store(in: &cancellables)

        preferences.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateIcon(self?.capture.levels ?? [])
                }
            }
            .store(in: &cancellables)

        if preferences.autoListen {
            Task { await capture.start() }
        }
    }

    private func updateIcon(_ levels: [CGFloat]) {
        statusItem.button?.image = WaveformRenderer.statusImage(
            levels: levels,
            preferences: preferences
        )
        statusItem.button?.setAccessibilityLabel("系统音频波形")
    }

    private func updateMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: capture.state.title, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let toggle = NSMenuItem(
            title: capture.isCapturing ? "停止" : "开始",
            action: #selector(toggleCapture),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())
        let settings = NSMenuItem(
            title: "PulseBar 设置...",
            action: #selector(openAppSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        if capture.state == .permissionDenied {
            let permission = NSMenuItem(
                title: "音频权限...",
                action: #selector(openPrivacySettings),
                keyEquivalent: ""
            )
            permission.target = self
            menu.addItem(permission)

            let restart = NSMenuItem(
                title: "授权后重启 PulseBar",
                action: #selector(relaunch),
                keyEquivalent: ""
            )
            restart.target = self
            menu.addItem(restart)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 PulseBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func showSettings() {
        settingsWindow.present()
    }

    @objc private func toggleCapture() {
        Task {
            if capture.isCapturing {
                await capture.stop()
            } else {
                await capture.start(requestPermission: true)
                if capture.state == .permissionDenied {
                    openPrivacySettings()
                }
            }
        }
    }

    @objc private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openAppSettings() {
        showSettings()
    }

    @objc private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if error == nil {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

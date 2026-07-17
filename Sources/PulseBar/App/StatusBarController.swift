import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let capture = AudioCaptureService()
    private let preferences = WaveformPreferences()
    private let statusItem = NSStatusBar.system.statusItem(withLength: 38)
    private var peakLevels: [CGFloat] = []
    private var shouldListen = false
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private lazy var settingsWindow = SettingsWindowController(
        preferences: preferences
    )

    override init() {
        super.init()
        shouldListen = preferences.autoListen

        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "PulseBar"
        statusItem.length = preferences.statusItemWidth

        capture.$levels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levels in
                self?.updatePeakLevels(with: levels)
                self?.updateIcon(levels)
            }
            .store(in: &cancellables)

        capture.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if !capture.isCapturing {
                    peakLevels = Array(repeating: 0, count: capture.levels.count)
                    updateIcon(capture.levels)
                }
                handleCaptureState(state)
                updateMenu()
            }
            .store(in: &cancellables)

        preferences.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateIcon(self?.capture.levels ?? [])
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon(self?.capture.levels ?? [])
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.suspendForSleep() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resumeAfterWake() }
            .store(in: &cancellables)

        if shouldListen {
            Task { await capture.start() }
        }
    }

    private func updateIcon(_ levels: [CGFloat]) {
        statusItem.length = preferences.statusItemWidth
        statusItem.button?.image = WaveformRenderer.statusImage(
            levels: levels,
            lowFrequencyLevels: capture.lowFrequencyLevels,
            highFrequencyLevels: capture.highFrequencyLevels,
            peakLevels: peakLevels,
            preferences: preferences
        )
        statusItem.button?.setAccessibilityLabel("系统音频波形")
    }

    private func updatePeakLevels(with levels: [CGFloat]) {
        if peakLevels.count != levels.count {
            peakLevels = levels
            return
        }
        peakLevels = zip(peakLevels, levels).map { peak, level in
            max(level, peak - 0.018)
        }
    }

    private func updateMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: capture.state.title, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let toggle = NSMenuItem(
            title: shouldListen ? "停止" : "开始",
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

        let about = NSMenuItem(
            title: "关于 PulseBar",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

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
            if shouldListen {
                shouldListen = false
                reconnectTask?.cancel()
                reconnectTask = nil
                await capture.stop()
            } else {
                shouldListen = true
                reconnectAttempts = 0
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

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "未知"
        let alert = NSAlert()
        alert.messageText = "PulseBar"
        alert.informativeText = "系统音频菜单栏频谱 · 版本 \(version)"
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "好")
        alert.runModal()
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

    private func handleCaptureState(_ state: AudioCaptureService.State) {
        switch state {
        case .capturing:
            reconnectAttempts = 0
            reconnectTask?.cancel()
            reconnectTask = nil
        case .permissionDenied:
            shouldListen = false
        case .failed:
            scheduleReconnect()
        case .idle, .starting:
            break
        }
    }

    private func scheduleReconnect() {
        guard shouldListen, reconnectTask == nil else { return }
        guard reconnectAttempts < 3 else {
            shouldListen = false
            return
        }
        reconnectAttempts += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self, shouldListen else { return }
            reconnectTask = nil
            await capture.start()
        }
    }

    private func suspendForSleep() {
        reconnectTask?.cancel()
        reconnectTask = nil
        guard shouldListen else { return }
        Task { await capture.stop() }
    }

    private func resumeAfterWake() {
        guard shouldListen else { return }
        reconnectAttempts = 0
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self, shouldListen else { return }
            reconnectTask = nil
            await capture.start()
        }
    }
}

import AppKit
import Combine
import ServiceManagement

enum WaveformAnchor: String, CaseIterable, Identifiable {
    case upward
    case centered
    case downward

    var id: Self { self }

    var title: String {
        switch self {
        case .upward: "向上"
        case .centered: "居中"
        case .downward: "向下"
        }
    }
}

enum WaveformShape: String, CaseIterable, Identifiable {
    case fineSpectrum = "bars"
    case waveLines
    case softSpectrum
    case mountains

    var id: Self { self }

    var title: String {
        switch self {
        case .fineSpectrum: "细条"
        case .waveLines: "波浪"
        case .softSpectrum: "柔光"
        case .mountains: "山峰"
        }
    }
}

enum WaveformColorMode: String, CaseIterable, Identifiable {
    case system
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .custom: "单色"
        }
    }
}

enum WaveformFlowDirection: String, CaseIterable, Identifiable {
    case centerOutward
    case rightToLeft

    var id: Self { self }

    var title: String {
        switch self {
        case .centerOutward: "中心向两侧"
        case .rightToLeft: "右 → 左"
        }
    }
}

enum WaveformIdleStyle: String, CaseIterable, Identifiable {
    case dots
    case shortBars

    var id: Self { self }

    var title: String {
        switch self {
        case .dots: "圆点"
        case .shortBars: "短竖线"
        }
    }
}

@MainActor
final class WaveformPreferences: ObservableObject {
    private enum Key {
        static let anchor = "waveform.anchor"
        static let shape = "waveform.shape"
        static let colorMode = "waveform.colorMode"
        static let customColor = "waveform.customColor"
        static let flowDirection = "waveform.flowDirection"
        static let idleStyle = "waveform.idleStyle"
        static let autoListen = "capture.autoListen"
    }

    private let defaults: UserDefaults

    @Published var anchor: WaveformAnchor {
        didSet { defaults.set(anchor.rawValue, forKey: Key.anchor) }
    }
    @Published var shape: WaveformShape {
        didSet { defaults.set(shape.rawValue, forKey: Key.shape) }
    }
    @Published var colorMode: WaveformColorMode {
        didSet { defaults.set(colorMode.rawValue, forKey: Key.colorMode) }
    }
    @Published var customColorHex: String {
        didSet { defaults.set(customColorHex, forKey: Key.customColor) }
    }
    @Published var flowDirection: WaveformFlowDirection {
        didSet { defaults.set(flowDirection.rawValue, forKey: Key.flowDirection) }
    }
    @Published var idleStyle: WaveformIdleStyle {
        didSet { defaults.set(idleStyle.rawValue, forKey: Key.idleStyle) }
    }
    @Published var autoListen: Bool {
        didSet { defaults.set(autoListen, forKey: Key.autoListen) }
    }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginItemNeedsApproval = false
    @Published private(set) var loginItemError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        anchor = WaveformAnchor(rawValue: defaults.string(forKey: Key.anchor) ?? "") ?? .centered
        shape = WaveformShape(rawValue: defaults.string(forKey: Key.shape) ?? "") ?? .fineSpectrum
        colorMode = WaveformColorMode(rawValue: defaults.string(forKey: Key.colorMode) ?? "") ?? .system
        customColorHex = defaults.string(forKey: Key.customColor) ?? "#FF4D67"
        flowDirection = WaveformFlowDirection(
            rawValue: defaults.string(forKey: Key.flowDirection) ?? ""
        ) ?? .centerOutward
        idleStyle = WaveformIdleStyle(rawValue: defaults.string(forKey: Key.idleStyle) ?? "") ?? .dots
        autoListen = defaults.object(forKey: Key.autoListen) as? Bool ?? true
        refreshLoginItemStatus()
    }

    var customColor: NSColor {
        NSColor(hexRGB: customColorHex) ?? .systemPink
    }

    func setCustomColor(_ color: NSColor) {
        guard let color = color.usingColorSpace(.sRGB) else { return }
        customColorHex = String(
            format: "#%02X%02X%02X",
            Int(color.redComponent * 255),
            Int(color.greenComponent * 255),
            Int(color.blueComponent * 255)
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }

    func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginItemNeedsApproval = status == .requiresApproval
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private extension NSColor {
    convenience init?(hexRGB: String) {
        let value = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

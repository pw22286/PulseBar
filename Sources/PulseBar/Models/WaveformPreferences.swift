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

    func title(for orientation: WaveformOrientation) -> String {
        guard orientation == .horizontal else { return title }
        switch self {
        case .upward: return "向左"
        case .centered: return "居中"
        case .downward: return "向右"
        }
    }
}

enum WaveformShape: String, CaseIterable, Identifiable {
    case fineSpectrum = "bars"
    case waveLines
    case softSpectrum
    case mountains

    var id: Self { self }

    var isBarStyle: Bool {
        self == .fineSpectrum || self == .softSpectrum
    }

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
        case .system: "系统色"
        case .custom: "单色"
        }
    }
}

enum WaveformOrientation: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: Self { self }

    var title: String {
        switch self {
        case .vertical: "竖向"
        case .horizontal: "横向"
        }
    }
}

enum SpectrumWidth: String, CaseIterable, Identifiable {
    case compact
    case standard
    case relaxed
    case wide

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: "紧凑"
        case .standard: "默认"
        case .relaxed: "舒展"
        case .wide: "宽阔"
        }
    }

    var points: CGFloat {
        switch self {
        case .compact: 30
        case .standard: 38
        case .relaxed: 69
        case .wide: 84
        }
    }
}

@MainActor
final class WaveformPreferences: ObservableObject {
    private enum Key {
        static let anchor = "waveform.anchor"
        static let shape = "waveform.shape"
        static let colorMode = "waveform.colorMode"
        static let customColor = "waveform.singleColor"
        static let orientation = "waveform.orientation"
        static let spectrumWidth = "waveform.spectrumWidth"
        static let peakHold = "waveform.peakHold"
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
    @Published var orientation: WaveformOrientation {
        didSet { defaults.set(orientation.rawValue, forKey: Key.orientation) }
    }
    @Published var spectrumWidth: SpectrumWidth {
        didSet { defaults.set(spectrumWidth.rawValue, forKey: Key.spectrumWidth) }
    }
    @Published var peakHold: Bool {
        didSet { defaults.set(peakHold, forKey: Key.peakHold) }
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
        customColorHex = defaults.string(forKey: Key.customColor) ?? "#FF3B30"
        orientation = WaveformOrientation(
            rawValue: defaults.string(forKey: Key.orientation) ?? ""
        ) ?? .vertical
        spectrumWidth = SpectrumWidth(
            rawValue: defaults.string(forKey: Key.spectrumWidth) ?? ""
        ) ?? .standard
        peakHold = defaults.object(forKey: Key.peakHold) as? Bool ?? false
        autoListen = defaults.object(forKey: Key.autoListen) as? Bool ?? true
        refreshLoginItemStatus()
    }

    var customColor: NSColor {
        NSColor(hexRGB: customColorHex) ?? .white
    }

    var statusItemWidth: CGFloat {
        orientation == .vertical ? spectrumWidth.points : SpectrumWidth.standard.points
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

extension NSColor {
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

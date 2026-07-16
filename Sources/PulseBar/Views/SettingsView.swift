import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: WaveformPreferences

    var body: some View {
        Form {
            Section("频谱样式") {
                WaveformStyleGrid(preferences: preferences)
            }

            Section("外观") {
                Picker("波形方向", selection: $preferences.orientation) {
                    ForEach(WaveformOrientation.allCases) { orientation in
                        Text(orientation.title).tag(orientation)
                    }
                }
                .pickerStyle(.segmented)

                Picker("伸展方向", selection: $preferences.anchor) {
                    ForEach(WaveformAnchor.allCases) { anchor in
                        Text(anchor.title(for: preferences.orientation)).tag(anchor)
                    }
                }
                .pickerStyle(.segmented)

                Picker("颜色", selection: $preferences.colorMode) {
                    ForEach(WaveformColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if preferences.colorMode == .custom {
                    ColorPresetPicker(preferences: preferences)

                    ColorPicker(
                        "高级调色",
                        selection: customColor,
                        supportsOpacity: false
                    )
                }

                if preferences.orientation == .vertical {
                    SpectrumWidthSlider(preferences: preferences)
                }

                Toggle("峰值悬停", isOn: $preferences.peakHold)
                    .opacity(preferences.shape.isBarStyle ? 1 : 0)
                    .allowsHitTesting(preferences.shape.isBarStyle)
                    .accessibilityHidden(!preferences.shape.isBarStyle)
                    .frame(height: 20)
            }

            Section("启动") {
                Toggle("启动后自动监听", isOn: $preferences.autoListen)
                Toggle("登录时启动", isOn: launchAtLogin)

                if preferences.loginItemNeedsApproval {
                    Button("在系统设置中批准") {
                        preferences.openLoginItemSettings()
                    }
                }

                if let error = preferences.loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: preferences.customColor) },
            set: { preferences.setCustomColor(NSColor($0)) }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { preferences.launchAtLogin },
            set: { preferences.setLaunchAtLogin($0) }
        )
    }

}

private struct ColorPreset: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(nsColor: NSColor(hexRGB: hex) ?? .white) }
}

private struct ColorPresetPicker: View {
    @ObservedObject var preferences: WaveformPreferences

    private let presets = [
        ColorPreset(name: "红", hex: "#FF3B30"),
        ColorPreset(name: "橙", hex: "#FF9500"),
        ColorPreset(name: "黄", hex: "#FFCC00"),
        ColorPreset(name: "绿", hex: "#34C759"),
        ColorPreset(name: "青", hex: "#32ADE6"),
        ColorPreset(name: "蓝", hex: "#007AFF"),
        ColorPreset(name: "紫", hex: "#AF52DE")
    ]

    var body: some View {
        LabeledContent("预设颜色") {
            HStack(spacing: 9) {
                ForEach(presets) { preset in
                    Button {
                        preferences.customColorHex = preset.hex
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle()
                                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                            }
                            .overlay {
                                if preferences.customColorHex == preset.hex {
                                    Circle()
                                        .stroke(Color.accentColor, lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                    .accessibilityLabel(preset.name)
                    .accessibilityValue(
                        preferences.customColorHex == preset.hex ? "已选择" : ""
                    )
                }
            }
        }
    }
}

private struct WaveformStyleGrid: View {
    @ObservedObject var preferences: WaveformPreferences

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(WaveformShape.allCases) { shape in
                Button {
                    preferences.shape = shape
                } label: {
                    ZStack(alignment: .topTrailing) {
                        WaveformPreview(shape: shape)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .accessibilityHidden(true)

                        if preferences.shape == shape {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(7)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                    .background(
                        Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(
                                preferences.shape == shape
                                    ? Color.accentColor.opacity(0.8)
                                    : Color.primary.opacity(0.08),
                                lineWidth: preferences.shape == shape ? 1.5 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .help(shape.title)
                .accessibilityLabel(shape.title)
                .accessibilityValue(preferences.shape == shape ? "已选择" : "")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SpectrumWidthSlider: View {
    @ObservedObject var preferences: WaveformPreferences

    var body: some View {
        LabeledContent("频谱宽度") {
            HStack(spacing: 10) {
                Slider(value: selection, in: 0...3, step: 1)
                    .frame(minWidth: 150)

                Text(preferences.spectrumWidth.title)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private var selection: Binding<Double> {
        Binding(
            get: {
                Double(SpectrumWidth.allCases.firstIndex(of: preferences.spectrumWidth) ?? 1)
            },
            set: { value in
                let index = min(3, max(0, Int(value.rounded())))
                preferences.spectrumWidth = SpectrumWidth.allCases[index]
            }
        )
    }
}

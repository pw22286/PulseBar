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
                Picker("伸展方向", selection: $preferences.anchor) {
                    ForEach(WaveformAnchor.allCases) { anchor in
                        Text(anchor.title).tag(anchor)
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
                    ColorPicker(
                        "单色颜色",
                        selection: customColor,
                        supportsOpacity: false
                    )
                }

                Picker("扩散方向", selection: $preferences.flowDirection) {
                    ForEach(WaveformFlowDirection.allCases) { direction in
                        Label(
                            direction.title,
                            systemImage: direction == .rightToLeft
                                ? "arrow.left"
                                : "arrow.left.and.right"
                        )
                        .tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                SpectrumWidthSlider(preferences: preferences)

                if preferences.shape == .fineSpectrum || preferences.shape == .softSpectrum {
                    Picker("静音状态", selection: $preferences.idleStyle) {
                        ForEach(WaveformIdleStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("频谱宽度")
                Spacer()
                Text(preferences.spectrumWidth.title)
                    .foregroundStyle(.secondary)
            }

            Slider(value: selection, in: 0...3, step: 1)

            HStack(spacing: 0) {
                ForEach(SpectrumWidth.allCases) { width in
                    Text(width.title)
                        .font(.caption2)
                        .foregroundStyle(
                            preferences.spectrumWidth == width ? .primary : .secondary
                        )
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("频谱宽度")
        .accessibilityValue(preferences.spectrumWidth.title)
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

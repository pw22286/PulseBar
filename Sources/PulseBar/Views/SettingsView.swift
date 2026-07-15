import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: WaveformPreferences

    var body: some View {
        VStack(spacing: 0) {
            WaveformPreview(shape: preferences.shape)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(height: 78)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .padding(.horizontal, 34)
                .padding(.vertical, 12)

            Divider()

            Form {
                Section("外观") {
                    Picker("波形样式", selection: $preferences.shape) {
                        ForEach(WaveformShape.allCases) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("伸展方向", selection: $preferences.anchor) {
                        ForEach(WaveformAnchor.allCases) { anchor in
                            Text(anchor.title).tag(anchor)
                        }
                    }
                    .pickerStyle(.segmented)

                    ColorModePicker(preferences: preferences)

                    if preferences.colorMode == .custom {
                        ColorPicker(
                            "单色",
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
        }
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

private struct ColorModePicker: View {
    @ObservedObject var preferences: WaveformPreferences

    var body: some View {
        HStack {
            Text("颜色")
            Spacer()

            HStack(spacing: 12) {
                ForEach(WaveformColorMode.allCases) { mode in
                    Button {
                        preferences.colorMode = mode
                    } label: {
                        swatch(for: mode)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .stroke(
                                        preferences.colorMode == mode ? Color.accentColor : .clear,
                                        lineWidth: 2
                                    )
                                    .padding(-4)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(mode.title)
                    .accessibilityLabel(mode.title)
                }
            }
            .padding(.trailing, 4)
        }
    }

    @ViewBuilder
    private func swatch(for mode: WaveformColorMode) -> some View {
        switch mode {
        case .system:
            Circle().fill(.primary)
        case .custom:
            Circle().fill(Color(nsColor: preferences.customColor))
        }
    }
}

import Foundation

@main
enum SpectrumAnalyzerCheck {
    static func main() {
        let silenceAnalyzer = SpectrumAnalyzer()
        guard let silence = silenceAnalyzer.process(
            samples: Array(repeating: 0, count: 1_024),
            sampleRate: 48_000
        ), silence.levels.count == 32, silence.levels.max() ?? 1 < 0.001 else {
            fatalError("Silence spectrum check failed")
        }

        let sampleRate = 48_000.0
        func tone(_ frequency: Double) -> [Float] {
            (0..<1_024).map { index in
                Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.5)
            }
        }

        guard let bass = SpectrumAnalyzer().process(samples: tone(120), sampleRate: sampleRate),
              (bass.lowFrequencyLevels.max() ?? 0)
                > (bass.highFrequencyLevels.max() ?? 0) else {
            fatalError("Low-frequency layer check failed")
        }
        guard let treble = SpectrumAnalyzer().process(samples: tone(4_000), sampleRate: sampleRate),
              (treble.highFrequencyLevels.max() ?? 0)
                > (treble.lowFrequencyLevels.max() ?? 0) else {
            fatalError("High-frequency layer check failed")
        }

        print("Spectrum checks passed")
    }
}

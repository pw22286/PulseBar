import Foundation

@main
enum SpectrumAnalyzerCheck {
    static func main() {
        let silenceAnalyzer = SpectrumAnalyzer()
        guard let silence = silenceAnalyzer.process(
            samples: Array(repeating: 0, count: 1_024),
            sampleRate: 48_000
        ), silence.count == 32, silence.max() ?? 1 < 0.001 else {
            fatalError("Silence spectrum check failed")
        }

        let toneAnalyzer = SpectrumAnalyzer()
        let sampleRate = 48_000.0
        let samples = (0..<1_024).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.5)
        }
        guard let tone = toneAnalyzer.process(samples: samples, sampleRate: sampleRate),
              tone.count == 32,
              tone.max() ?? 0 > 0.1 else {
            fatalError("Tone spectrum check failed")
        }

        print("Spectrum checks passed")
    }
}

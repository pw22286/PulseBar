import Accelerate
import CoreGraphics

struct SpectrumFrame {
    let levels: [CGFloat]
    let lowFrequencyLevels: [CGFloat]
    let highFrequencyLevels: [CGFloat]
}

final class SpectrumAnalyzer {
    let bandCount: Int

    private let fftSize = 1_024
    private let minimumFrequency = 55.0
    private let maximumFrequency = 16_000.0
    private let crossoverFrequency = 500.0
    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    private var pendingSamples: [Float] = []
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]
    private var smoothed: [Float]

    init(bandCount: Int = 32) {
        self.bandCount = bandCount
        log2FFTSize = vDSP_Length(log2(Double(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2FFTSize, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("Unable to create FFT setup")
        }
        fftSetup = setup
        window = Array(repeating: 0, count: fftSize)
        windowed = Array(repeating: 0, count: fftSize)
        real = Array(repeating: 0, count: fftSize / 2)
        imaginary = Array(repeating: 0, count: fftSize / 2)
        magnitudes = Array(repeating: 0, count: fftSize / 2)
        smoothed = Array(repeating: 0, count: bandCount)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func reset() {
        pendingSamples.removeAll(keepingCapacity: true)
        smoothed = Array(repeating: 0, count: bandCount)
    }

    func process(samples: [Float], sampleRate: Double) -> SpectrumFrame? {
        guard !samples.isEmpty else { return nil }
        pendingSamples.append(contentsOf: samples)
        guard pendingSamples.count >= fftSize else { return nil }

        let frame = Array(pendingSamples.suffix(fftSize))
        let retainedCount = fftSize / 2
        pendingSamples = Array(pendingSamples.suffix(retainedCount))

        vDSP_vmul(
            frame,
            1,
            window,
            1,
            &windowed,
            1,
            vDSP_Length(fftSize)
        )

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )
                windowed.withUnsafeBytes { rawBuffer in
                    let complex = rawBuffer.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(
                        complex.baseAddress!,
                        2,
                        &split,
                        1,
                        vDSP_Length(fftSize / 2)
                    )
                }
                vDSP_fft_zrip(
                    fftSetup,
                    &split,
                    1,
                    log2FFTSize,
                    FFTDirection(FFT_FORWARD)
                )
                vDSP_zvmags(
                    &split,
                    1,
                    &magnitudes,
                    1,
                    vDSP_Length(fftSize / 2)
                )
            }
        }

        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(fftSize))
        let rawBands = bands(sampleRate: sampleRate, silence: rms < 0.000_02)

        for index in smoothed.indices {
            let coefficient: Float = rawBands[index] > smoothed[index] ? 0.68 : 0.14
            smoothed[index] += (rawBands[index] - smoothed[index]) * coefficient
        }

        let upperFrequency = min(maximumFrequency, sampleRate * 0.48)
        let crossoverPosition = log(crossoverFrequency / minimumFrequency)
            / log(upperFrequency / minimumFrequency) * Double(bandCount)
        let crossoverBand = min(bandCount - 1, max(0, Int(crossoverPosition)))
        let lowWeight = Float(crossoverPosition - Double(crossoverBand))

        var low = Array(smoothed[0...crossoverBand])
        low[low.count - 1] *= lowWeight
        var high = Array(smoothed[crossoverBand..<bandCount])
        high[0] *= 1 - lowWeight

        // Bass ends last so center-outward rendering places it at the center.
        return SpectrumFrame(
            levels: smoothed.reversed().map(CGFloat.init),
            lowFrequencyLevels: low.reversed().map(CGFloat.init),
            highFrequencyLevels: high.reversed().map(CGFloat.init)
        )
    }

    private func bands(sampleRate: Double, silence: Bool) -> [Float] {
        guard !silence else { return Array(repeating: 0, count: bandCount) }

        let upperFrequency = min(maximumFrequency, sampleRate * 0.48)
        let binWidth = sampleRate / Double(fftSize)
        let frequencyRatio = upperFrequency / minimumFrequency

        return (0..<bandCount).map { band in
            let lower = minimumFrequency * pow(
                frequencyRatio,
                Double(band) / Double(bandCount)
            )
            let upper = minimumFrequency * pow(
                frequencyRatio,
                Double(band + 1) / Double(bandCount)
            )
            let startBin = max(1, min(magnitudes.count - 1, Int(lower / binWidth)))
            let endBin = max(
                startBin + 1,
                min(magnitudes.count, Int(ceil(upper / binWidth)))
            )

            var peak: Float = 0
            for bin in startBin..<endBin {
                peak = max(peak, magnitudes[bin])
            }

            let amplitude = sqrt(peak) * 2 / Float(fftSize)
            let decibels = 20 * log10(max(amplitude, 0.000_000_1))
            let normalized = max(0, min(1, (decibels + 68) / 68))
            let highFrequencyCompensation = 0.9 + Float(band) / Float(bandCount) * 0.24
            return min(1, normalized * highFrequencyCompensation)
        }
    }
}

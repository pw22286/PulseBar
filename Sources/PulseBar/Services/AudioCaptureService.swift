import AudioToolbox
import Combine
import CoreGraphics
import CoreMedia
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit

final class AudioCaptureService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case capturing
        case permissionDenied
        case failed(String)

        var title: String {
            switch self {
            case .idle: "已停止"
            case .starting: "正在连接系统音频..."
            case .capturing: "正在监听系统音频"
            case .permissionDenied: "需要系统音频录制权限"
            case .failed(let message): "错误：\(message)"
            }
        }
    }

    @Published private(set) var levels = Array(repeating: CGFloat(0), count: 15)
    @Published private(set) var state = State.idle

    private let sensitivity = CGFloat(1)
    private let smoothing = CGFloat(0.55)

    private let sampleQueue = DispatchQueue(label: "com.pulsebar.audio")
    private let permissionRequestKey = "didRequestScreenCapturePermission"
    private let logger = Logger(subsystem: "com.pulsebar.app", category: "AudioCapture")
    private var stream: SCStream?
    private var lastMeterLog = Date.distantPast

    var isCapturing: Bool { state == .capturing || state == .starting }

    @MainActor
    func start() async {
        guard stream == nil else { return }

        state = .starting
        guard CGPreflightScreenCaptureAccess() else {
            logger.info("Screen capture permission is unavailable")
            state = .permissionDenied
            if !UserDefaults.standard.bool(forKey: permissionRequestKey) {
                UserDefaults.standard.set(true, forKey: permissionRequestKey)
                CGRequestScreenCaptureAccess()
            }
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else {
                throw CaptureError.noDisplay
            }

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.queueDepth = 1
            configuration.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

            self.stream = stream
            try await stream.startCapture()
            state = .capturing
            logger.info("System audio capture started")
        } catch {
            stream = nil
            state = .failed(error.localizedDescription)
            logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        levels = Array(repeating: 0, count: levels.count)
        state = .idle
    }

    private func meterLevel(from sampleBuffer: CMSampleBuffer) -> CGFloat {
        guard
            let format = CMSampleBufferGetFormatDescription(sampleBuffer),
            let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
            description.mFormatID == kAudioFormatLinearPCM
        else { return 0 }

        var requiredSize = 0
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }

        let bufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr else { return 0 }

        var sumOfSquares = 0.0
        var sampleCount = 0
        for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
            guard let data = buffer.mData else { continue }
            let byteCount = Int(buffer.mDataByteSize)

            if description.mBitsPerChannel == 32,
               description.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                let samples = data.assumingMemoryBound(to: Float.self)
                let count = byteCount / MemoryLayout<Float>.size
                for index in 0..<count {
                    let sample = Double(samples[index])
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            } else if description.mBitsPerChannel == 16 {
                let samples = data.assumingMemoryBound(to: Int16.self)
                let count = byteCount / MemoryLayout<Int16>.size
                for index in 0..<count {
                    let sample = Double(samples[index]) / Double(Int16.max)
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            } else if description.mBitsPerChannel == 32 {
                let samples = data.assumingMemoryBound(to: Int32.self)
                let count = byteCount / MemoryLayout<Int32>.size
                for index in 0..<count {
                    let sample = Double(samples[index]) / Double(Int32.max)
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            }
        }

        guard sampleCount > 0 else { return 0 }
        let rms = sqrt(sumOfSquares / Double(sampleCount))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return CGFloat(min(1, max(0, (decibels + 50) / 50)))
    }

    @MainActor
    private func append(_ level: CGFloat) {
        let previous = levels.last ?? 0
        let adjusted = min(1, level * sensitivity)
        let decay = 0.3 + smoothing * 0.65
        let smoothed = max(adjusted, previous * decay)
        levels.removeFirst()
        levels.append(smoothed)
    }
}

extension AudioCaptureService: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        let level = meterLevel(from: sampleBuffer)
        if Date().timeIntervalSince(lastMeterLog) >= 10 {
            logger.debug("Audio level: \(level, privacy: .public)")
            lastMeterLog = Date()
        }
        Task { @MainActor [weak self] in
            self?.append(level)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.stream = nil
            self?.state = .failed(error.localizedDescription)
            self?.logger.error("Capture stopped: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private enum CaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? { "未找到可捕获的显示器" }
}

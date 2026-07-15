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

    @Published private(set) var levels = Array(repeating: CGFloat(0), count: 32)
    @Published private(set) var state = State.idle

    private let sampleQueue = DispatchQueue(label: "com.pulsebar.audio")
    private let analyzer = SpectrumAnalyzer(bandCount: 32)
    private let permissionRequestKey = "didRequestScreenCapturePermission.stableIdentityV1"
    private let logger = Logger(subsystem: "com.pulsebar.app", category: "AudioCapture")
    private var stream: SCStream?
    private var lastMeterLog = Date.distantPast
    private var lastPublishTime = Date.distantPast

    var isCapturing: Bool { state == .capturing || state == .starting }

    @MainActor
    func start(requestPermission: Bool = false) async {
        guard stream == nil else { return }

        state = .starting
        guard CGPreflightScreenCaptureAccess() else {
            logger.info("Screen capture permission is unavailable")
            state = .permissionDenied
            let didRequest = UserDefaults.standard.bool(forKey: permissionRequestKey)
            if requestPermission || !didRequest {
                UserDefaults.standard.set(true, forKey: permissionRequestKey)
                if CGRequestScreenCaptureAccess() {
                    UserDefaults.standard.set(false, forKey: permissionRequestKey)
                    await start()
                }
            }
            return
        }
        UserDefaults.standard.set(false, forKey: permissionRequestKey)

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
        analyzer.reset()
        levels = Array(repeating: 0, count: levels.count)
        state = .idle
    }

    private func audioSamples(
        from sampleBuffer: CMSampleBuffer
    ) -> (samples: [Float], sampleRate: Double)? {
        guard
            let format = CMSampleBufferGetFormatDescription(sampleBuffer),
            let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
            description.mFormatID == kAudioFormatLinearPCM
        else { return nil }

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
        ) == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let decoded = buffers.map { decodedSamples(from: $0, format: description) }
            .filter { !$0.isEmpty }
        guard !decoded.isEmpty else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let channelCount = max(1, Int(description.mChannelsPerFrame))
        let isNonInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        var mono = Array(repeating: Float(0), count: frameCount)

        if isNonInterleaved || decoded.count > 1 {
            for channel in decoded {
                for frame in 0..<min(frameCount, channel.count) {
                    mono[frame] += channel[frame] / Float(decoded.count)
                }
            }
        } else {
            let interleaved = decoded[0]
            for frame in 0..<frameCount {
                let offset = frame * channelCount
                guard offset + channelCount <= interleaved.count else { break }
                for channel in 0..<channelCount {
                    mono[frame] += interleaved[offset + channel] / Float(channelCount)
                }
            }
        }

        return (mono, description.mSampleRate)
    }

    private func decodedSamples(
        from buffer: AudioBuffer,
        format: AudioStreamBasicDescription
    ) -> [Float] {
        guard let data = buffer.mData else { return [] }
        let byteCount = Int(buffer.mDataByteSize)

        if format.mBitsPerChannel == 32,
           format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let count = byteCount / MemoryLayout<Float>.size
            let pointer = data.assumingMemoryBound(to: Float.self)
            return (0..<count).map { pointer[$0].isFinite ? pointer[$0] : 0 }
        }
        if format.mBitsPerChannel == 16 {
            let count = byteCount / MemoryLayout<Int16>.size
            let pointer = data.assumingMemoryBound(to: Int16.self)
            return (0..<count).map { Float(pointer[$0]) / Float(Int16.max) }
        }
        if format.mBitsPerChannel == 32 {
            let count = byteCount / MemoryLayout<Int32>.size
            let pointer = data.assumingMemoryBound(to: Int32.self)
            return (0..<count).map { Float(pointer[$0]) / Float(Int32.max) }
        }
        return []
    }
}

extension AudioCaptureService: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        guard let audio = audioSamples(from: sampleBuffer) else { return }
        guard let spectrum = analyzer.process(
            samples: audio.samples,
            sampleRate: audio.sampleRate
        ) else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPublishTime) >= 1.0 / 30.0 else { return }
        lastPublishTime = now

        if Date().timeIntervalSince(lastMeterLog) >= 10 {
            logger.debug("Spectrum peak: \(spectrum.max() ?? 0, privacy: .public)")
            lastMeterLog = Date()
        }
        Task { @MainActor [weak self] in
            self?.levels = spectrum
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

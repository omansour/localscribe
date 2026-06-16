import AVFoundation

/// Captures the default microphone input to a WAV file via `AVAudioEngine`.
///
/// We write at the input node's native format (sample rate + channel count) and
/// let ffmpeg downmix/resample to mono 16 kHz during the final mix. This avoids
/// fragile real-time format conversion.
final class MicRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    /// Requests microphone permission. Returns whether access was granted.
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func start(to url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // `format.settings` yields a settings dict compatible with the tap buffers,
        // guaranteeing `AVAudioFile.write(from:)` accepts them.
        file = try AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.file?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
    }
}

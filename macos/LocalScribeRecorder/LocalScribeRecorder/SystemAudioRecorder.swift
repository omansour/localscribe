import AVFoundation
import ScreenCaptureKit

/// Captures system audio output (everything coming out of the speakers, minus
/// this app's own audio) to a WAV file via ScreenCaptureKit.
///
/// Audio capture through SCStream requires the **Screen Recording** TCC grant,
/// even though we discard the video. We attach a tiny (2×2) video config because
/// `SCStream` still expects one.
final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var file: AVAudioFile?
    private var destURL: URL?
    private let sampleQueue = DispatchQueue(label: "localscribe.sck.audio")

    /// Whether the Screen Recording permission has been granted (no prompt).
    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the Screen Recording permission prompt. Returns the (possibly
    /// stale) current status; the user may need to re-launch after granting.
    @discardableResult
    static func requestPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    func start(to url: URL) async throws {
        destURL = url
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "LocalScribe", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No display available for system audio capture.",
            ])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Minimal video config — required even though we only consume audio.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        file = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let formatDesc = sampleBuffer.formatDescription,
              let asbd = formatDesc.audioStreamBasicDescription else { return }

        if file == nil, let url = destURL {
            var streamDesc = asbd
            if let format = AVAudioFormat(streamDescription: &streamDesc) {
                file = try? AVAudioFile(forWriting: url, settings: format.settings)
            }
        }
        guard let file else { return }

        var streamDesc = asbd
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else { return }

        try? sampleBuffer.withAudioBufferList { abl, _ in
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: abl.unsafePointer,
                                             deallocator: nil) else { return }
            try? file.write(from: pcm)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("LocalScribe: system audio stream stopped: \(error.localizedDescription)")
    }
}

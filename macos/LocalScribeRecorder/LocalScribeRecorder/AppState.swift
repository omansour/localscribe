import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case mixing
        case ready          // recording mixed, awaiting transcribe
        case transcribing
        case done
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var lastRecording: URL?
    @Published var lastTranscript: URL?
    @Published var log: String = ""

    @Published var micAuthorized = MicRecorder.isAuthorized
    @Published var systemAuthorized = SystemAudioRecorder.isAuthorized

    // Transcribe options surfaced in the UI.
    @Published var language: String = ""      // "" == auto (Parakeet)
    @Published var speakers: Int = -1         // -1 == auto detection

    private let settings = Settings.shared
    private let mic = MicRecorder()
    private let system = SystemAudioRecorder()

    private var micTemp: URL?
    private var systemTemp: URL?
    private var startDate: Date?
    private var timer: AnyCancellable?

    var isBusy: Bool {
        switch phase {
        case .recording, .mixing, .transcribing: return true
        default: return false
        }
    }

    // MARK: - Permissions

    func refreshPermissions() {
        micAuthorized = MicRecorder.isAuthorized
        systemAuthorized = SystemAudioRecorder.isAuthorized
    }

    func requestMicPermission() {
        Task {
            _ = await MicRecorder.requestPermission()
            refreshPermissions()
        }
    }

    func requestSystemPermission() {
        SystemAudioRecorder.requestPermission()
        // The grant only takes effect on next launch; nudge the user there.
        refreshPermissions()
    }

    // MARK: - Recording

    func startRecording() {
        guard phase == .idle || phase == .done else { return }
        log = ""
        lastTranscript = nil

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("localscribe-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            phase = .error("Could not create temp dir: \(error.localizedDescription)")
            return
        }
        let micURL = tmpDir.appendingPathComponent("mic.wav")
        let sysURL = tmpDir.appendingPathComponent("sys.wav")
        micTemp = micURL
        systemTemp = sysURL

        Task {
            do {
                try mic.start(to: micURL)
            } catch {
                phase = .error("Mic capture failed: \(error.localizedDescription)")
                return
            }
            // System audio is best-effort: if it fails (e.g. no permission), keep
            // recording the mic alone rather than aborting the session.
            do {
                try await system.start(to: sysURL)
            } catch {
                appendLog("⚠️ System audio capture unavailable: \(error.localizedDescription)\n")
            }
            startDate = Date()
            elapsed = 0
            timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
            phase = .recording
        }
    }

    func stopRecording() {
        guard phase == .recording else { return }
        timer?.cancel()
        timer = nil
        phase = .mixing

        Task {
            mic.stop()
            await system.stop()

            guard let micURL = micTemp, let sysURL = systemTemp else {
                phase = .error("Internal error: missing temp files.")
                return
            }

            let stamp = Self.timestamp()
            let outURL = settings.audioDirURL.appendingPathComponent("rec_\(stamp).wav")
            do {
                try FileManager.default.createDirectory(
                    at: settings.audioDirURL, withIntermediateDirectories: true)
                try AudioMixer.mix(mic: micURL, system: sysURL, to: outURL,
                                   ffmpegPath: settings.ffmpegPath)
            } catch {
                phase = .error("Mixing failed: \(error.localizedDescription)")
                return
            }
            // Clean up temp dir.
            try? FileManager.default.removeItem(at: micURL.deletingLastPathComponent())

            lastRecording = outURL
            appendLog("✅ Recording saved: \(outURL.path)\n")
            phase = .ready
        }
    }

    // MARK: - Transcription

    func transcribe() {
        guard !isBusy, let recording = lastRecording else { return }
        phase = .transcribing
        log = ""
        let opts = (speakers: speakers, language: language)
        Task {
            let result = await Transcriber.run(
                wav: recording, speakers: opts.speakers,
                language: opts.language.isEmpty ? nil : opts.language,
                settings: settings,
                onLog: { [weak self] chunk in
                    Task { @MainActor in self?.appendLog(chunk) }
                })
            if result.exitCode == 0, let md = result.outputMarkdown {
                lastTranscript = md
                appendLog("\n✅ Transcript: \(md.path)\n")
                NSWorkspace.shared.open(md)
                phase = .done
            } else {
                phase = .error("transcribe exited with code \(result.exitCode).")
            }
        }
    }

    // MARK: - Helpers

    func openOutputFolder() {
        try? FileManager.default.createDirectory(
            at: settings.outputDirURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(settings.outputDirURL)
    }

    func revealRecording() {
        guard let rec = lastRecording else { return }
        NSWorkspace.shared.activateFileViewerSelecting([rec])
    }

    private func appendLog(_ s: String) {
        log += s
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

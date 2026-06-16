import Foundation

/// Mixes the mic and system temp WAVs into a single mono 16 kHz WAV using ffmpeg.
///
/// Output format (mono / 16 kHz / s16) matches what `make record` produces, so it
/// is 100% compatible with the localscribe `transcribe` pipeline.
enum AudioMixer {
    struct Error: Swift.Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Combines `mic` and `system` into `output`. If one source is missing or
    /// empty (e.g. nothing played through the speakers), the other is used alone.
    static func mix(mic: URL, system: URL, to output: URL, ffmpegPath: String) throws {
        let fm = FileManager.default
        let micOK = isNonEmpty(mic, fm: fm)
        let sysOK = isNonEmpty(system, fm: fm)

        guard micOK || sysOK else {
            throw Error(message: "No audio was captured (mic and system are both empty).")
        }

        var args: [String] = ["-y", "-hide_banner"]
        if micOK && sysOK {
            args += ["-i", mic.path, "-i", system.path,
                     "-filter_complex",
                     "[0:a][1:a]amix=inputs=2:duration=longest:normalize=0"]
        } else {
            args += ["-i", (micOK ? mic : system).path]
        }
        args += ["-ac", "1", "-ar", "16000", "-sample_fmt", "s16", output.path]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpegPath)
        proc.arguments = args
        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = Pipe()

        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "unknown ffmpeg error"
            throw Error(message: "ffmpeg failed (exit \(proc.terminationStatus)):\n\(msg)")
        }
    }

    private static func isNonEmpty(_ url: URL, fm: FileManager) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return false }
        // A bare WAV header is ~44 bytes; require more than that to count as real audio.
        return size > 1024
    }
}

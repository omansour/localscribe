import Foundation

/// Thread-safe string accumulator: stdout/stderr arrive on a background queue
/// while the termination handler reads the result on another.
private final class LogAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        buffer += s
    }

    var value: String {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}

/// Runs the localscribe `transcribe` pipeline on a WAV file by shelling out to
/// `uv run --no-sync python -m localscribe transcribe ...`.
enum Transcriber {
    struct Result {
        let exitCode: Int32
        let log: String
        let outputMarkdown: URL?
    }

    /// - Parameters:
    ///   - wav: the mixed recording to transcribe.
    ///   - speakers: known speaker count, or -1 for auto detection.
    ///   - language: forced language code (e.g. "fr"), or nil for auto (Parakeet).
    ///   - onLog: streamed stdout/stderr lines, delivered on the main actor.
    static func run(wav: URL, speakers: Int, language: String?,
                    settings: Settings,
                    onLog: @escaping @Sendable (String) -> Void) async -> Result {
        var args = ["run", "--no-sync", "python", "-m", "localscribe", "transcribe",
                    wav.path, "--speakers", String(speakers)]
        if let language, !language.isEmpty {
            args += ["--language", language]
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: settings.uvPath)
        proc.arguments = args
        proc.currentDirectoryURL = settings.repoURL

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = settings.subprocessPath
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        let expectedOutput = settings.outputDirURL
            .appendingPathComponent(wav.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("md")

        let accumulator = LogAccumulator()
        return await withCheckedContinuation { continuation in
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                accumulator.append(chunk)
                onLog(chunk)
            }

            proc.terminationHandler = { p in
                handle.readabilityHandler = nil
                // Drain anything left in the pipe.
                let rest = handle.readDataToEndOfFile()
                if !rest.isEmpty, let chunk = String(data: rest, encoding: .utf8) {
                    accumulator.append(chunk)
                    onLog(chunk)
                }
                let md = FileManager.default.fileExists(atPath: expectedOutput.path)
                    ? expectedOutput : nil
                continuation.resume(returning: Result(
                    exitCode: p.terminationStatus, log: accumulator.value, outputMarkdown: md))
            }

            do {
                try proc.run()
            } catch {
                handle.readabilityHandler = nil
                continuation.resume(returning: Result(
                    exitCode: -1,
                    log: "Failed to launch uv at \(settings.uvPath): \(error.localizedDescription)",
                    outputMarkdown: nil))
            }
        }
    }
}

import Foundation

/// User-configurable paths, persisted in `UserDefaults`.
///
/// A GUI app launched outside a terminal does NOT inherit the shell `PATH`, so
/// we cannot rely on `uv`/`ffmpeg` being discoverable by name. We store absolute
/// paths and an explicit `PATH` to inject into the transcribe subprocess.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Keys {
        static let repoPath = "repoPath"
        static let uvPath = "uvPath"
        static let extraPath = "extraPath"
    }

    /// Root of the localscribe repo. Recordings land in `<repo>/audio`, transcripts
    /// in `<repo>/output` — matching the CLI's relative-path conventions.
    @Published var repoPath: String {
        didSet { UserDefaults.standard.set(repoPath, forKey: Keys.repoPath) }
    }

    /// Absolute path to the `uv` executable.
    @Published var uvPath: String {
        didSet { UserDefaults.standard.set(uvPath, forKey: Keys.uvPath) }
    }

    /// Directories prepended to the transcribe subprocess `PATH` so the Python
    /// pipeline can find `ffmpeg` (it uses `shutil.which("ffmpeg")`).
    @Published var extraPath: String {
        didSet { UserDefaults.standard.set(extraPath, forKey: Keys.extraPath) }
    }

    private init() {
        let d = UserDefaults.standard
        repoPath = d.string(forKey: Keys.repoPath)
            ?? "/Users/oliviermansour/Documents/myWorkspace/voice_rec"
        uvPath = d.string(forKey: Keys.uvPath) ?? "/opt/homebrew/bin/uv"
        extraPath = d.string(forKey: Keys.extraPath) ?? "/opt/homebrew/bin"
    }

    var repoURL: URL { URL(fileURLWithPath: repoPath, isDirectory: true) }
    var audioDirURL: URL { repoURL.appendingPathComponent("audio", isDirectory: true) }
    var outputDirURL: URL { repoURL.appendingPathComponent("output", isDirectory: true) }

    /// `PATH` value for spawned subprocesses (ffmpeg + uv resolution).
    var subprocessPath: String { "\(extraPath):/usr/bin:/bin:/usr/sbin:/sbin" }

    /// Absolute path to `ffmpeg`, derived from the first dir in `extraPath`.
    var ffmpegPath: String {
        let firstDir = extraPath.split(separator: ":").first.map(String.init) ?? "/opt/homebrew/bin"
        return "\(firstDir)/ffmpeg"
    }
}

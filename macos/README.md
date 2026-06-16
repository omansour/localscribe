# LocalScribe Recorder (macOS menu bar app)

A small native macOS menu bar app that records your **microphone** and the
**system audio output** (the other people on a call) at the same time, mixes
them into a single mono 16 kHz WAV in the repo's `audio/` folder, and lets you
launch the existing `localscribe transcribe` pipeline on it with one click.

It is purely additive — it does **not** modify any Python code. It just produces
a WAV that is byte-for-byte compatible with what `make record` makes, then shells
out to `uv run --no-sync python -m localscribe transcribe`.

## Requirements

- **Full Xcode** (not just Command Line Tools) to build the `.app`.
- macOS 14+ (uses `MenuBarExtra`, ScreenCaptureKit audio capture).
- `uv` and `ffmpeg` installed (default assumed at `/opt/homebrew/bin`).

## Build & run

From the repo root, via the Makefile:

```bash
make app-run        # build (Release) and launch
make app-install    # build and install into /Applications, then launch
make app-build      # build only
```

Or open it in Xcode and Run (⌘R):

```bash
open macos/LocalScribeRecorder/LocalScribeRecorder.xcodeproj
```

For TCC permissions to stick across rebuilds, you may want to set your own
Development Team under Signing & Capabilities (the project ships with ad-hoc
signing `-`).

> **Note:** the Makefile builds into `~/Library/Caches/LocalScribeRecorder-build`,
> not inside the repo. This project lives under `~/Documents`, which iCloud Drive
> syncs and stamps with extended attributes that make `codesign` fail
> (`resource fork, Finder information, or similar detritus not allowed`).
> Building outside the synced folder avoids that.

## Permissions

On first run the app needs two grants:

1. **Microphone** — prompted automatically (`NSMicrophoneUsageDescription`).
2. **Screen Recording** — required by ScreenCaptureKit even for audio-only
   capture. The app triggers the prompt; if you deny it, system audio is
   skipped and only the mic is recorded. Grant it in
   *System Settings → Privacy & Security → Screen Recording*, then relaunch.

## How it works

1. **Mic** → `AVAudioEngine` tap → temp `mic.wav`.
2. **System audio** → ScreenCaptureKit `SCStream` (`capturesAudio`,
   `excludesCurrentProcessAudio`) → temp `sys.wav`.
3. On **Stop**, ffmpeg mixes both:
   `amix=inputs=2:duration=longest:normalize=0 -ac 1 -ar 16000 -sample_fmt s16`
   → `audio/rec_<timestamp>.wav`.
4. **Transcribe** runs `uv run --no-sync python -m localscribe transcribe
   audio/rec_<ts>.wav --speakers <N> [--language <code>]` with `cwd` = repo root
   and an explicit `PATH` (so the Python subprocess finds `ffmpeg`). The
   resulting `output/rec_<ts>.md` opens automatically.

## Configuration

Paths are stored in `UserDefaults` (`repoPath`, `uvPath`, `extraPath`) with
sensible defaults in `Settings.swift`. Edit there if your repo or Homebrew
location differs.

## Known limitation

The mic and system streams have independent clocks; `amix` aligns them only at
the start, so very long recordings may drift slightly. A future version could
mix through a single `AVAudioEngine` graph or resample to a common clock.

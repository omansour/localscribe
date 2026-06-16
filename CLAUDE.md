# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`localscribe` is a **fully local, offline** CLI that takes an audio (or video) file and produces a
Markdown transcript with diarization ("who spoke when") and recognition of enrolled voices
("that turn was Me"). Targets macOS Apple Silicon; ASR runs on the Apple GPU via MLX,
diarization/embeddings run on CPU via sherpa-onnx. No cloud, no NVIDIA GPU, no Hugging Face token.

## Commands

Everything is driven through the Makefile (`make help` lists targets). The CLI itself is
`uv run --no-sync python -m localscribe <command>`.

```bash
make setup                                              # uv sync + download diarization/voiceprint models
make enroll NAME="Me" FILES="enroll/a.wav enroll/b.wav" # store a voiceprint
make list                                               # list enrolled voiceprints
make transcribe FILE=audio/x.m4a [SPEAKERS=N] [LANG=fr] # main entry point
make record OUT=audio/x.wav [DEVICE=:3]                 # capture mic to 16 kHz mono WAV (press q, not Ctrl+C)
make devices                                            # list avfoundation audio inputs
```

There is **no test suite, linter, or formatter** configured. The only way to exercise changes is
to run `make transcribe` on a sample file.

`LANG` is only honored when passed explicitly on the make command line (`make transcribe ... LANG=fr`);
a `LANG` inherited from the shell environment (the locale) is deliberately ignored so it never
accidentally switches the ASR backend (see the `ifeq ($(origin LANG),command line)` guard in the Makefile).

## Architecture

The pipeline (`pipeline.py::process_file`) is a linear 5-stage flow; each stage lives in its own module:

1. **`audio.py`** — decode any ffmpeg-readable input to mono 16 kHz float32 via a subprocess (no decode libs).
2. **`speakers.py`** — diarize into `DiarSegment(start, end, speaker_id)` using sherpa-onnx (pyannote
   segmentation + TitaNet embeddings + fast clustering), then identify: concatenate each anonymous
   speaker's segments, embed, and cosine-match against enrolled voiceprints. Returns `{speaker_id: name}`.
3. **`enroll.py`** — voiceprint storage. Enrolled embeddings live in `personas/voiceprints.npz`
   (local, gitignored); enrollment averages embeddings across the provided files.
4. **ASR** — two interchangeable backends producing the same `AsrSentence(text, start, end)`:
   - **`asr.py`** (Parakeet, default): multilingual auto-detection. Always transcribes in overlapping
     30s/15s chunks — this is **load-bearing**, not just for memory: single-pass TDT greedy decoding can
     collapse a whole transcript to a few words on some inputs; chunking forces multiple passes that merge correctly.
   - **`whisper_asr.py`** (Whisper large-v3): used only when `--language` is set, because Whisper takes a
     forced language token and avoids mid-sentence code-switching.
   The backend is chosen in `pipeline.py` purely by whether `language` is truthy.
5. **`report.py`** — merge ASR sentences with diar segments by **max time overlap**, group consecutive
   same-speaker turns, render Markdown to `output/<stem>.md`.

`__main__.py` is the argparse CLI (`enroll` / `list` / `transcribe`). The shared data contract between
stages is the three dataclasses: `DiarSegment`, `AsrSentence`, `Turn`.

## Models

Two kinds, fetched differently:
- **Diarization + voiceprint** ONNX models (~45 MB) → `models/` via `models/download_models.sh` (run by `make models`).
  Paths are hardcoded in `speakers.py` (`SEGMENTATION_MODEL`, `EMBEDDING_MODEL`); both are checked for
  existence with a "run download_models.sh" hint before use.
- **ASR** models (Parakeet ~2.3 GB, Whisper ~3 GB) → auto-downloaded by MLX on first transcription into the
  shared Hugging Face cache (`~/.cache/huggingface/hub/`, overridable via `HF_HOME`). Not in `models/`.

## macOS menu bar recorder app (`macos/`)

`macos/LocalScribeRecorder/` is a native Swift menu bar app (greenfield Xcode project) that records
the **microphone** and **system audio output** simultaneously, mixes them to a single mono 16 kHz WAV
in `audio/`, and triggers `transcribe`. It is **purely additive** — it does not modify any Python code,
it just produces a WAV identical to `make record`'s output and shells out to the CLI.

- **Build:** requires **full Xcode** (not just Command Line Tools), macOS 14+. CLI build/verify:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project
  macos/LocalScribeRecorder/LocalScribeRecorder.xcodeproj -scheme LocalScribeRecorder build`.
  With only Command Line Tools, you can still type-check the sources: `swiftc -sdk $(xcrun
  --show-sdk-path) -target arm64-apple-macos14.0 -typecheck macos/.../LocalScribeRecorder/*.swift`.
- **Capture:** mic via `AVAudioEngine` (`MicRecorder.swift`); system audio via ScreenCaptureKit
  `SCStream` (`SystemAudioRecorder.swift`) — needs the **Screen Recording** TCC grant even for
  audio-only, and that grant only takes effect on next launch.
- **Mix:** ffmpeg `amix=inputs=2:duration=longest:normalize=0 -ac 1 -ar 16000 -sample_fmt s16`
  (`AudioMixer.swift`), falling back to the single available source if one is empty.
- **Transcribe:** `Transcriber.swift` runs `uv run --no-sync python -m localscribe transcribe …`.
  **Load-bearing:** a GUI app does NOT inherit the shell `PATH`, so it uses absolute `uv`/`ffmpeg`
  paths and injects an explicit `PATH` (default `/opt/homebrew/bin`) into the subprocess env — without
  it the Python pipeline fails on `shutil.which("ffmpeg")`. Paths are configurable in `Settings.swift`
  (persisted in `UserDefaults`); `cwd` is the repo root so `output/<stem>.md` resolves as in the CLI.
- **Known limitation:** mic and system streams have independent clocks; `amix` aligns only at the
  start, so very long recordings may drift. Documented in `macos/README.md`.

## Packaging gotcha

PyPI sherpa-onnx wheels are broken on macOS arm64 (missing onnxruntime dylib). `pyproject.toml` pins
`sherpa-onnx` and `sherpa-onnx-core` to the official k2-fsa wheel index. Keep that index config when
touching dependencies, or imports break at runtime.

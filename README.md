# voice_rec: Transcription + diarization + your-voice recognition

**Local** audio transcription. Tested on Apple Silicon (M1 and M3), featuring:

- **Multilingual transcription** (fr + en) via NVIDIA's **Parakeet v3**, accelerated by the Apple GPU (MLX).
- **Optional language forcing** via OpenAI's **Whisper large-v3** (also MLX): pass a language to avoid code-switching.
- **Diarization** ("who spoke when") via **sherpa-onnx** (CPU).
- **Your-voice recognition**: enroll your voiceprint once, then the system labels your speech turns.
- Readable **Markdown output**, with timestamps.

Everything runs offline. No NVIDIA GPU, no cloud, no Hugging Face token required.

## Makefile targets

| Target | Description |
|--------|-------------|
| `make help` | Show available targets |
| `make install` | Install Python dependencies (`uv sync`) |
| `make models` | Download diarization / voiceprint models |
| `make setup` | Full setup: install deps + download models |
| `make enroll` | Enroll a voice: `NAME="Me" FILES="enroll/a.wav enroll/b.wav"` |
| `make list` | List enrolled voiceprints |
| `make devices` | List available audio input devices (for `DEVICE=...`) |
| `make record` | Record from mic: `[OUT=audio/x.wav] [DEVICE=:3]` (press `q` to stop) |
| `make transcribe` | Transcribe a file: `FILE=audio/x.m4a [SPEAKERS=N] [LANG=fr]` |
| `make clean` | Remove generated transcriptions and audio files |
| `make clean-all` | Remove venv, downloaded models and voiceprints (full reset) |

## Supported input formats

Both the diarization and the transcription paths decode audio through **ffmpeg**,
so any format ffmpeg can read works: **wav, mp3, m4a, flac, ogg, ...** as well as
**video files** (e.g. **mp4, mov, mkv**) — the audio track is extracted automatically.

## Requirements

- macOS Apple Silicon (M1/M2/M3/M4)
- `ffmpeg`: `brew install ffmpeg`
- `uv` (Python package manager)

## Installation

```bash
make setup
```

This runs `uv sync` (Python deps) and `models/download_models.sh` (diarization/voiceprint models, ~45 MB).

ASR models are downloaded automatically on the first transcription:
- **Parakeet** (~2.3 GB) — used by default (multilingual auto-detection).
- **Whisper large-v3** (~3 GB) — used when you pass `LANG=fr` (or any language).

Both are stored in the standard Hugging Face cache (`~/.cache/huggingface/hub/`),
shared across projects. The first run will be slow (download), subsequent runs
are instant. You can change the cache location with the `HF_HOME` environment variable.

You can also run the steps separately:

```bash
make install   # uv sync
make models    # ./models/download_models.sh
```

## Usage

All commands are available through the Makefile (`make help` lists them).

### 1. Enroll your voice (once)

Put 1 to 3 clips where you speak alone, in a quiet setting (10-30 s each) into `enroll/`, then:

```bash
make enroll NAME="Me" FILES="enroll/me_1.wav enroll/me_2.wav"
```

You can record those clips straight from your mic (press `q` to stop, not `Ctrl+C`):

```bash
make record OUT=enroll/me_1.wav
```

Check known voiceprints:

```bash
make list
```

### 2. Transcribe a file

```bash
make transcribe FILE=audio/meeting.m4a
```

The transcription `output/meeting.md` looks like:

```markdown
# Transcription — meeting.m4a

**Detected speakers:** Me, Speaker 2

---

**Me** _[00:00 → 00:12]_

Hello everyone, let's start the meeting...

**Speaker 2** _[00:12 → 00:20]_

Sure, sounds good. I prepared the numbers...
```

### Useful options

Pass the number of speakers when you know it (more reliable than auto):

```bash
make transcribe FILE=audio/meeting.m4a SPEAKERS=2
```

Force a language to avoid code-switching. By default the transcription uses
**Parakeet** with automatic language detection, which can occasionally flip a
few words to the wrong language (e.g. French → English) on ambiguous audio.
Setting `LANG` switches the ASR backend to **Whisper** (`large-v3`), which takes
the language as input and stays in it:

```bash
make transcribe FILE=audio/meeting.m4a SPEAKERS=2 LANG=fr
```

The Whisper `large-v3` model (~3 GB) is downloaded automatically on the first
run with `LANG`, into the shared Hugging Face cache. Use `LANG=fr`, `LANG=en`, etc.

For finer control, call the CLI directly:

```bash
uv run python -m voice_rec transcribe audio/meeting.m4a \
  --speakers 2 --id-threshold 0.5 --cluster-threshold 0.5

# Force French (uses the Whisper backend):
uv run python -m voice_rec transcribe audio/meeting.m4a --speakers 2 --language fr
```

- `--speakers N`: number of speakers if known (more reliable than auto).
- `--language fr`: force a language (switches to the Whisper backend). Omit for
  automatic multilingual detection (Parakeet).
- `--id-threshold 0.5`: threshold to recognize your voice (raise it if you get false matches, lower it if your voice is not recognized).
- `--cluster-threshold 0.5`: in auto mode, smaller = more speakers detected.

## Recording audio from the CLI

`make record` captures your mic straight to a 16 kHz mono WAV:

```bash
make record OUT=audio/test2.wav
```

Speak, then press **`q`** to stop. Use `q`, not `Ctrl+C`: it lets ffmpeg flush the
last buffer and finalize the WAV header, so you never lose the final second.

By default it records the system's **default input device**. To pick a specific
one, list the devices and pass its avfoundation index via `DEVICE`:

```bash
make devices                          # e.g. [3] MacBook Pro Microphone
make record OUT=audio/test2.wav DEVICE=:3
```

If the first recording comes out empty, grant your terminal microphone access in
System Settings → Privacy & Security → Microphone.

## Project structure

| Item | Role |
|------|------|
| `personas/` | Stored voiceprints (`voiceprints.npz`, not versioned) |
| `voice_rec/audio.py` | Audio decoding to 16 kHz mono via ffmpeg |
| `voice_rec/speakers.py` | Diarization + voiceprints + identification (sherpa-onnx) |
| `voice_rec/asr.py` | Parakeet transcription (MLX), automatic language |
| `voice_rec/whisper_asr.py` | Whisper transcription (MLX), forced language |
| `voice_rec/report.py` | Merge + Markdown rendering |
| `voice_rec/enroll.py` | Voiceprint enrollment |
| `voice_rec/pipeline.py` | End-to-end orchestration |
| `voice_rec/__main__.py` | CLI |
| `Makefile` | Common commands |



## Privacy & consent

Before enrolling someone's voice, make sure you have their **explicit consent**.
A voiceprint is biometric data — recording, storing, or processing a person's
voice without their knowledge may violate privacy regulations (GDPR, etc.).
Only enroll people who have agreed to it, and delete their data upon request.

## Notes

- Diarization works best when speakers do not talk over each other.
- If a known voice is not recognized, re-enroll with longer/cleaner clips, or adjust `--id-threshold`.
- Voiceprints are stored in `personas/voiceprints.npz` (local, not versioned).
- **Packaging note:** sherpa-onnx wheels on PyPI are broken on macOS arm64 (missing onnxruntime dylib). `pyproject.toml` is configured to install sherpa-onnx from the official k2-fsa wheel index instead. This is transparent in normal use.

## License

This project is licensed under the [MIT License](LICENSE).

"""Mono 16 kHz audio loading via ffmpeg.

sherpa-onnx (diarization + embeddings) expects mono 16 kHz float32 audio.
We go through ffmpeg so we can accept any format (wav, mp3, m4a, ...)
without depending on extra decoding libraries.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np

TARGET_SAMPLE_RATE = 16000

# Volume normalization applied before diarization and ASR. Quiet recordings
# (e.g. faint voices well below the peak) are otherwise missed by the ASR
# greedy decoder. The chain is speech-tuned and intentionally aggressive — we
# only care about transcribability, not audio fidelity:
#   highpass   : drop sub-80 Hz rumble that would skew the loudness target
#   speechnorm : raise quiet speech half-cycles toward full scale
#   loudnorm   : settle the overall perceived level (EBU R128) with a -1.5 dB
#                true-peak ceiling so the boost never clips
ASR_BOOST_FILTER = (
    "highpass=f=80,"
    "speechnorm=e=12.5:r=0.0001:l=1,"
    "loudnorm=I=-16:TP=-1.5:LRA=11"
)


def _ensure_ffmpeg() -> None:
    if shutil.which("ffmpeg") is None:
        raise RuntimeError(
            "ffmpeg not found. Install it with:  brew install ffmpeg"
        )


def load_audio_16k_mono(path: str | Path) -> np.ndarray:
    """Decode an audio file to mono 16 kHz, returned as float32 in [-1, 1]."""
    _ensure_ffmpeg()
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"Audio file not found: {path}")

    cmd = [
        "ffmpeg",
        "-nostdin",
        "-threads", "0",
        "-i", str(path),
        "-f", "f32le",       # PCM float32 little-endian on stdout
        "-acodec", "pcm_f32le",
        "-ac", "1",          # mono
        "-ar", str(TARGET_SAMPLE_RATE),
        "-",
    ]
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"ffmpeg failed to decode {path}:\n"
            + proc.stderr.decode("utf-8", errors="replace")
        )

    audio = np.frombuffer(proc.stdout, dtype=np.float32)
    return np.ascontiguousarray(audio)


def preprocess_audio(path: str | Path) -> Path:
    """Write a normalized temporary WAV (mono 16 kHz) boosting quiet voices.

    Applies ``ASR_BOOST_FILTER`` so faint speech is reliably transcribed. The
    duration is preserved, so timestamps stay aligned with the original. The
    caller owns the returned file and must delete it.
    """
    _ensure_ffmpeg()
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"Audio file not found: {path}")

    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    out = Path(tmp.name)

    cmd = [
        "ffmpeg",
        "-nostdin",
        "-y",
        "-threads", "0",
        "-i", str(path),
        "-af", ASR_BOOST_FILTER,
        "-ac", "1",          # mono
        "-ar", str(TARGET_SAMPLE_RATE),
        "-c:a", "pcm_s16le",
        str(out),
    ]
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        out.unlink(missing_ok=True)
        raise RuntimeError(
            f"ffmpeg failed to preprocess {path}:\n"
            + proc.stderr.decode("utf-8", errors="replace")
        )
    return out

"""Mono 16 kHz audio loading via ffmpeg.

sherpa-onnx (diarization + embeddings) expects mono 16 kHz float32 audio.
We go through ffmpeg so we can accept any format (wav, mp3, m4a, ...)
without depending on extra decoding libraries.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import numpy as np

TARGET_SAMPLE_RATE = 16000


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

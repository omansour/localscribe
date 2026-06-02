"""Transcription via Parakeet (MLX) — accelerated by the Apple Silicon GPU.

We use parakeet-tdt-0.6b-v3: multilingual (fr + en + 23 other European
languages), automatic language detection, and word-level timestamps.
The model is downloaded automatically from Hugging Face on first call.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from parakeet_mlx import from_pretrained

DEFAULT_MODEL = "mlx-community/parakeet-tdt-0.6b-v3"


@dataclass
class AsrSentence:
    """A transcribed sentence with its time bounds (seconds)."""

    text: str
    start: float
    end: float


def load_asr_model(model_name: str = DEFAULT_MODEL):
    print(f"==> Loading Parakeet ASR model: {model_name}")
    return from_pretrained(model_name)


def transcribe(
    model,
    audio_path: str | Path,
    chunk_duration: float = 30.0,
    overlap_duration: float = 15.0,
) -> list[AsrSentence]:
    """Transcribe a long audio file into timestamped sentences.

    Audio is always processed in overlapping chunks. Besides keeping memory
    bounded on long files, this avoids a degenerate failure mode of the TDT
    greedy decoder, which can collapse a whole single-pass transcription down
    to a few words on some inputs. Chunking forces multiple shorter passes,
    which are then merged, and reliably recovers the full transcript.
    """
    result = model.transcribe(
        str(audio_path),
        chunk_duration=chunk_duration,
        overlap_duration=overlap_duration,
    )
    return [
        AsrSentence(text=s.text.strip(), start=float(s.start), end=float(s.end))
        for s in result.sentences
        if s.text.strip()
    ]

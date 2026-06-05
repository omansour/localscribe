"""Transcription via OpenAI Whisper (MLX) — accelerated by the Apple Silicon GPU.

This is an alternative ASR backend to ``asr.py`` (Parakeet). Whisper accepts an
explicit language, which is fed to its decoder as a language token. Unlike
Parakeet's automatic per-chunk language detection, this prevents mid-sentence
code-switching (e.g. flipping from French to English on ambiguous words), so it
is the backend used whenever the user forces a language with ``--language``.

The model is downloaded automatically from Hugging Face on first call, into the
standard cache (``~/.cache/huggingface/hub/``), shared across projects.
"""

from __future__ import annotations

from pathlib import Path

import mlx_whisper

from .asr import AsrSentence

# Full-precision large-v3 (best French accuracy; same variant as the wispr app).
DEFAULT_MODEL = "mlx-community/whisper-large-v3-mlx"


def transcribe(
    audio_path: str | Path,
    language: str,
    model_name: str = DEFAULT_MODEL,
) -> list[AsrSentence]:
    """Transcribe an audio file into timestamped sentences with a forced language.

    Args:
        audio_path: file to transcribe (any format ffmpeg-decodable by Whisper).
        language: ISO language code to force (e.g. ``"fr"``, ``"en"``).
        model_name: Hugging Face repo id of the MLX Whisper model.
    """
    print(f"==> Loading Whisper ASR model: {model_name}")
    result = mlx_whisper.transcribe(
        str(audio_path),
        path_or_hf_repo=model_name,
        language=language,
        word_timestamps=False,
    )
    return [
        AsrSentence(
            text=seg["text"].strip(),
            start=float(seg["start"]),
            end=float(seg["end"]),
        )
        for seg in result.get("segments", [])
        if seg.get("text", "").strip()
    ]

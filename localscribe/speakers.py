"""Speaker diarization and recognition via sherpa-onnx (CPU, fully local).

Three responsibilities:
  1. Extract a "voiceprint" (embedding) from one or more files.
  2. Diarize audio: "who spoke when" -> segments (start, end, speaker_id).
  3. Identify, for each anonymous detected speaker, whether it matches a known
     voiceprint (your voice) by comparing embeddings.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import sherpa_onnx

from .audio import TARGET_SAMPLE_RATE, load_audio_16k_mono

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
SEGMENTATION_MODEL = MODELS_DIR / "sherpa-onnx-pyannote-segmentation-3-0" / "model.onnx"
EMBEDDING_MODEL = MODELS_DIR / "nemo_en_titanet_small.onnx"


@dataclass
class DiarSegment:
    """A speech turn: from start to end (seconds), attributed to a speaker."""

    start: float
    end: float
    speaker: str  # e.g. "speaker_00", later replaced by a name if identified


# --------------------------------------------------------------------------- #
# Voiceprint (embedding)
# --------------------------------------------------------------------------- #
def build_embedding_extractor(num_threads: int = 2) -> sherpa_onnx.SpeakerEmbeddingExtractor:
    if not EMBEDDING_MODEL.is_file():
        raise FileNotFoundError(
            f"Embedding model missing: {EMBEDDING_MODEL}\n"
            "Run first:  ./models/download_models.sh"
        )
    config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
        model=str(EMBEDDING_MODEL),
        num_threads=num_threads,
        provider="cpu",
    )
    if not config.validate():
        raise RuntimeError(f"Invalid embedding config: {config}")
    return sherpa_onnx.SpeakerEmbeddingExtractor(config)


def embedding_from_samples(
    extractor: sherpa_onnx.SpeakerEmbeddingExtractor,
    samples: np.ndarray,
    sample_rate: int = TARGET_SAMPLE_RATE,
) -> np.ndarray:
    stream = extractor.create_stream()
    stream.accept_waveform(sample_rate=sample_rate, waveform=samples)
    stream.input_finished()
    if not extractor.is_ready(stream):
        raise RuntimeError("Embedding extractor not ready (audio too short?).")
    return np.array(extractor.compute(stream), dtype=np.float32)


def embedding_from_files(
    extractor: sherpa_onnx.SpeakerEmbeddingExtractor,
    files: list[str | Path],
) -> np.ndarray:
    """Average embedding over several files (recommended for enrollment)."""
    if not files:
        raise ValueError("No file provided for the voiceprint.")
    acc = None
    for f in files:
        samples = load_audio_16k_mono(f)
        emb = embedding_from_samples(extractor, samples)
        acc = emb if acc is None else acc + emb
    return acc / len(files)


# --------------------------------------------------------------------------- #
# Diarization
# --------------------------------------------------------------------------- #
def build_diarizer(
    num_speakers: int = -1,
    cluster_threshold: float = 0.5,
    num_threads: int = 2,
) -> sherpa_onnx.OfflineSpeakerDiarization:
    """Build the diarization pipeline.

    num_speakers: number of speakers if known, otherwise -1 (auto via clustering).
    cluster_threshold: used only when num_speakers == -1.
        smaller -> more speakers, larger -> fewer speakers.
    """
    if not SEGMENTATION_MODEL.is_file():
        raise FileNotFoundError(
            f"Segmentation model missing: {SEGMENTATION_MODEL}\n"
            "Run first:  ./models/download_models.sh"
        )
    if not EMBEDDING_MODEL.is_file():
        raise FileNotFoundError(
            f"Embedding model missing: {EMBEDDING_MODEL}\n"
            "Run first:  ./models/download_models.sh"
        )

    config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
                model=str(SEGMENTATION_MODEL)
            ),
            num_threads=num_threads,
        ),
        embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model=str(EMBEDDING_MODEL),
            num_threads=num_threads,
            provider="cpu",
        ),
        clustering=sherpa_onnx.FastClusteringConfig(
            num_clusters=num_speakers,
            threshold=cluster_threshold,
        ),
        min_duration_on=0.3,
        min_duration_off=0.5,
    )
    if not config.validate():
        raise RuntimeError(
            "Invalid diarization config. Check that the models exist."
        )
    return sherpa_onnx.OfflineSpeakerDiarization(config)


def diarize(
    diarizer: sherpa_onnx.OfflineSpeakerDiarization,
    samples: np.ndarray,
    show_progress: bool = True,
) -> list[DiarSegment]:
    def _cb(done: int, total: int) -> int:
        pct = done / total * 100 if total else 100.0
        print(f"\r  diarization: {pct:5.1f}%", end="", flush=True)
        return 0

    if show_progress:
        result = diarizer.process(samples, callback=_cb).sort_by_start_time()
        print()
    else:
        result = diarizer.process(samples).sort_by_start_time()

    return [
        DiarSegment(start=r.start, end=r.end, speaker=f"speaker_{r.speaker:02d}")
        for r in result
    ]


# --------------------------------------------------------------------------- #
# Identification: match anonymous speakers to known voiceprints
# --------------------------------------------------------------------------- #
def _cosine(a: np.ndarray, b: np.ndarray) -> float:
    denom = (np.linalg.norm(a) * np.linalg.norm(b)) + 1e-9
    return float(np.dot(a, b) / denom)


def identify_speakers(
    extractor: sherpa_onnx.SpeakerEmbeddingExtractor,
    samples: np.ndarray,
    segments: list[DiarSegment],
    known: dict[str, np.ndarray],
    threshold: float = 0.5,
    sample_rate: int = TARGET_SAMPLE_RATE,
) -> dict[str, str]:
    """Return a mapping {anonymous_speaker_id: name}.

    For each anonymous speaker we concatenate its segments, compute its
    embedding, then compare it to each known voiceprint. The best match above
    the threshold gives the name; otherwise we keep a generic "Speaker N" label.
    """
    # Group samples by anonymous speaker.
    by_speaker: dict[str, list[np.ndarray]] = {}
    for seg in segments:
        i0 = max(0, int(seg.start * sample_rate))
        i1 = min(len(samples), int(seg.end * sample_rate))
        if i1 > i0:
            by_speaker.setdefault(seg.speaker, []).append(samples[i0:i1])

    mapping: dict[str, str] = {}
    generic_index = 1
    used_names: set[str] = set()

    for speaker_id in sorted(by_speaker):
        chunk = np.concatenate(by_speaker[speaker_id])
        try:
            emb = embedding_from_samples(extractor, chunk, sample_rate)
        except RuntimeError:
            mapping[speaker_id] = f"Speaker {generic_index}"
            generic_index += 1
            continue

        best_name, best_score = None, -1.0
        for name, ref in known.items():
            score = _cosine(emb, ref)
            if score > best_score:
                best_name, best_score = name, score

        if best_name is not None and best_score >= threshold and best_name not in used_names:
            mapping[speaker_id] = best_name
            used_names.add(best_name)
        else:
            mapping[speaker_id] = f"Speaker {generic_index}"
            generic_index += 1

    return mapping

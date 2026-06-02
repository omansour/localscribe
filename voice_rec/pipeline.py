"""Full pipeline: audio -> diarization -> identification -> ASR -> Markdown."""

from __future__ import annotations

import time
from pathlib import Path

from . import asr, report, speakers, whisper_asr
from .audio import load_audio_16k_mono
from .enroll import load_voiceprints

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "output"


def process_file(
    audio_path: str | Path,
    output_dir: str | Path = DEFAULT_OUTPUT_DIR,
    num_speakers: int = -1,
    cluster_threshold: float = 0.5,
    id_threshold: float = 0.5,
    model_name: str = asr.DEFAULT_MODEL,
    language: str | None = None,
) -> Path:
    audio_path = Path(audio_path)
    t0 = time.time()

    # 1) Load audio as mono 16 kHz (for diarization/embeddings).
    print(f"==> Loading audio: {audio_path.name}")
    samples = load_audio_16k_mono(audio_path)
    duration = len(samples) / 16000
    print(f"    duration: {duration:.1f}s")

    # 2) Diarize: who spoke when.
    print("==> Diarization (who spoke when)...")
    diarizer = speakers.build_diarizer(
        num_speakers=num_speakers, cluster_threshold=cluster_threshold
    )
    segments = speakers.diarize(diarizer, samples)
    n_anon = len({s.speaker for s in segments})
    print(f"    {len(segments)} segments, {n_anon} distinct speaker(s)")

    # 3) Identify known speakers (your voice).
    known = load_voiceprints()
    if known:
        print(f"==> Identification (known voiceprints: {', '.join(sorted(known))})")
        extractor = speakers.build_embedding_extractor()
        speaker_names = speakers.identify_speakers(
            extractor, samples, segments, known, threshold=id_threshold
        )
    else:
        print("==> No known voiceprint: speakers left anonymous.")
        speaker_names = {
            speaker_id: f"Speaker {i + 1}"
            for i, speaker_id in enumerate(sorted({seg.speaker for seg in segments}))
        }
    for anon, name in sorted(speaker_names.items()):
        print(f"    {anon} -> {name}")

    # 4) Transcribe. With a forced language, use Whisper (it accepts a language
    #    token and avoids code-switching); otherwise use multilingual Parakeet.
    if language:
        print(f"==> Transcription (Whisper via MLX, language forced: {language})...")
        sentences = whisper_asr.transcribe(audio_path, language=language)
    else:
        print("==> Transcription (Parakeet via MLX, auto language)...")
        model = asr.load_asr_model(model_name)
        sentences = asr.transcribe(model, audio_path)
    print(f"    {len(sentences)} sentences transcribed")

    # 5) Merge and write the Markdown.
    print("==> Merging and generating Markdown...")
    turns = report.assign_speakers(sentences, segments, speaker_names)
    md = report.render_markdown(turns, audio_path.name, speaker_names)
    out_path = Path(output_dir) / f"{audio_path.stem}.md"
    report.write_markdown(md, out_path)

    print(f"\nDone in {time.time() - t0:.1f}s")
    print(f"   Transcription written: {out_path}")
    return out_path

"""Command-line interface.

Examples:
    # 1. Enroll your voice (10-30 s of clean samples of you speaking)
    uv run python -m localscribe enroll --name "Me" enroll/me_1.wav enroll/me_2.wav

    # 2. List known voiceprints
    uv run python -m localscribe list

    # 3. Transcribe a file (Markdown output in output/)
    uv run python -m localscribe transcribe audio/meeting.m4a

    # Specify the number of speakers if you know it (more reliable):
    uv run python -m localscribe transcribe audio/meeting.m4a --speakers 3

    # Force a language to avoid code-switching (uses the Whisper backend):
    uv run python -m localscribe transcribe audio/meeting.m4a --language fr
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import asr
from .enroll import enroll, list_enrolled
from .pipeline import DEFAULT_OUTPUT_DIR, process_file


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="localscribe",
        description="Batch transcription with speaker diarization and voice recognition (Apple Silicon).",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # enroll
    p_enroll = sub.add_parser("enroll", help="Record the voiceprint of a person.")
    p_enroll.add_argument("--name", required=True, help="Person's name (e.g. \"Me\").")
    p_enroll.add_argument("files", nargs="+", help="Audio sample files for this voice.")

    # list
    sub.add_parser("list", help="List the enrolled voiceprints.")

    # transcribe
    p_tr = sub.add_parser("transcribe", help="Transcribe an audio file to Markdown.")
    p_tr.add_argument("audio", help="Audio file to transcribe (wav, mp3, m4a, ...).")
    p_tr.add_argument(
        "--output-dir", default=str(DEFAULT_OUTPUT_DIR),
        help="Output directory for .md files (default: output/).",
    )
    p_tr.add_argument(
        "--speakers", type=int, default=-1,
        help="Number of speakers if known (default: -1 = auto detection).",
    )
    p_tr.add_argument(
        "--cluster-threshold", type=float, default=0.5,
        help="Clustering threshold when --speakers=-1 (smaller = more speakers).",
    )
    p_tr.add_argument(
        "--id-threshold", type=float, default=0.5,
        help="Similarity threshold to recognize a known voice (0-1).",
    )
    p_tr.add_argument(
        "--model", default=asr.DEFAULT_MODEL,
        help="Parakeet model to use (ignored when --language is set).",
    )
    p_tr.add_argument(
        "--language", default=None,
        help="Force a language (e.g. 'fr', 'en'). Switches the ASR backend to "
             "Whisper, which avoids code-switching. Default: auto (Parakeet).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.command == "enroll":
        enroll(args.name, args.files)
    elif args.command == "list":
        list_enrolled()
    elif args.command == "transcribe":
        audio_path = Path(args.audio)
        if not audio_path.is_file():
            print(f"ERROR: audio file not found: {audio_path}", file=sys.stderr)
            parent = audio_path.parent if str(audio_path.parent) else Path(".")
            try:
                siblings = sorted(
                    p.name for p in parent.iterdir()
                    if p.is_file() and not p.name.startswith(".")
                )
            except OSError:
                siblings = []
            if siblings:
                print(f"Available files in {parent}/:", file=sys.stderr)
                for name in siblings:
                    print(f"  - {parent / name}", file=sys.stderr)
            else:
                print(f"Directory '{parent}/' has no readable files.", file=sys.stderr)
            return 1
        process_file(
            args.audio,
            output_dir=args.output_dir,
            num_speakers=args.speakers,
            cluster_threshold=args.cluster_threshold,
            id_threshold=args.id_threshold,
            model_name=args.model,
            language=args.language,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

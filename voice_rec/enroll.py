"""Enrollment: record the voiceprint of a person (e.g. you).

Voiceprints are stored in personas/voiceprints.npz at the project root. You can
enroll several people (you, a recurring colleague, etc.).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .speakers import build_embedding_extractor, embedding_from_files

PROJECT_ROOT = Path(__file__).resolve().parent.parent
VOICEPRINTS_PATH = PROJECT_ROOT / "personas" / "voiceprints.npz"


def load_voiceprints() -> dict[str, np.ndarray]:
    if not VOICEPRINTS_PATH.is_file():
        return {}
    data = np.load(VOICEPRINTS_PATH, allow_pickle=True)
    return {key: data[key] for key in data.files}


def save_voiceprints(prints: dict[str, np.ndarray]) -> None:
    np.savez(VOICEPRINTS_PATH, **prints)


def enroll(name: str, audio_files: list[str | Path]) -> None:
    """Compute and store the voiceprint of `name` from audio samples."""
    files = [Path(f) for f in audio_files]
    missing = [str(f) for f in files if not f.is_file()]
    if missing:
        raise FileNotFoundError("Files not found: " + ", ".join(missing))

    print(f"==> Computing voiceprint for '{name}' ({len(files)} file(s))")
    extractor = build_embedding_extractor()
    embedding = embedding_from_files(extractor, files)

    prints = load_voiceprints()
    prints[name] = embedding
    save_voiceprints(prints)
    print(f"==> Voiceprint saved. Known people: {', '.join(sorted(prints))}")


def list_enrolled() -> None:
    prints = load_voiceprints()
    if not prints:
        print("No voiceprint enrolled yet. Use the 'enroll' command.")
        return
    print("Enrolled voiceprints:")
    for name in sorted(prints):
        print(f"  - {name}  (dim={prints[name].shape[0]})")

"""Merge diarization + transcription, then render Markdown.

We attribute each transcribed sentence (with its time bounds) to the speaker
whose speech turn overlaps the sentence the most, then group consecutive
sentences from the same speaker into readable blocks.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

from .asr import AsrSentence
from .speakers import DiarSegment


@dataclass
class Turn:
    speaker: str
    start: float
    end: float
    text: str


def _fmt_ts(seconds: float) -> str:
    """Format a time as HH:MM:SS (or MM:SS if < 1h)."""
    td = timedelta(seconds=max(0.0, seconds))
    total = int(td.total_seconds())
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def _overlap(a_start: float, a_end: float, b_start: float, b_end: float) -> float:
    return max(0.0, min(a_end, b_end) - max(a_start, b_start))


def assign_speakers(
    sentences: list[AsrSentence],
    segments: list[DiarSegment],
    speaker_names: dict[str, str],
) -> list[Turn]:
    """Attach each sentence to the speaker with the largest time overlap."""
    turns: list[Turn] = []
    for sent in sentences:
        best_seg, best_ov = None, 0.0
        for seg in segments:
            ov = _overlap(sent.start, sent.end, seg.start, seg.end)
            if ov > best_ov:
                best_seg, best_ov = seg, ov

        if best_seg is not None:
            label = speaker_names.get(best_seg.speaker, best_seg.speaker)
        else:
            label = "Unknown"

        turns.append(Turn(speaker=label, start=sent.start, end=sent.end, text=sent.text))
    return turns


def merge_consecutive(turns: list[Turn]) -> list[Turn]:
    """Merge consecutive sentences from the same speaker into a single block."""
    if not turns:
        return []
    merged = [Turn(turns[0].speaker, turns[0].start, turns[0].end, turns[0].text)]
    for t in turns[1:]:
        last = merged[-1]
        if t.speaker == last.speaker:
            last.end = t.end
            last.text = f"{last.text} {t.text}".strip()
        else:
            merged.append(Turn(t.speaker, t.start, t.end, t.text))
    return merged


def render_markdown(
    turns: list[Turn],
    source_name: str,
    speaker_names: dict[str, str],
) -> str:
    distinct = sorted(set(speaker_names.values()))
    lines: list[str] = []
    lines.append(f"# Transcription — {source_name}")
    lines.append("")
    lines.append(f"_Generated on {datetime.now():%Y-%m-%d %H:%M}_")
    lines.append("")
    if distinct:
        lines.append(f"**Detected speakers:** {', '.join(distinct)}")
        lines.append("")
    lines.append("---")
    lines.append("")

    for t in merge_consecutive(turns):
        lines.append(f"**{t.speaker}** _[{_fmt_ts(t.start)} → {_fmt_ts(t.end)}]_")
        lines.append("")
        lines.append(t.text)
        lines.append("")

    return "\n".join(lines)


def write_markdown(content: str, out_path: str | Path) -> Path:
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(content, encoding="utf-8")
    return out_path

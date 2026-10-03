"""Convert a legally owned Psych-style chart to jave-chart-v1.

This tool converts note timing only. It does not copy audio, images, scripts,
events, or other copyrighted content. Engine forks differ, so review the output.
"""

import argparse
import json
import re
from pathlib import Path


def slug(value: str) -> str:
    result = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return result or "imported-song"


parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path, help="Psych chart JSON you have rights to use")
parser.add_argument("output", type=Path, help="Destination Jave chart JSON")
parser.add_argument("--difficulty", default="normal")
parser.add_argument("--player-only", action="store_true", help="Discard opponent notes (not recommended)")
args = parser.parse_args()

source = json.loads(args.source.read_text(encoding="utf-8-sig"))
nested = source.get("song") if isinstance(source, dict) else None
song = nested if isinstance(nested, dict) else source
if not isinstance(song, dict) or not isinstance(song.get("notes"), list):
    raise SystemExit("Unsupported input: expected song.notes section array")

title = str(song.get("song", args.source.stem))
converted = []
for section_index, section in enumerate(song["notes"]):
    if not isinstance(section, dict):
        continue
    player_section = bool(section.get("mustHitSection", False))
    for note_index, raw in enumerate(section.get("sectionNotes", [])):
        if not isinstance(raw, list) or len(raw) < 2:
            print(f"warning: skipped section {section_index} note {note_index}")
            continue
        try:
            time_ms = float(raw[0])
            note_data = int(raw[1])
            sustain_ms = max(0.0, float(raw[2])) if len(raw) > 2 else 0.0
        except (TypeError, ValueError):
            print(f"warning: skipped malformed section {section_index} note {note_index}")
            continue
        belongs_to_player = player_section
        if note_data >= 4:
            belongs_to_player = not belongs_to_player
        if args.player_only and not belongs_to_player:
            continue
        note = {
            "timeMs": round(time_ms, 3),
            "lane": note_data % 4,
            "owner": "player" if belongs_to_player else "opponent",
        }
        if sustain_ms > 0:
            note["lengthMs"] = round(sustain_ms, 3)
        converted.append(note)

converted.sort(key=lambda note: (note["timeMs"], note["lane"]))
result = {
    "format": "jave-chart-v1",
    "song": slug(title),
    "difficulty": args.difficulty,
    "bpm": float(song.get("bpm", 120)),
    "offsetMs": 0,
    "notes": converted,
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(f"Converted {len(converted)} notes to {args.output}")
print("Psych ownership was preserved: mustHitSection selects the base side and noteData 4-7 flips it.")
print("Review sync, sustains, license, and credits before packaging.")

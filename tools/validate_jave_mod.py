"""Validate a self-contained Jave Engine mod package."""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise ValueError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def required_file(root: Path, relative: str, label: str) -> Path:
    path = root / relative
    if not path.is_file():
        raise ValueError(f"missing {label}: {relative}")
    return path


def validate_wav(path: Path) -> None:
    header = path.read_bytes()[:12]
    if len(header) != 12 or header[:4] != b"RIFF" or header[8:12] != b"WAVE":
        raise ValueError(f"not a valid RIFF/WAVE file: {path}")


def validate(root: Path) -> dict[str, int]:
    mod = load_json(required_file(root, "mod.json", "mod manifest"))
    if not mod.get("id") or not mod.get("name"):
        raise ValueError("mod.json requires non-empty id and name")

    weeks_doc = load_json(required_file(root, "data/weeks.json", "weeks file"))
    weeks = weeks_doc.get("weeks", [])
    if not isinstance(weeks, list) or not weeks:
        raise ValueError("data/weeks.json must contain at least one week")

    song_manifests = sorted(root.glob("songs/*/song.json"))
    if not song_manifests:
        raise ValueError("no songs/*/song.json manifests found")

    song_ids: set[str] = set()
    totals = {"songs": 0, "weeks": len(weeks), "notes": 0, "player": 0,
              "opponent": 0, "sustains": 0, "camera_events": 0,
              "animation_frames": 0}

    for manifest_path in song_manifests:
        song = load_json(manifest_path)
        song_id = str(song.get("id", ""))
        if not song_id or song_id in song_ids:
            raise ValueError(f"missing or duplicate song id in {manifest_path}")
        song_ids.add(song_id)

        audio = required_file(root, str(song.get("audio", "")), f"audio for {song_id}")
        validate_wav(audio)
        chart_path = required_file(root, str(song.get("chart", "")), f"chart for {song_id}")
        chart = load_json(chart_path)
        if chart.get("song") != song_id:
            raise ValueError(f"chart song id mismatch for {song_id}")

        notes = chart.get("notes", [])
        if not isinstance(notes, list) or not notes:
            raise ValueError(f"chart has no notes: {song_id}")
        owners: set[str] = set()
        for note in notes:
            if not isinstance(note, dict):
                raise ValueError(f"non-object note in {song_id}")
            lane = note.get("lane")
            owner = note.get("owner")
            time_ms = note.get("timeMs")
            if lane not in (0, 1, 2, 3) or owner not in ("player", "opponent"):
                raise ValueError(f"invalid lane/owner in {song_id}: {note}")
            if not isinstance(time_ms, (int, float)) or time_ms < 0:
                raise ValueError(f"invalid note time in {song_id}: {note}")
            owners.add(owner)
            totals[owner] += 1
            totals["notes"] += 1
            if float(note.get("lengthMs", 0)) > 0:
                totals["sustains"] += 1
        if owners != {"player", "opponent"}:
            raise ValueError(f"chart must contain both owners: {song_id}")
        events = chart.get("cameraEvents", [])
        if not isinstance(events, list):
            raise ValueError(f"cameraEvents must be an array: {song_id}")
        totals["camera_events"] += len(events)

        for field in ("stageImage", "playerIcon", "opponentIcon"):
            required_file(root, str(song.get(field, "")), f"{field} for {song_id}")
        for field in ("playerVisual", "opponentVisual", "girlfriendVisual"):
            visual = root / str(song.get(field, ""))
            for pose in ("idle", "left", "down", "up", "right"):
                frames = sorted((visual / pose).glob("*.png"))
                if not frames:
                    raise ValueError(f"missing {pose} animation for {field} in {song_id}")

        totals["songs"] += 1

    for week in weeks:
        if not isinstance(week, dict) or not week.get("id"):
            raise ValueError("each week requires an id")
        listed = week.get("songs", [])
        if not isinstance(listed, list) or not listed:
            raise ValueError(f"week has no songs: {week.get('id')}")
        missing = [song for song in listed if song not in song_ids]
        if missing:
            raise ValueError(f"week {week.get('id')} references missing songs: {missing}")

    frames_root = root / "assets/imported/characters"
    totals["animation_frames"] = sum(
        1 for pose in ("idle", "left", "down", "up", "right")
        for path in frames_root.glob(f"*/{pose}/*.png") if path.is_file()
    )
    required_file(root, "migration/source-unconverted/psych-source/pack.json", "preserved source")
    return totals


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mod_root", type=Path)
    args = parser.parse_args()
    try:
        totals = validate(args.mod_root.resolve())
    except ValueError as exc:
        print(f"VALIDATION FAILED: {exc}", file=sys.stderr)
        return 1
    print("VALIDATION PASSED")
    for key, value in totals.items():
        print(f"{key}: {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

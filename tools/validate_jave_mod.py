"""Validate a self-contained Jave Engine mod package."""

from __future__ import annotations

import argparse
import json
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


def validate_audio(path: Path) -> None:
    if not path.is_file() and path.suffix.lower() == ".wav" and path.with_suffix(".ogg").is_file():
        path = path.with_suffix(".ogg")
    if not path.is_file():
        raise ValueError(f"missing audio: {path}")
    header = path.read_bytes()[:12]
    suffix = path.suffix.lower()
    if suffix == ".wav":
        if len(header) != 12 or header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            raise ValueError(f"not a valid RIFF/WAVE file: {path}")
    elif suffix == ".ogg":
        if header[:4] != b"OggS":
            raise ValueError(f"not a valid Ogg file: {path}")
    elif suffix == ".mp3":
        if header[:3] != b"ID3" and not (len(header) >= 2 and header[0] == 0xFF and header[1] & 0xE0 == 0xE0):
            raise ValueError(f"not a valid MP3 file: {path}")
    else:
        raise ValueError(f"supported audio is WAV, Ogg Vorbis or MP3: {path}")


def validate(root: Path) -> dict[str, int]:
    mod = load_json(required_file(root, "mod.json", "mod manifest"))
    for field in ("id", "name", "version", "author", "description"):
        if field in mod and not isinstance(mod[field], str):
            raise ValueError(f"mod.json {field} must be a string")
    if "enabled" in mod and not isinstance(mod["enabled"], bool):
        raise ValueError("mod.json enabled must be true or false")

    totals = {"songs": 0, "weeks": 0, "scripts": 0, "notes": 0, "player": 0,
              "opponent": 0, "sustains": 0, "camera_events": 0}
    song_ids: set[str] = set()

    for manifest_path in sorted(root.glob("songs/*/song.json")):
        song = load_json(manifest_path)
        song_id = str(song.get("id", ""))
        if not song_id or song_id in song_ids:
            raise ValueError(f"missing or duplicate song id in {manifest_path}")
        song_ids.add(song_id)

        validate_audio(root / str(song.get("audio", "")))
        chart = load_json(required_file(root, str(song.get("chart", "")), f"chart for {song_id}"))
        if chart.get("format") != "jave-chart-v1":
            raise ValueError(f"chart format must be jave-chart-v1: {song_id}")

        notes = chart.get("notes", [])
        if not isinstance(notes, list) or not notes:
            raise ValueError(f"chart has no notes: {song_id}")
        for note in notes:
            if not isinstance(note, dict):
                raise ValueError(f"non-object note in {song_id}")
            lane = note.get("lane")
            owner = note.get("owner", "player")
            time_ms = note.get("timeMs")
            if lane not in (0, 1, 2, 3) or owner not in ("player", "opponent"):
                raise ValueError(f"invalid lane/owner in {song_id}: {note}")
            if not isinstance(time_ms, (int, float)) or time_ms < 0:
                raise ValueError(f"invalid note time in {song_id}: {note}")
            totals[owner] += 1
            totals["notes"] += 1
            if float(note.get("lengthMs", 0)) > 0:
                totals["sustains"] += 1
        events = chart.get("cameraEvents", [])
        if not isinstance(events, list):
            raise ValueError(f"cameraEvents must be an array: {song_id}")
        totals["camera_events"] += len(events)

        for field in ("stageImage", "playerIcon", "opponentIcon"):
            if song.get(field):
                required_file(root, str(song[field]), f"{field} for {song_id}")
        for field in ("playerVisual", "opponentVisual", "girlfriendVisual"):
            if not song.get(field):
                continue
            visual = root / str(song[field])
            for pose in ("idle", "left", "down", "up", "right"):
                if not any((visual / pose).glob("*.png")) and not (visual / f"{pose}.png").is_file():
                    raise ValueError(f"missing {pose} animation for {field} in {song_id}")

        totals["songs"] += 1

    weeks_path = root / "data/weeks.json"
    if weeks_path.is_file():
        weeks = load_json(weeks_path).get("weeks", [])
        if not isinstance(weeks, list):
            raise ValueError("data/weeks.json weeks must be an array")
        for week in weeks:
            if not isinstance(week, dict) or not week.get("id"):
                raise ValueError("each week requires an id")
            listed = week.get("songs", [])
            if not isinstance(listed, list) or not listed:
                raise ValueError(f"week has no songs: {week.get('id')}")
            missing = [song for song in listed if song not in song_ids]
            if missing:
                print(f"warning: week {week.get('id')} lists songs this mod does not contain: {missing}")
        totals["weeks"] = len(weeks)

    for script in sorted(root.glob("scripts/*.lua")):
        try:
            script.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            raise ValueError(f"script is not UTF-8: {script}: {exc}") from exc
        totals["scripts"] += 1

    if totals["songs"] == 0 and totals["scripts"] == 0:
        raise ValueError("mod adds no songs/*/song.json and no scripts/*.lua")
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

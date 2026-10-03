"""Validate Jave Engine JSON packages and PCM WAV demo audio."""

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        return None


song_ids: set[str] = set()
for package in [ROOT] + list((ROOT / "mods").glob("*")):
    for stage_file in (package / "data/stages").glob("*.json"):
        stage = load(stage_file)
        if not isinstance(stage, dict) or "layout" not in stage:
            continue
        layout = stage["layout"]
        if not isinstance(layout, dict):
            errors.append(f"{stage_file.relative_to(ROOT)}: invalid layout")
            continue
        for role in ("player", "opponent", "girlfriend"):
            placement = layout.get("placements", {}).get(role, {})
            anchor = placement.get("anchor", [])
            if not isinstance(anchor, list) or len(anchor) != 2 or not all(isinstance(v, (int, float)) for v in anchor):
                errors.append(f"{stage_file.relative_to(ROOT)}: invalid {role} anchor")
            scale = placement.get("scale", 1)
            if not isinstance(scale, (int, float)) or scale <= 0:
                errors.append(f"{stage_file.relative_to(ROOT)}: invalid {role} scale")
player_notes = 0
opponent_notes = 0
camera_events = 0
for manifest in sorted((ROOT / "songs").glob("*/song.json")):
    song = load(manifest)
    if not isinstance(song, dict):
        continue
    required = ("id", "title", "artist", "audio", "chart")
    for field in required:
        if not song.get(field):
            errors.append(f"{manifest.relative_to(ROOT)}: missing {field}")
    song_id = song.get("id", "")
    if song_id in song_ids:
        errors.append(f"duplicate song id: {song_id}")
    song_ids.add(song_id)
    if song.get("stage") and song.get("boyfriendPosition"):
        stage_file = ROOT / "data" / "stages" / f"{song['stage']}.json"
        if not stage_file.is_file():
            errors.append(f"{manifest.relative_to(ROOT)}: missing stage metadata {stage_file.relative_to(ROOT)}")
        for field in ("boyfriendPosition", "girlfriendPosition", "opponentPosition",
                      "cameraBoyfriend", "cameraGirlfriend", "cameraOpponent"):
            point = song.get(field)
            if not isinstance(point, list) or len(point) != 2 or not all(isinstance(value, (int, float)) for value in point):
                errors.append(f"{manifest.relative_to(ROOT)}: invalid {field}")
    for field in ("stageImage", "playerIcon", "opponentIcon"):
        if song.get(field) and not (ROOT / song[field]).is_file():
            errors.append(f"{manifest.relative_to(ROOT)}: missing {field} {song[field]}")
    for field in ("playerVisual", "opponentVisual", "girlfriendVisual"):
        if song.get(field):
            visual = ROOT / song[field]
            for pose in ("idle.png", "left.png", "down.png", "up.png", "right.png"):
                if not (visual / pose).is_file() and not list((visual / Path(pose).stem).glob("frame_*.png")):
                    errors.append(f"{manifest.relative_to(ROOT)}: missing {field} pose {pose}")
            for animation in ("idle", "left", "down", "up", "right"):
                if not list((visual / animation).glob("frame_*.png")):
                    errors.append(f"{manifest.relative_to(ROOT)}: missing {field} animation {animation}")
    audio = ROOT / song.get("audio", "")
    chart_path = ROOT / song.get("chart", "")
    if not audio.is_file():
        errors.append(f"missing audio: {audio.relative_to(ROOT)}")
    elif audio.suffix.lower() == ".wav":
        try:
            with audio.open("rb") as stream:
                if stream.read(4) != b"RIFF":
                    raise ValueError("missing RIFF header")
                stream.seek(8)
                if stream.read(4) != b"WAVE":
                    raise ValueError("missing WAVE signature")
        except Exception as exc:
            errors.append(f"{audio.relative_to(ROOT)}: invalid WAV: {exc}")
    else:
        errors.append(f"{audio.relative_to(ROOT)}: supported audio is WAV")
    chart = load(chart_path) if chart_path.is_file() else None
    if chart is None:
        errors.append(f"missing or invalid chart: {chart_path.relative_to(ROOT)}")
        continue
    if chart.get("format") != "jave-chart-v1":
        errors.append(f"{chart_path.relative_to(ROOT)}: wrong format")
    previous = -1.0
    notes = chart.get("notes", [])
    if not notes:
        errors.append(f"{chart_path.relative_to(ROOT)}: no notes")
    for index, note in enumerate(notes):
        time = note.get("timeMs", -1)
        lane = note.get("lane", -1)
        owner = note.get("owner", "player")
        length = note.get("lengthMs", 0)
        if not isinstance(time, (int, float)) or time < 0:
            errors.append(f"{chart_path.relative_to(ROOT)} note {index}: invalid timeMs")
        if lane not in range(4):
            errors.append(f"{chart_path.relative_to(ROOT)} note {index}: lane must be 0..3")
        if owner not in ("player", "opponent"):
            errors.append(f"{chart_path.relative_to(ROOT)} note {index}: owner must be player or opponent")
        elif owner == "player":
            player_notes += 1
        else:
            opponent_notes += 1
        if not isinstance(length, (int, float)) or length < 0:
            errors.append(f"{chart_path.relative_to(ROOT)} note {index}: invalid lengthMs")
        if isinstance(time, (int, float)) and time < previous:
            errors.append(f"{chart_path.relative_to(ROOT)} note {index}: notes are not sorted")
        if isinstance(time, (int, float)):
            previous = time
    previous_camera = -1.0
    for index, event in enumerate(chart.get("cameraEvents", [])):
        camera_events += 1
        event_time = event.get("timeMs", -1)
        if event.get("type") not in ("focus", "position", "zoom", "setZoom"):
            errors.append(f"{chart_path.relative_to(ROOT)} camera event {index}: invalid type")
        if not isinstance(event_time, (int, float)) or event_time < previous_camera:
            errors.append(f"{chart_path.relative_to(ROOT)} camera event {index}: invalid ordering")
        if isinstance(event_time, (int, float)):
            previous_camera = event_time

for manifest in sorted((ROOT / "mods").glob("*/mod.json")):
    mod = load(manifest)
    if isinstance(mod, dict):
        for field in ("id", "name", "version", "author"):
            if not mod.get(field):
                errors.append(f"{manifest.relative_to(ROOT)}: missing {field}")

for json_file in (ROOT / "config").glob("*.json"):
    load(json_file)

weeks_path = ROOT / "data" / "weeks.json"
weeks = load(weeks_path) if weeks_path.is_file() else None
if not isinstance(weeks, dict) or not isinstance(weeks.get("weeks"), list):
    errors.append("data/weeks.json: missing weeks array")
else:
    week_ids: set[str] = set()
    for index, week in enumerate(weeks["weeks"]):
        if not isinstance(week, dict) or not week.get("id") or not week.get("name"):
            errors.append(f"data/weeks.json week {index}: missing id or name")
            continue
        if week["id"] in week_ids:
            errors.append(f"data/weeks.json: duplicate week id {week['id']}")
        week_ids.add(week["id"])
        for song_id in week.get("songs", []):
            if song_id not in song_ids:
                errors.append(f"data/weeks.json {week['id']}: missing song {song_id}")

expected_note_centers = {
    "left": (0xC2, 0x4B, 0x99),
    "down": (0x00, 0xFF, 0xFF),
    "up": (0x12, 0xFA, 0x05),
    "right": (0xF9, 0x39, 0x3F),
}
for lane in ("left", "down", "up", "right"):
    for kind in ("receptor", "note", "press", "confirm", "hold", "hold_end"):
        note_image = ROOT / "assets" / "imported" / "notes" / f"{kind}_{lane}.png"
        if not note_image.is_file():
            errors.append(f"missing note PNG: {note_image.relative_to(ROOT)}")
            continue
        try:
            with Image.open(note_image) as image:
                rgba = image.convert("RGBA")
                if rgba.getbbox() is None:
                    errors.append(f"{note_image.relative_to(ROOT)}: empty transparent image")
                if kind == "note" and "--psych-palette" in sys.argv:
                    center = rgba.getpixel((rgba.width // 2, rgba.height // 2))[:3]
                    if center != expected_note_centers[lane]:
                        errors.append(
                            f"{note_image.relative_to(ROOT)}: Psych RGB palette was not baked "
                            f"(center {center}, expected {expected_note_centers[lane]})"
                        )
        except Exception as exc:
            errors.append(f"{note_image.relative_to(ROOT)}: invalid PNG: {exc}")

if errors:
    print("Jave content validation failed:")
    print("\n".join(f"- {error}" for error in errors))
    sys.exit(1)

print(f"Jave content validation passed: {len(song_ids)} song(s), {player_notes} player notes, "
      f"{opponent_notes} opponent notes, {camera_events} camera events")

"""Import user-supplied Psych Engine songs into Jave Engine.

Normal-difficulty charts (player and opponent notes) are converted to jave-chart-v1.
Instrumental and voice stems are mixed into one Ogg Vorbis file per song
(songs/<id>/Song.ogg) using an ffmpeg with libvorbis. Unsupported source JSON is
preserved under migration/source-unconverted and listed in the report.
Usage: python tools/import_psych_library.py PSYCH_ROOT JAVE_ROOT [--ffmpeg PATH]
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

from convert_audio import ffmpeg_problem


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "imported-song"


WEEK_IDS = ["tutorial", "week1", "week2", "week3", "week4", "week5", "week6", "week7", "weekend1"]
WEEK_STAGE = {
    "tutorial": "stage", "week1": "stage", "week2": "spooky", "week3": "philly",
    "week4": "limo", "week5": "mall", "week6": "school", "week7": "tank",
    "weekend1": "phillyStreets",
}
SPECIAL_STAGE = {"winter-horrorland": "mallEvil", "thorns": "schoolEvil", "blazin": "phillyBlazin"}
STAGE_MENU_IMAGE = {
    "stage": "menu_stage.png", "spooky": "menu_halloween.png", "philly": "menu_philly.png",
    "limo": "menu_limo.png", "mall": "menu_christmas.png", "mallEvil": "menu_christmas.png",
    "school": "menu_school.png", "schoolEvil": "menu_school.png", "tank": "menu_tank.png",
    "phillyStreets": "menu_phillystreets.png", "phillyBlazin": "menu_phillystreets.png",
}
POSES = {"idle": ["idle", "danceLeft", "danceRight"], "left": ["singLEFT"],
         "down": ["singDOWN"], "up": ["singUP"], "right": ["singRIGHT"]}

# Psych Engine 1.0 stores the default antialiased notes as RGB channel masks.
# Psych's RGBPalette shader replaces the source red, green, and blue channels
# with these three colors for each lane.  Jave uses ordinary PNGs, so bake the
# same palette into every colored frame during import instead of displaying the
# raw red/green/blue mask.
PSYCH_ARROW_RGB = (
    ((0xC2, 0x4B, 0x99), (0xFF, 0xFF, 0xFF), (0x3C, 0x1F, 0x56)),  # left
    ((0x00, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF), (0x15, 0x42, 0xB7)),  # down
    ((0x12, 0xFA, 0x05), (0xFF, 0xFF, 0xFF), (0x0A, 0x44, 0x47)),  # up
    ((0xF9, 0x39, 0x3F), (0xFF, 0xFF, 0xFF), (0x65, 0x10, 0x38)),  # right
)


def read_psych_weeks(assets: Path) -> tuple[list[dict], dict[str, tuple[int, str]]]:
    weeks = []
    order = {}
    next_order = 0
    root = assets / "shared" / "weeks"
    for week_id in WEEK_IDS:
        source = root / f"{week_id}.json"
        if not source.is_file():
            continue
        data = json.loads(source.read_text(encoding="utf-8-sig"))
        songs = [slug(str(row[0])) for row in data.get("songs", []) if isinstance(row, list) and row]
        color = data.get("songs", [["", "", [95, 227, 255]]])[0][2]
        if not isinstance(color, list) or len(color) != 3:
            color = [95, 227, 255]
        weeks.append({"id": week_id, "name": data.get("weekName", week_id),
                      "storyName": data.get("storyName", ""), "songs": songs, "color": color})
        for song_id in songs:
            order[song_id] = (next_order, week_id)
            next_order += 1
    return weeks, order


def read_stage_configs(assets: Path, target: Path) -> dict[str, dict]:
    result = {}
    source_root = assets / "shared" / "stages"
    output_root = target / "data" / "stages"
    output_root.mkdir(parents=True, exist_ok=True)
    for source in sorted(source_root.glob("*.json")):
        data = json.loads(source.read_text(encoding="utf-8-sig"))
        stage_id = source.stem
        converted = {
            "id": stage_id,
            "defaultZoom": float(data.get("defaultZoom", 0.9)),
            "cameraSpeed": float(data.get("camera_speed", 1.0)),
            "boyfriend": data.get("boyfriend", [770, 100]),
            "girlfriend": data.get("girlfriend", [400, 130]),
            "opponent": data.get("opponent", [100, 100]),
            "cameraBoyfriend": data.get("camera_boyfriend", [0, 0]),
            "cameraGirlfriend": data.get("camera_girlfriend", [0, 0]),
            "cameraOpponent": data.get("camera_opponent", [0, 0]),
            "hideGirlfriend": bool(data.get("hide_girlfriend", False)),
        }
        destination = output_root / f"{stage_id}.json"
        if destination.is_file():
            previous = json.loads(destination.read_bytes())
            if isinstance(previous.get("layout"), dict):
                converted["layout"] = previous["layout"]
        destination.write_text(json.dumps(converted, indent=2) + "\n", encoding="utf-8")
        result[stage_id] = converted
    return result


def select_animation(data: dict, pose: str) -> dict | None:
    animations = data.get("animations", [])
    for wanted in POSES.get(pose, (pose,)):
        for animation in animations:
            if animation.get("anim") == wanted:
                return animation
    return animations[0] if pose == "idle" and animations else None


def atlas_frames(xml_path: Path) -> list[dict]:
    root = ET.parse(xml_path).getroot()
    frames = []
    for node in root.iter():
        if node.tag.lower().endswith("subtexture"):
            frames.append({key: node.attrib.get(key) for key in (
                "name", "x", "y", "width", "height", "rotated", "frameX", "frameY", "frameWidth", "frameHeight"
            )})
    return frames


def rebuild_atlas_frame(source: Image.Image, frame: dict) -> Image.Image:
    x, y = int(frame["x"]), int(frame["y"])
    width, height = int(frame["width"]), int(frame["height"])
    cropped = source.crop((x, y, x + width, y + height))
    if str(frame.get("rotated", "false")).lower() == "true":
        cropped = cropped.transpose(Image.Transpose.ROTATE_90)
    frame_width = int(frame.get("frameWidth") or width)
    frame_height = int(frame.get("frameHeight") or height)
    frame_x = int(frame.get("frameX") or 0)
    frame_y = int(frame.get("frameY") or 0)
    rebuilt = Image.new("RGBA", (frame_width, frame_height), (0, 0, 0, 0))
    rebuilt.alpha_composite(cropped, (-frame_x, -frame_y))
    return rebuilt


def bake_psych_rgb_palette(image: Image.Image,
                           palette: tuple[tuple[int, int, int], ...]) -> Image.Image:
    """Apply Psych's RGBPalette fragment-shader math to an RGBA image."""
    red_color, green_color, blue_color = palette
    source_pixels = image.load()
    shaded = Image.new("RGBA", image.size)
    shaded.putdata([
        (
            min(255, round((red * red_color[0] + green * green_color[0] + blue * blue_color[0]) / 255)),
            min(255, round((red * red_color[1] + green * green_color[1] + blue * blue_color[1]) / 255)),
            min(255, round((red * red_color[2] + green * green_color[2] + blue * blue_color[2]) / 255)),
            alpha,
        )
        for y in range(image.height)
        for red, green, blue, alpha in (source_pixels[x, y] for x in range(image.width))
    ])
    return shaded


def load_pose_frames(assets: Path, character_id: str, pose: str) -> tuple[list[Image.Image], int]:
    character_file = assets / "shared" / "characters" / f"{character_id}.json"
    if not character_file.is_file():
        return [], 24
    data = json.loads(character_file.read_text(encoding="utf-8-sig"))
    animation = select_animation(data, pose)
    if not animation:
        return [], 24
    image_id = str(data.get("image", "")).split(",")[0].strip()
    image_path = assets / "shared" / "images" / f"{image_id}.png"
    xml_path = assets / "shared" / "images" / f"{image_id}.xml"
    if not image_path.is_file() or not xml_path.is_file():
        return [], int(animation.get("fps", 24))
    prefix = str(animation.get("name", ""))
    frames = sorted(atlas_frames(xml_path), key=lambda frame: str(frame.get("name", "")))
    matches = [frame for frame in frames if str(frame.get("name", "")).startswith(prefix)]
    if not matches:
        return [], int(animation.get("fps", 24))
    indices = animation.get("indices", [])
    if isinstance(indices, list) and indices:
        indexed = []
        for index in indices:
            if 0 <= int(index) < len(matches):
                indexed.append(matches[int(index)])
        if indexed:
            matches = indexed
    source = Image.open(image_path).convert("RGBA")
    rebuilt = [rebuild_atlas_frame(source, frame) for frame in matches]
    max_width = max(image.width for image in rebuilt)
    max_height = max(image.height for image in rebuilt)
    normalized = []
    for image in rebuilt:
        canvas = Image.new("RGBA", (max_width, max_height), (0, 0, 0, 0))
        canvas.alpha_composite(image, ((max_width - image.width) // 2, max_height - image.height))
        normalized.append(canvas)
    return normalized, max(1, int(animation.get("fps", 24)))


def save_pose_animation(frames: list[Image.Image], destination: Path) -> bool:
    if not frames:
        return False
    if destination.is_dir():
        shutil.rmtree(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames):
        frame.save(destination / f"frame_{index:03d}.png", optimize=True)
    return True


def extract_named_atlas_frame(image_path: Path, xml_path: Path, frame_name: str, destination: Path,
                              palette: tuple[tuple[int, int, int], ...] | None = None) -> bool:
    if not image_path.is_file() or not xml_path.is_file():
        return False
    frame = next((item for item in atlas_frames(xml_path) if item.get("name") == frame_name), None)
    if not frame:
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    rebuilt_atlas = rebuild_atlas_frame(Image.open(image_path).convert("RGBA"), frame)
    if palette is not None:
        rebuilt_atlas = bake_psych_rgb_palette(rebuilt_atlas, palette)
    rebuilt_atlas.save(destination, optimize=True)
    return True


def create_note_images(assets: Path, target: Path) -> dict[str, str]:
    source_root = assets / "shared" / "images" / "noteSkins"
    image_path = source_root / "NOTE_assets.png"
    xml_path = source_root / "NOTE_assets.xml"
    output = target / "assets" / "imported" / "notes"
    lane_names = ("left", "down", "up", "right")
    receptors = ("arrowLEFT0000", "arrowDOWN0000", "arrowUP0000", "arrowRIGHT0000")
    colors = ("purple", "blue", "green", "red")
    result = {}
    for lane, (lane_name, receptor, color) in enumerate(zip(lane_names, receptors, colors)):
        names = {
            "receptor": receptor,
            "note": f"{color}0000",
            "press": f"{lane_name} press0000",
            "confirm": f"{lane_name} confirm0000",
            "hold": f"{color} hold piece0000",
            "hold_end": f"{color} hold end0000",
        }
        for kind, atlas_name in names.items():
            destination = output / f"{kind}_{lane_name}.png"
            palette = None if kind == "receptor" else PSYCH_ARROW_RGB[lane]
            if not extract_named_atlas_frame(image_path, xml_path, atlas_name, destination, palette):
                raise RuntimeError(f"missing Psych note atlas frame: {atlas_name}")
            result[f"{kind}_{lane}"] = destination.relative_to(target).as_posix()
    return result


def create_character_visuals(assets: Path, target: Path, character_ids: set[str], force: bool = False) -> dict[str, dict[str, str]]:
    visuals = {}
    fallback = {"pico-blazin": "pico-playable", "darnell-blazin": "darnell", "spirit": "senpai-angry"}
    for character_id in sorted(character_ids):
        safe_id = slug(character_id or "gf")
        output_dir = target / "assets" / "imported" / "characters" / safe_id
        existing_poses = {pose: output_dir / f"{pose}.png" for pose in ("idle", "left", "down", "up", "right")}
        if (not force and output_dir.joinpath("animation.json").is_file() and
                json.loads((output_dir / "animation.json").read_text()).get("version") == 2 and
                all(path.is_file() and list((output_dir / pose).glob("frame_*.png")) for pose, path in existing_poses.items())):
            visuals[character_id] = {pose: path.relative_to(target).as_posix() for pose, path in existing_poses.items()}
            continue
        pose_paths = {}
        source_id = character_id
        idle_frames, idle_fps = load_pose_frames(assets, source_id, "idle")
        if not idle_frames and character_id in fallback:
            source_id = fallback[character_id]
            idle_frames, idle_fps = load_pose_frames(assets, source_id, "idle")
        if not idle_frames:
            placeholder = Image.new("RGBA", (260, 360), (0, 0, 0, 0))
            draw = ImageDraw.Draw(placeholder)
            draw.ellipse((70, 20, 190, 140), fill=(180, 190, 220, 255))
            draw.rounded_rectangle((40, 130, 220, 350), 50, fill=(95, 105, 150, 255))
            draw.text((20, 330), safe_id, fill=(255, 255, 255, 255))
            idle_frames = [placeholder]
        save_pose_animation(idle_frames, output_dir / "idle")
        idle_path = output_dir / "idle.png"
        idle_frames[0].save(idle_path, optimize=True)
        pose_paths["idle"] = idle_path
        source_file = assets / "shared" / "characters" / f"{source_id}.json"
        source_meta = json.loads(source_file.read_text(encoding="utf-8-sig")) if source_file.is_file() else {}
        animation_meta = {"version": 2, "scale": source_meta.get("scale", 1),
                          "flipX": source_meta.get("flip_x", False),
                          "idle": {"frames": len(idle_frames), "fps": idle_fps,
                                   "loop": False, "width": idle_frames[0].width, "height": idle_frames[0].height}}
        extra_poses = ("danceRight",) if select_animation(source_meta, "danceRight") else ()
        for pose in ("left", "down", "up", "right") + extra_poses:
            destination = output_dir / f"{pose}.png"
            pose_frames, pose_fps = load_pose_frames(assets, source_id, pose)
            if not pose_frames:
                pose_frames = idle_frames
                pose_fps = idle_fps
            save_pose_animation(pose_frames, output_dir / pose)
            pose_frames[0].save(destination, optimize=True)
            pose_paths[pose] = destination
            animation = select_animation(source_meta, pose) or {}
            animation_meta[pose] = {"frames": len(pose_frames), "fps": pose_fps,
                                    "loop": bool(animation.get("loop", False)),
                                    "width": pose_frames[0].width, "height": pose_frames[0].height}
        (output_dir / "animation.json").write_text(json.dumps(animation_meta, indent=2) + "\n", encoding="utf-8")
        visuals[character_id] = {pose: path.relative_to(target).as_posix() for pose, path in pose_paths.items()}
    return visuals


def create_icon(assets: Path, target: Path, character_id: str) -> str:
    character_file = assets / "shared" / "characters" / f"{character_id}.json"
    health_icon = character_id
    if character_file.is_file():
        data = json.loads(character_file.read_text(encoding="utf-8-sig"))
        health_icon = str(data.get("healthicon") or character_id)
    source = assets / "shared" / "images" / "icons" / f"icon-{health_icon}.png"
    if not source.is_file():
        source = assets / "shared" / "images" / "icons" / "icon-face.png"
    destination = target / "assets" / "imported" / "icons" / f"{slug(character_id)}.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    image = Image.open(source).convert("RGBA")
    frame = min(image.height, image.width // 2 if image.width >= image.height * 2 else image.width)
    image.crop((0, 0, frame, min(frame, image.height))).save(destination)
    return destination.relative_to(target).as_posix()


def create_stage_images(assets: Path, target: Path) -> dict[str, str]:
    layers = {
        "stage": [("week1/images/stageback.png", "cover"), ("week1/images/stagefront.png", "bottom"), ("week1/images/stagecurtains.png", "cover")],
        "spooky": [("week2/images/halloween_bg_low.png", "cover")],
        "philly": [("week3/images/philly/sky.png", "cover"), ("week3/images/philly/city.png", "cover"), ("week3/images/philly/street.png", "cover")],
        "limo": [("week4/images/limo/limoSunset.png", "cover")],
        "mall": [("week5/images/christmas/bgWalls.png", "cover"), ("week5/images/christmas/fgSnow.png", "bottom")],
        "mallEvil": [("week5/images/christmas/evilBG.png", "cover"), ("week5/images/christmas/evilSnow.png", "bottom")],
        "school": [("week6/images/weeb/weebSky.png", "cover"), ("week6/images/weeb/weebSchool.png", "cover"), ("week6/images/weeb/weebStreet.png", "cover")],
        "schoolEvil": [("week6/images/weeb/evilSchoolBG.png", "cover"), ("week6/images/weeb/evilSchoolFG.png", "cover")],
        "tank": [("week7/images/tankSky.png", "cover"), ("week7/images/tankMountains.png", "bottom"), ("week7/images/tankBuildings.png", "bottom"), ("week7/images/tankRuins.png", "bottom"), ("week7/images/tankGround.png", "cover")],
        "phillyStreets": [("weekend1/images/phillyStreets/phillySkybox.png", "cover"), ("weekend1/images/phillyStreets/phillySkyline.png", "bottom"), ("weekend1/images/phillyStreets/phillyConstruction.png", "bottom"), ("weekend1/images/phillyStreets/phillyForeground.png", "bottom")],
        "phillyBlazin": [("weekend1/images/phillyBlazin/skyBlur.png", "cover"), ("weekend1/images/phillyBlazin/streetBlur.png", "bottom")],
    }
    menu_root = assets / "shared" / "images" / "menubackgrounds"
    result = {}
    for stage, fallback_name in STAGE_MENU_IMAGE.items():
        destination = target / "assets" / "imported" / "stages" / f"{stage}.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        canvas = Image.new("RGBA", (1280, 720), (8, 10, 20, 255))
        rendered = False
        for relative, mode in layers.get(stage, []):
            source = assets / relative
            if not source.is_file():
                continue
            image = Image.open(source).convert("RGBA")
            if mode == "cover":
                image = ImageOps.fit(image, (1280, 720), Image.Resampling.LANCZOS)
                canvas.alpha_composite(image)
            else:
                scale = 1280 / image.width
                image = image.resize((1280, max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
                if image.height > 720:
                    image = image.crop((0, image.height - 720, 1280, image.height))
                canvas.alpha_composite(image, (0, 720 - image.height))
            rendered = True
        if not rendered:
            canvas = ImageOps.fit(Image.open(menu_root / fallback_name).convert("RGBA"), (1280, 720), Image.Resampling.LANCZOS)
        canvas.save(destination)
        result[stage] = destination.relative_to(target).as_posix()
    return result


def convert_chart(source: Path, destination: Path, fallback_id: str, fallback_stage: str) -> dict:
    root = json.loads(source.read_text(encoding="utf-8-sig"))
    nested = root.get("song") if isinstance(root, dict) else None
    song = nested if isinstance(nested, dict) else root
    if not isinstance(song, dict) or not isinstance(song.get("notes"), list):
        raise ValueError("expected song.notes section array")
    title = str(song.get("song") or fallback_id.replace("-", " ").title())
    bpm = float(song.get("bpm", 120))
    converted = []
    camera_events = []
    player_count = 0
    opponent_count = 0
    section_time_ms = 0.0
    current_bpm = bpm
    last_focus = None
    for section in song["notes"]:
        if not isinstance(section, dict):
            continue
        player_section = bool(section.get("mustHitSection", False))
        focus = "player" if player_section else "opponent"
        if focus != last_focus:
            camera_events.append({"timeMs": round(section_time_ms, 3), "type": "focus", "target": focus})
            last_focus = focus
        for raw in section.get("sectionNotes", []):
            if not isinstance(raw, list) or len(raw) < 2:
                continue
            time_ms = float(raw[0])
            note_data = int(raw[1])
            sustain_ms = max(0.0, float(raw[2])) if len(raw) > 2 else 0.0
            # This supplied library has already normalized ownership by section.
            # Applying Psych's legacy noteData >= 4 flip again produces almost all-BF charts.
            belongs_to_player = player_section
            note = {"timeMs": round(time_ms, 3), "lane": note_data % 4,
                    "owner": "player" if belongs_to_player else "opponent"}
            if belongs_to_player:
                player_count += 1
            else:
                opponent_count += 1
            if sustain_ms > 0:
                note["lengthMs"] = round(sustain_ms, 3)
            converted.append(note)
        if section.get("changeBPM") and section.get("bpm"):
            current_bpm = float(section["bpm"])
        section_beats = float(section.get("sectionBeats", section.get("lengthInSteps", 16) / 4))
        section_time_ms += section_beats * 60000.0 / current_bpm

    events_source = source.parent / "events.json"
    if events_source.is_file():
        event_root = json.loads(events_source.read_text(encoding="utf-8-sig"))
        nested_events = event_root.get("song") if isinstance(event_root, dict) else None
        event_data = nested_events if isinstance(nested_events, dict) else event_root
        for event_group in event_data.get("events", []) if isinstance(event_data, dict) else []:
            if not isinstance(event_group, list) or len(event_group) < 2:
                continue
            event_time = float(event_group[0])
            for event in event_group[1]:
                if not isinstance(event, list) or not event:
                    continue
                name = str(event[0])
                value1 = str(event[1]) if len(event) > 1 else ""
                value2 = str(event[2]) if len(event) > 2 else ""
                try:
                    if name == "Camera Follow Pos":
                        camera_events.append({"timeMs": event_time, "type": "position",
                                              "x": float(value1 or 0), "y": float(value2 or 0)})
                    elif name == "Add Camera Zoom":
                        camera_events.append({"timeMs": event_time, "type": "zoom",
                                              "amount": float(value1 or 0.015)})
                    elif name == "Set Camera Zoom":
                        camera_events.append({"timeMs": event_time, "type": "setZoom",
                                              "amount": float(value1 or 0.9)})
                except ValueError:
                    continue
    converted.sort(key=lambda item: (item["timeMs"], item["lane"]))
    camera_events.sort(key=lambda item: item["timeMs"])
    output = {
        "format": "jave-chart-v1",
        "song": fallback_id,
        "difficulty": "normal",
        "bpm": bpm,
        "offsetMs": 0,
        "notes": converted,
        "cameraEvents": camera_events,
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    return {
        "title": title, "bpm": bpm, "playerNotes": player_count, "opponentNotes": opponent_count,
        "stage": str(song.get("stage") or fallback_stage), "cameraEvents": len(camera_events),
        "player": str(song.get("player1") or "bf"),
        "opponent": str(song.get("player2") or "dad"),
        "girlfriend": str(song.get("gfVersion") or song.get("player3") or "gf"),
    }


def mix_audio(ffmpeg: str, source_dir: Path, destination: Path) -> str:
    inputs = [source_dir / "Inst.ogg"]
    inputs += sorted(source_dir.glob("Voices*.ogg"))
    command = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error"]
    for audio in inputs:
        command += ["-i", str(audio)]
    if len(inputs) == 1:
        command += ["-map", "0:a:0"]
    else:
        pads = "".join(f"[{index}:a:0]" for index in range(len(inputs)))
        mix = f"{pads}amix=inputs={len(inputs)}:duration=longest:dropout_transition=0:normalize=0,alimiter=limit=0.95[mix]"
        command += ["-filter_complex", mix, "-map", "[mix]"]
    partial = destination.with_name(destination.stem + ".partial.ogg")
    command += ["-ar", "44100", "-ac", "2", "-c:a", "libvorbis", "-q:a", "6", str(partial)]
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        partial.unlink(missing_ok=True)
        raise RuntimeError(result.stderr.strip() or f"ffmpeg exited {result.returncode}")
    partial.replace(destination)
    return destination.name


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("psych_root", type=Path, help="Psych Engine installation (holds assets/)")
parser.add_argument("jave_root", type=Path, help="Jave Engine content root to write into")
parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"), help="ffmpeg with the libvorbis encoder (default: ffmpeg on PATH)")
parser.add_argument("--workers", type=int, default=4)
parser.add_argument("--notes-only", action="store_true",
                    help="rebuild only the Psych note PNGs (no audio or chart conversion)")
parser.add_argument("--characters-only", action="store_true")
parser.add_argument("--character", action="append", help="character ID to rebuild with --characters-only")
args = parser.parse_args()

if args.characters_only:
    character_ids = set(args.character) if args.character else {path.name for path in (args.jave_root / "assets/imported/characters").iterdir() if path.is_dir()}
    create_character_visuals(args.psych_root / "assets", args.jave_root, character_ids, force=True)
    print(f"Rebuilt {len(character_ids)} character animations")
    raise SystemExit(0)

if args.notes_only:
    note_images = create_note_images(args.psych_root / "assets", args.jave_root)
    print(f"done: rebuilt {len(note_images)} Psych note PNGs with baked RGB palettes")
    raise SystemExit(0)

ffmpeg_error = ffmpeg_problem(args.ffmpeg)
if ffmpeg_error:
    raise SystemExit(f"error: {ffmpeg_error}")
assets = args.psych_root / "assets"
audio_root = assets / "songs"
chart_root = assets / "shared" / "data"
if not audio_root.is_dir() or not chart_root.is_dir():
    raise SystemExit("Expected Psych assets/songs and assets/shared/data folders")

weeks, story_order = read_psych_weeks(assets)
stage_images = create_stage_images(assets, args.jave_root)
stage_configs = read_stage_configs(assets, args.jave_root)
note_images = create_note_images(assets, args.jave_root)
jobs = []
records = []
character_ids = set()
skipped = []
errors = []
for chart_dir in sorted(path for path in chart_root.iterdir() if path.is_dir()):
    song_id = slug(chart_dir.name)
    chart_source = chart_dir / f"{chart_dir.name}.json"
    source_audio = audio_root / chart_dir.name
    if not chart_source.is_file():
        skipped.append((song_id, "normal chart missing"))
        continue
    if not (source_audio / "Inst.ogg").is_file():
        skipped.append((song_id, "Inst.ogg missing"))
        continue
    try:
        order, week_id = story_order.get(song_id, (100000, ""))
        fallback_stage = SPECIAL_STAGE.get(song_id, WEEK_STAGE.get(week_id, "stage"))
        chart_destination = args.jave_root / "data" / "charts" / f"{song_id}.json"
        details = convert_chart(chart_source, chart_destination, song_id, fallback_stage)
        if song_id in SPECIAL_STAGE:
            details["stage"] = SPECIAL_STAGE[song_id]
        song_dir = args.jave_root / "songs" / song_id
        song_dir.mkdir(parents=True, exist_ok=True)
        character_ids.update((details["player"], details["opponent"], details["girlfriend"]))
        records.append({"songId": song_id, "weekId": week_id, "order": order, "details": details,
                        "sourceAudio": source_audio, "songDir": song_dir})
    except Exception as exc:
        errors.append((song_id, f"chart conversion failed: {exc}"))

character_visuals = create_character_visuals(assets, args.jave_root, character_ids)
icon_paths = {character_id: create_icon(assets, args.jave_root, character_id) for character_id in character_ids}

for record in records:
    song_id = record["songId"]
    details = record["details"]
    stage_config = stage_configs.get(details["stage"], stage_configs.get("stage", {}))
    metadata = {
        "id": song_id,
        "title": details["title"],
        "artist": "Loaded from FNF Original",
        "bpm": details["bpm"],
        "order": record["order"],
        "week": record["weekId"],
        "stage": details["stage"],
        "playerCharacter": details["player"],
        "opponentCharacter": details["opponent"],
        "girlfriendCharacter": details["girlfriend"],
        "stageImage": stage_images.get(details["stage"], stage_images["stage"]),
        "playerVisual": character_visuals[details["player"]]["idle"].rsplit("/", 1)[0],
        "opponentVisual": character_visuals[details["opponent"]]["idle"].rsplit("/", 1)[0],
        "girlfriendVisual": character_visuals[details["girlfriend"]]["idle"].rsplit("/", 1)[0],
        "playerIcon": icon_paths[details["player"]],
        "opponentIcon": icon_paths[details["opponent"]],
        "boyfriendPosition": stage_config.get("boyfriend", [770, 100]),
        "girlfriendPosition": stage_config.get("girlfriend", [400, 130]),
        "opponentPosition": stage_config.get("opponent", [100, 100]),
        "cameraBoyfriend": stage_config.get("cameraBoyfriend", [0, 0]),
        "cameraGirlfriend": stage_config.get("cameraGirlfriend", [0, 0]),
        "cameraOpponent": stage_config.get("cameraOpponent", [0, 0]),
        "cameraSpeed": stage_config.get("cameraSpeed", 1.0),
        "defaultZoom": stage_config.get("defaultZoom", 0.9),
        "hideGirlfriend": stage_config.get("hideGirlfriend", False),
        "audio": f"songs/{song_id}/Song.ogg",
        "chart": f"data/charts/{song_id}.json",
        "description": "Converted from the user's local PsychEngine folder.",
        "license": "User-supplied content; no redistribution rights granted by Jave Engine",
    }
    (record["songDir"] / "song.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    jobs.append((song_id, details, record["sourceAudio"], record["songDir"] / "Song.ogg"))

available_ids = {record["songId"] for record in records}
for week in weeks:
    week["songs"] = [song_id for song_id in week["songs"] if song_id in available_ids]
(args.jave_root / "data" / "weeks.imported.json").write_text(json.dumps({"format": "jave-weeks-v1", "weeks": weeks}, indent=2) + "\n", encoding="utf-8")


def run_job(job):
    song_id, details, source_audio, destination = job
    if not destination.is_file() or destination.stat().st_size < 4096:
        mix_audio(args.ffmpeg, source_audio, destination)
    return song_id, details["title"], details["playerNotes"], details["opponentNotes"], destination.stat().st_size


converted = []
with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
    futures = {pool.submit(run_job, job): job for job in jobs}
    for future in concurrent.futures.as_completed(futures):
        job = futures[future]
        try:
            converted.append(future.result())
            print(f"converted {job[0]}")
        except Exception as exc:
            errors.append((job[0], f"audio conversion failed: {exc}"))

# Preserve non-normal Psych JSON that Jave does not execute.
unconverted_root = args.jave_root / "migration" / "source-unconverted"
for chart_dir in sorted(path for path in chart_root.iterdir() if path.is_dir()):
    extras = [path for path in chart_dir.glob("*.json") if path.name.lower() != f"{chart_dir.name.lower()}.json"]
    for extra in extras:
        destination = unconverted_root / slug(chart_dir.name) / extra.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(extra, destination)
for song_id, reason in skipped:
    destination = unconverted_root / song_id / "MISSING_AUDIO.txt"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(reason + "\n", encoding="utf-8")

converted.sort()
character_dirs = list((args.jave_root / "assets" / "imported" / "characters").iterdir())
animation_frame_count = sum(1 for character_dir in character_dirs for _ in character_dir.rglob("frame_*.png"))
fallback_pose_count = sum(
    pose.read_bytes() == (character_dir / "idle.png").read_bytes()
    for character_dir in character_dirs
    for pose in character_dir.glob("*.png")
    if pose.name != "idle.png"
)
report = [
    "# Psych song migration report",
    "",
    f"Source: `{args.psych_root}`",
    "",
    f"- Converted songs: {len(converted)}",
    f"- Skipped songs: {len(skipped)}",
    f"- Errors: {len(errors)}",
    "- Difficulty imported: Normal",
    "- Audio: Inst plus available Voices stems mixed to stereo Ogg Vorbis (quality 6)",
    "- Charts: supplied section-based ownership converted; timing, lanes, and sustains retained",
    f"- Camera events: {sum(record['details']['cameraEvents'] for record in records)} section focus/position/zoom events converted",
    f"- Stage metadata: {len(stage_configs)} Psych stage JSON files converted with character and camera coordinates",
    f"- Story weeks: {len([week for week in weeks if week['songs']])}",
    f"- Visuals: {len(stage_images)} stage composites, {len(character_dirs)} characters, {animation_frame_count} animation frames, and {len(icon_paths)} health icons",
    f"- Note style: {len(note_images)} PNG frames extracted from the supplied Psych NOTE_assets atlas; Psych's default RGB shader palette was baked into colored frames",
    f"- Placeholder/fallback poses: {fallback_pose_count} unavailable sing poses reuse that character's imported idle frame",
    "- Validation: generated paths, charts, ownership fields, week references, and audio headers are checked by tools/validate_content.py",
    "",
    "## Converted",
    "",
]
report += [f"- `{song_id}` — {title}; {player_notes} player notes; {opponent_notes} opponent notes; {size} audio bytes"
           for song_id, title, player_notes, opponent_notes, size in converted]
report += ["", "## Skipped", ""]
report += [f"- `{song_id}` — {reason}" for song_id, reason in skipped] or ["- None"]
report += ["", "## Errors", ""]
report += [f"- `{song_id}` — {reason}" for song_id, reason in errors] or ["- None"]
report += [
    "", "## Preserved but not executed", "",
    "Easy/Hard charts, Psych events, preload data, and auxiliary chart JSON are under",
    "`migration/source-unconverted/`. Jave Engine does not execute Psych event data.",
    "", "## Manual review", "",
    "Verify sync and ownership for charts using custom note/event behavior. Imported audio",
    "and charts remain subject to their original rights; this package does not grant permission",
    "to redistribute them.", "",
]
(args.jave_root / "PSYCH_IMPORT_REPORT.md").write_text("\n".join(report), encoding="utf-8")
print(f"done: {len(converted)} converted, {len(skipped)} skipped, {len(errors)} errors")
if errors:
    raise SystemExit(1)

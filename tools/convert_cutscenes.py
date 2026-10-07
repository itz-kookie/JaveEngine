"""Convert cutscene videos listed in data/cutscenes.json to Theora .ogv, the format the engine plays.

Each "before"/"after" video gets a sibling .ogv and the manifest entry is rewritten to point at it.
Re-running skips videos whose .ogv already exists.
Usage: python tools/convert_cutscenes.py [mod_root] [--dry-run] [--ffmpeg PATH]
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
SIDES = ("before", "after")
REQUIRED_ENCODERS = ("libtheora", "libvorbis")


def rejection(relative):
    # Same rule as the engine: manifest paths must stay inside the content root.
    normalized = relative.replace("\\", "/")
    if normalized.startswith("/") or ":" in normalized:
        return "absolute path rejected"
    if ".." in normalized.split("/"):
        return "path traversal rejected"
    return ""


def ffmpeg_problem(ffmpeg):
    if not ffmpeg:
        return "ffmpeg not found on PATH; install it or pass --ffmpeg PATH"
    try:
        listing = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        return f"cannot run {ffmpeg}: {exc}"
    names = {line.split()[1] for line in listing.splitlines() if len(line.split()) > 1}
    missing = [encoder for encoder in REQUIRED_ENCODERS if encoder not in names]
    if missing:
        return f"{ffmpeg} lacks required encoders: {', '.join(missing)} (build ffmpeg with --enable-libtheora --enable-libvorbis)"
    return ""


def convert(ffmpeg, source, target):
    partial = target.with_name(target.stem + ".partial.ogv")
    command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
               "-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis", "-q:a", "5", str(partial)]
    try:
        result = subprocess.run(command, capture_output=True, text=True)
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    if result.returncode != 0:
        partial.unlink(missing_ok=True)
        return result.stderr.strip() or f"ffmpeg exited with {result.returncode}"
    partial.replace(target)
    return ""


def plan(manifest, root):
    """Yield (song_id, side, relative, source, target) for every entry that still points at a non-.ogv file."""
    for song_id, entry in manifest.items():
        if not isinstance(entry, dict):
            continue
        for side in SIDES:
            relative = entry.get(side)
            if not isinstance(relative, str) or not relative:
                continue
            problem = rejection(relative)
            if problem:
                print(f"warning: {song_id}.{side}: {problem}: {relative}")
                continue
            source = root / relative.replace("\\", "/")
            if source.suffix.lower() == ".ogv":
                if not source.is_file():
                    print(f"warning: {song_id}.{side}: missing {relative}")
                continue
            yield song_id, side, relative, source, source.with_suffix(".ogv")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("content_root", type=Path, nargs="?", default=ROOT / "mods" / "fnf-original",
                        help="package folder holding data/cutscenes.json (default: mods/fnf-original)")
    parser.add_argument("--dry-run", action="store_true", help="print what would change without writing anything")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    args = parser.parse_args()

    manifest_path = args.content_root / "data" / "cutscenes.json"
    if not manifest_path.is_file():
        sys.exit(f"error: no manifest at {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        sys.exit(f"error: {manifest_path} must be a JSON object keyed by song id")

    jobs = list(plan(manifest, args.content_root))
    pending = [job for job in jobs if job[3].is_file() and not job[4].is_file()]
    if pending and not args.dry_run:
        problem = ffmpeg_problem(args.ffmpeg)
        if problem:
            sys.exit(f"error: {problem}")

    rewritten = converted = failed = 0
    for song_id, side, relative, source, target in jobs:
        new_relative = str(PurePosixPath(relative.replace("\\", "/")).with_suffix(".ogv"))
        if not target.is_file():
            if not source.is_file():
                print(f"warning: {song_id}.{side}: missing {relative}")
                continue
            if args.dry_run:
                print(f"would convert {relative} -> {new_relative}")
            else:
                error = convert(args.ffmpeg, source, target)
                if error:
                    print(f"error: {song_id}.{side}: {relative}: {error}")
                    failed += 1
                    continue
                print(f"converted {relative} -> {new_relative}")
            converted += 1
        manifest[song_id][side] = new_relative
        rewritten += 1

    if rewritten and not args.dry_run:
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    verb = "would rewrite" if args.dry_run else "rewrote"
    print(f"done: {converted} {'to convert' if args.dry_run else 'converted'}, {verb} {rewritten} entries, {failed} failed")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()

"""Make Ogg Vorbis copies of song WAVs for mobile builds of the Godot engine.

Every songs/*/Inst.wav and every .wav named by a song.json "audio" field (in the content root and its mods)
gets a sibling .ogg. The WAVs and manifests are left alone; mobile builds prefer the .ogg when it exists.
Re-running skips WAVs whose .ogg already exists.
Usage: python tools/convert_audio.py [content_root] [--dry-run] [--ffmpeg PATH]
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_ENCODERS = ("libvorbis",)


def rejection(relative):
    # Same rule as the engine: manifest paths must stay inside their package root.
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
        return f"{ffmpeg} lacks required encoders: {', '.join(missing)} (build ffmpeg with --enable-libvorbis)"
    return ""


def convert(ffmpeg, source, target):
    partial = target.with_name(target.stem + ".partial.ogg")
    command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
               "-vn", "-c:a", "libvorbis", "-q:a", "6", str(partial)]
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


def package_roots(content_root):
    yield content_root
    mods = content_root / "mods"
    if mods.is_dir():
        yield from sorted(path for path in mods.iterdir() if path.is_dir())


def manifest_audio(package_root, manifest_path):
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"warning: {manifest_path}: {exc}")
        return None
    audio = manifest.get("audio") if isinstance(manifest, dict) else None
    if not isinstance(audio, str) or not audio.lower().endswith(".wav"):
        return None
    problem = rejection(audio)
    if problem:
        print(f"warning: {manifest_path}: {problem}: {audio}")
        return None
    return package_root / audio.replace("\\", "/")


def wav_sources(content_root):
    """Sorted, de-duplicated WAVs to convert across the content root and its mods."""
    sources = set()
    for package_root in package_roots(content_root):
        songs = package_root / "songs"
        if not songs.is_dir():
            continue
        for song_dir in sorted(path for path in songs.iterdir() if path.is_dir()):
            inst = song_dir / "Inst.wav"
            if inst.is_file():
                sources.add(inst)
            manifest = song_dir / "song.json"
            audio = manifest_audio(package_root, manifest) if manifest.is_file() else None
            if audio is None:
                continue
            if audio.is_file():
                sources.add(audio)
            else:
                print(f"warning: {manifest}: missing {audio}")
    return sorted(sources)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("content_root", type=Path, nargs="?", default=ROOT / "godot" / "content",
                        help="folder holding songs/ and mods/ (default: godot/content)")
    parser.add_argument("--dry-run", action="store_true", help="print what would change without writing anything")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    args = parser.parse_args()

    if not args.content_root.is_dir():
        sys.exit(f"error: no content folder at {args.content_root}")

    jobs = [(source, source.with_suffix(".ogg")) for source in wav_sources(args.content_root)]
    pending = [(source, target) for source, target in jobs if not target.is_file()]
    if pending and not args.dry_run:
        problem = ffmpeg_problem(args.ffmpeg)
        if problem:
            sys.exit(f"error: {problem}")

    converted = failed = 0
    for source, target in pending:
        shown = source.relative_to(args.content_root)
        if args.dry_run:
            print(f"would convert {shown} -> {target.name}")
            converted += 1
            continue
        error = convert(args.ffmpeg, source, target)
        if error:
            print(f"error: {shown}: {error}")
            failed += 1
            continue
        print(f"converted {shown} -> {target.name}")
        converted += 1

    skipped = len(jobs) - len(pending)
    print(f"done: {converted} {'to convert' if args.dry_run else 'converted'}, {skipped} already converted, {failed} failed")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()

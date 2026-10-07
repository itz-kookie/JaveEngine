"""Build one content pack (a mod .zip) per Story Mode week from the locally imported library.

Each week in data/weeks.imported.json becomes a self-contained mod folder holding its songs, charts, stages,
character folders (plus any attached speaker), icons, stage images, note art, week banner and cutscene
videos, and is zipped to <out>/<week-id>.zip with the mod inside a top-level fnf-<week-id>/ folder.
Every mod folder is checked with tools/validate_jave_mod.py before it is zipped. Shared files such as the
bf and gf folders are copied into every pack that uses them. The packs hold user-supplied content: they are
for the user's own devices, not for redistribution.
Usage: python tools/make_content_packs.py [content_root] [--out DIR] [--weeks ID ...] [--dry-run]
"""
import argparse
import json
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import validate_jave_mod  # noqa: E402

WEEKS_FILE = "data/weeks.imported.json"
CUTSCENES_FILE = "data/cutscenes.json"
NOTES_DIR = "assets/imported/notes"
WEEK_ART = "assets/imported/menus/weeks/{}.png"
SKIPPED_WEEKS = {"demo"}
VISUAL_FIELDS = ("playerVisual", "opponentVisual", "girlfriendVisual")
FILE_FIELDS = ("stageImage", "playerIcon", "opponentIcon")


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def package_relative(relative):
    """The path as a clean package-relative POSIX path, or None when it leaves the package."""
    normalized = relative.replace("\\", "/")
    if not normalized or normalized.startswith("/") or ":" in normalized:
        return None
    parts = []
    for part in normalized.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                return None
            parts.pop()
        else:
            parts.append(part)
    return "/".join(parts) if parts else None


def inside(content_root, relative):
    """True when the path, with symlinks resolved, stays inside the content root."""
    return (content_root / relative).resolve().is_relative_to(content_root)


def preferred_audio(content_root, relative):
    # The engine plays the .ogg sibling of a .wav when it exists, so only that file is packed.
    if PurePosixPath(relative).suffix.lower() == ".wav":
        ogg = str(PurePosixPath(relative).with_suffix(".ogg"))
        if (content_root / ogg).is_file():
            return ogg
    return relative


def character_folders(content_root, visual):
    """The character folder plus the speaker folder its animation.json attaches."""
    folders = [visual]
    meta_path = content_root / visual / "animation.json"
    if meta_path.is_file():
        meta = load_json(meta_path)
        speaker = meta.get("speaker") if isinstance(meta, dict) else None
        if isinstance(speaker, dict) and isinstance(speaker.get("assetPath"), str):
            attached = package_relative(f"{visual}/{speaker['assetPath']}")
            if attached:
                folders.append(attached)
    return folders


class Pack:
    def __init__(self, content_root, week):
        self.content_root = content_root
        self.week = week
        self.files = set()
        self.folders = set()
        self.cutscenes = {}
        self.problems = []

    def add_file(self, relative, label):
        clean = package_relative(relative)
        if not relative:
            self.problems.append(f"{label}: no path given")
        elif clean is None or not inside(self.content_root, clean):
            self.problems.append(f"{label}: path leaves the package: {relative}")
        elif not (self.content_root / clean).is_file():
            self.problems.append(f"{label}: missing {clean}")
        else:
            self.files.add(clean)

    def add_folder(self, relative, label):
        clean = package_relative(relative)
        if clean is None or not inside(self.content_root, clean):
            self.problems.append(f"{label}: path leaves the package: {relative}")
        elif not (self.content_root / clean).is_dir():
            self.problems.append(f"{label}: missing folder {clean}")
        else:
            self.folders.add(clean)

    def collect(self, cutscene_manifest):
        week_id = self.week["id"]
        stages = set()
        for song_id in self.week["songs"]:
            if not isinstance(song_id, str) or package_relative(song_id) != song_id or "/" in song_id:
                self.problems.append(f"song id is not a plain folder name: {song_id!r}")
                continue
            manifest_path = f"songs/{song_id}/song.json"
            if not (self.content_root / manifest_path).is_file():
                self.problems.append(f"song {song_id}: missing {manifest_path}")
                continue
            try:
                song = load_json(self.content_root / manifest_path)
                if not isinstance(song, dict):
                    raise ValueError("not a JSON object")
                self.collect_song(song_id, song, stages, cutscene_manifest)
            except ValueError as exc:
                self.problems.append(f"song {song_id}: unreadable JSON: {exc}")
                continue
            self.files.add(manifest_path)
        for stage in sorted(stages):
            stage_path = f"data/stages/{stage}.json"
            if (self.content_root / stage_path).is_file():
                self.files.add(stage_path)
        if (self.content_root / NOTES_DIR).is_dir():
            self.folders.add(NOTES_DIR)
        art = WEEK_ART.format(week_id)
        if (self.content_root / art).is_file():
            self.files.add(art)

    def collect_song(self, song_id, song, stages, cutscene_manifest):
        self.add_file(preferred_audio(self.content_root, str(song.get("audio", ""))), f"{song_id} audio")
        self.add_file(str(song.get("chart", "")), f"{song_id} chart")
        stage = package_relative(str(song.get("stage", "stage")))
        if stage and "/" not in stage:
            stages.add(stage)
        for field in FILE_FIELDS:
            if song.get(field):
                self.add_file(str(song[field]), f"{song_id} {field}")
        for field in VISUAL_FIELDS:
            if song.get(field):
                for folder in character_folders(self.content_root, str(song[field])):
                    self.add_folder(folder, f"{song_id} {field}")
        entry = cutscene_manifest.get(song_id)
        if isinstance(entry, dict):
            self.cutscenes[song_id] = entry
            for video in entry.values():
                self.add_file(str(video), f"{song_id} cutscene")

    def sources(self):
        paths = set(self.files)
        for folder in self.folders:
            for path in (self.content_root / folder).rglob("*"):
                relative = path.relative_to(self.content_root).as_posix()
                if (path.is_file() and not path.name.startswith(".") and inside(self.content_root, relative)
                        and preferred_audio(self.content_root, relative) == relative):
                    paths.add(relative)
        return sorted(paths)

    def manifest(self, mod_id):
        return {
            "id": mod_id,
            "name": self.week.get("storyName") or self.week.get("name") or self.week["id"],
            "version": "1.0",
            "author": "User-supplied content",
            "description": f"{self.week.get('name', self.week['id'])} from the user's local FNF library. "
                           "User-supplied content; no redistribution rights granted by Jave Engine.",
            "enabled": True,
        }

    def write(self, mod_root, mod_id):
        for relative in self.sources():
            target = mod_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.content_root / relative, target)
        write_json(mod_root / "mod.json", self.manifest(mod_id))
        write_json(mod_root / "data/weeks.json", {"format": "jave-weeks-v1", "weeks": [self.week]})
        if self.cutscenes:
            write_json(mod_root / CUTSCENES_FILE, self.cutscenes)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_zip(mod_root, zip_path, folder):
    partial = zip_path.with_name(zip_path.name + ".partial")
    try:
        with zipfile.ZipFile(partial, "w", zipfile.ZIP_DEFLATED, allowZip64=False) as archive:
            for path in sorted(mod_root.rglob("*")):
                if path.is_file():
                    archive.write(path, f"{folder}/{path.relative_to(mod_root).as_posix()}")
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    partial.replace(zip_path)


def megabytes(size):
    return f"{size / (1024 * 1024):.1f} MiB"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("content_root", type=Path, nargs="?", default=ROOT,
                        help="folder holding songs/, data/ and assets/ (default: the repository root)")
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "packs", help="where the .zip files go")
    parser.add_argument("--weeks", nargs="+", metavar="ID", help="only these week ids")
    parser.add_argument("--dry-run", action="store_true", help="list each pack's contents without writing anything")
    args = parser.parse_args()

    content_root = args.content_root.resolve()
    weeks_path = content_root / WEEKS_FILE
    if not weeks_path.is_file():
        sys.exit(f"error: no {WEEKS_FILE} in {content_root}; import a library first")
    weeks = [week for week in load_json(weeks_path).get("weeks", [])
             if isinstance(week, dict) and isinstance(week.get("id"), str) and isinstance(week.get("songs"), list)
             and week["songs"] and week["id"] not in SKIPPED_WEEKS]
    if args.weeks:
        unknown = sorted(set(args.weeks) - {week["id"] for week in weeks})
        if unknown:
            sys.exit(f"error: unknown week ids: {', '.join(unknown)}")
        weeks = [week for week in weeks if week["id"] in args.weeks]
    cutscenes_path = content_root / CUTSCENES_FILE
    cutscene_manifest = load_json(cutscenes_path) if cutscenes_path.is_file() else {}
    if not isinstance(cutscene_manifest, dict):
        sys.exit(f"error: {CUTSCENES_FILE} must hold a JSON object")

    if not args.dry_run:
        args.out.mkdir(parents=True, exist_ok=True)
    failed = 0
    for week in weeks:
        mod_id = f"fnf-{week['id']}"
        pack = Pack(content_root, week)
        pack.collect(cutscene_manifest)
        if pack.problems:
            for problem in pack.problems:
                print(f"error: {week['id']}: {problem}")
            failed += 1
            continue
        sources = pack.sources()
        file_count = len(sources) + (3 if pack.cutscenes else 2)
        source_size = sum((content_root / relative).stat().st_size for relative in sources)
        if args.dry_run:
            print(f"would build {week['id']}.zip: {file_count} files, {megabytes(source_size)} before zipping, "
                  f"songs {', '.join(week['songs'])}")
            continue
        with tempfile.TemporaryDirectory(prefix="jave-pack-") as staging:
            mod_root = Path(staging) / mod_id
            pack.write(mod_root, mod_id)
            try:
                validate_jave_mod.validate(mod_root)
            except ValueError as exc:
                print(f"error: {week['id']}: validation failed: {exc}")
                failed += 1
                continue
            zip_path = args.out / f"{week['id']}.zip"
            write_zip(mod_root, zip_path, mod_id)
        print(f"built {zip_path.relative_to(ROOT) if zip_path.is_relative_to(ROOT) else zip_path}: "
              f"{megabytes(zip_path.stat().st_size)} ({file_count} files)")
    print(f"done: {len(weeks) - failed} packs, {failed} failed")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()

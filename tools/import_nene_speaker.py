"""Bake the user's Adobe Animate A-Bot atlas into Jave speaker frames.

Uses original sprite pieces and nested affine transforms, not replacement art.
Usage: python tools/import_nene_speaker.py <PsychEngine> <JaveEngine>
"""
import argparse
import json
import math
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image

IDENTITY = (1, 0, 0, 1, 0, 0)


def multiply(p, q):
    a, b, c, d, x, y = p
    e, f, g, h, u, v = q
    return (a*e+c*f, b*e+d*f, a*g+c*h, b*g+d*h, a*u+c*v+x, b*u+d*v+y)


def matrix(instance):
    m = instance.get("Matrix3D", {})
    return tuple(m.get(k, default) for k, default in
                 zip(("m00", "m01", "m10", "m11", "m30", "m31"), IDENTITY))


def span(timeline):
    return max((f["index"] + f["duration"] for l in timeline["LAYERS"] for f in l["Frames"]), default=1)


def bake(folder):
    source = json.loads((folder / "Animation.json").read_bytes())
    mapping = json.loads((folder / "spritemap1.json").read_bytes())
    sheet = Image.open(folder / mapping["meta"]["image"]).convert("RGBA")
    sprites = {}
    for entry in mapping["ATLAS"]["SPRITES"]:
        s = entry["SPRITE"]
        crop = sheet.crop((s["x"], s["y"], s["x"]+s["w"], s["y"]+s["h"]))
        if s.get("rotated", False):
            crop = crop.transpose(Image.Transpose.ROTATE_90)
        sprites[s["name"]] = crop
    symbols = {s["SYMBOL_name"]: s["TIMELINE"] for s in source["SYMBOL_DICTIONARY"]["Symbols"]}

    def leaves(timeline, time, transform=IDENTITY, depth=0):
        if depth > 32:
            raise ValueError("Recursive Animate symbol")
        result = []
        for layer in reversed(timeline["LAYERS"]):
            frame = next((f for f in layer["Frames"] if f["index"] <= time < f["index"]+f["duration"]), None)
            if not frame:
                continue
            for element in frame["elements"]:
                if "ATLAS_SPRITE_instance" in element:
                    instance = element["ATLAS_SPRITE_instance"]
                    result.append((sprites[instance["name"]], multiply(transform, matrix(instance))))
                elif "SYMBOL_Instance" in element:
                    instance = element["SYMBOL_Instance"]
                    child = symbols[instance["SYMBOL_name"]]
                    child_time = int(instance.get("firstFrame", 0))
                    loop = instance.get("loop", "loop").lower()
                    if loop not in ("single frame", "singleframe"):
                        child_time += time-frame["index"]
                    child_time = child_time % span(child) if loop == "loop" else min(child_time, span(child)-1)
                    result.extend(leaves(child, child_time, multiply(transform, matrix(instance)), depth+1))
                else:
                    raise ValueError(f"Unsupported Animate element: {list(element)}")
        return result

    timeline = source["ANIMATION"]["TIMELINE"]
    frames = [leaves(timeline, t) for t in range(span(timeline))]
    corners = []
    for frame in frames:
        for image, (a,b,c,d,x,y) in frame:
            corners.extend((a*u+c*v+x, b*u+d*v+y) for u,v in
                           ((0,0),(image.width,0),(0,image.height),(image.width,image.height)))
    left = math.floor(min(x for x,y in corners))
    top = math.floor(min(y for x,y in corners))
    width = math.ceil(max(x for x,y in corners))-left
    height = math.ceil(max(y for x,y in corners))-top
    output = []
    for frame in frames:
        canvas = Image.new("RGBA", (width, height))
        for image, (a,b,c,d,x,y) in frame:
            determinant = a*d-b*c
            if abs(determinant) < 1e-8:
                continue
            x -= left
            y -= top
            inverse = (d/determinant, -c/determinant, (c*y-d*x)/determinant,
                       -b/determinant, a/determinant, (b*x-a*y)/determinant)
            transformed = image.transform(canvas.size, Image.Transform.AFFINE, inverse,
                                          resample=Image.Resampling.BICUBIC)
            canvas.alpha_composite(transformed)
        output.append(canvas)
    return output, source.get("metadata", {}).get("framerate", 24)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("psych_root", type=Path)
    parser.add_argument("jave_root", type=Path)
    args = parser.parse_args()
    frames, fps = bake(args.psych_root / "assets/weekend1/images/abot/abotSystem")
    # The system atlas has a transparent screen: Psych draws these layers
    # separately. Bake the supplied screen and visualization pieces behind it.
    abot = args.psych_root / "assets/weekend1/images/abot"
    screen = Image.open(abot / "stereoBG.png").convert("RGBA").resize((455, 265))
    viz_sheet = Image.open(abot / "aBotViz.png").convert("RGBA")
    viz_frames = {node.attrib["name"]: node.attrib for node in ET.parse(abot / "aBotViz.xml").getroot()}
    eyes, _ = bake(abot / "systemEyes")
    for index, frame in enumerate(frames):
        background = Image.new("RGBA", frame.size)
        background.alpha_composite(screen, (180, 28))
        for band in range(1, 8):
            level = min(5, index // 3 + band % 2)
            source = viz_frames[f"viz{band}{level:04d}"]
            x, y, w, h = (int(source[key]) for key in ("x", "y", "width", "height"))
            bar = Image.new("RGBA", (int(source.get("frameWidth", w)), int(source.get("frameHeight", h))))
            bar.alpha_composite(viz_sheet.crop((x, y, x+w, y+h)),
                                (-int(source.get("frameX", 0)), -int(source.get("frameY", 0))))
            bar = bar.resize((53, 183))
            background.alpha_composite(bar, (210 + (band-1)*54, 88))
        background.alpha_composite(frame)
        background.alpha_composite(eyes[min(index, len(eyes)-1)].resize((85, 30)), (32, 252))
        frames[index] = background
    destination = args.jave_root / "assets/imported/characters/nene-large-speaker"
    (destination / "idle").mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames):
        frame.save(destination / "idle" / f"frame_{index:03d}.png")
    frames[0].save(destination / "idle.png")
    metadata = {"version": 2, "scale": 1, "flipX": False,
                "idle": {"frames": len(frames), "fps": fps, "loop": False,
                         "width": frames[0].width, "height": frames[0].height}}
    (destination / "animation.json").write_text(json.dumps(metadata, indent=2)+"\n")
    character = args.jave_root / "assets/imported/characters/nene/animation.json"
    nene = json.loads(character.read_bytes())
    nene["speaker"] = {"assetPath": "../nene-large-speaker", "overlap": 140}
    character.write_text(json.dumps(nene, indent=2)+"\n")
    print(f"A-Bot speaker: {len(frames)} frames, {frames[0].size}, {fps} FPS")


if __name__ == "__main__":
    main()

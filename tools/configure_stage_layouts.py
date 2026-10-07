"""Set presentation anchors for the user's baked 1280x720 stage images."""
import json
from pathlib import Path
from PIL import Image, ImageOps
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
# Center X, floor Y, character scale: opponent, girlfriend, player.
LAYOUTS = {
    "stage": ((380,590,.9),(730,570,.85),(920,605,.95)),
    "spooky": ((355,615,.9),(740,590,.85),(925,635,.95)),
    "philly": ((365,625,.95),(720,590,.85),(940,630,.95)),
    "limo": ((390,555,.8),(760,570,.8),(930,515,.85)),
    "mall": ((400,645,.85),(735,620,.8),(935,650,.95)),
    "mallEvil": ((365,630,.9),(720,600,.8),(950,640,.95)),
    "school": ((390,600,.9),(735,600,.85),(920,635,.95)),
    "schoolEvil": ((430,615,.9),(745,595,.85),(930,630,.95)),
    "tank": ((405,620,.9),(745,555,.8),(905,625,.95)),
    "phillyStreets": ((400,600,.95),(735,550,1),(945,635,.95)),
    "phillyBlazin": ((435,635,.85),(790,540,.85),(930,630,.95)),
}


def configure(package):
    songs = [json.loads(p.read_bytes()) for p in (package/'songs').glob('*/song.json')]
    stage_dir = package/'data/stages'
    stage_dir.mkdir(parents=True, exist_ok=True)
    for stage_id in sorted({s.get('stage') for s in songs} & LAYOUTS.keys()):
        file = stage_dir/f'{stage_id}.json'
        song = next(s for s in songs if s.get('stage') == stage_id)
        data = json.loads(file.read_bytes()) if file.exists() else {
            'id': stage_id, 'boyfriend': song.get('boyfriendPosition',[770,100]),
            'girlfriend': song.get('girlfriendPosition',[400,130]),
            'opponent': song.get('opponentPosition',[100,100]),
            'defaultZoom': song.get('defaultZoom',.9), 'hideGirlfriend': song.get('hideGirlfriend',False)}
        placements = {}
        for role, source_key, (x,y,scale) in zip(('opponent','girlfriend','player'),
                ('opponent','girlfriend','boyfriend'), LAYOUTS[stage_id]):
            placements[role] = {'anchor':[x,y], 'sourceAnchor':data[source_key], 'scale':scale}
        data['layout'] = {'revision':2,'width':1280,'height':720,'positionScale':.5,'placements':placements}
        file.write_text(json.dumps(data,indent=2)+'\n')
        print('Configured',stage_id)


def add_limo_floor(psych_root, package):
    folder = psych_root/'assets/week4/images/limo'
    destination = package/'assets/imported/stages/limo.png'
    if not (folder/'limoSunset.png').is_file():
        raise FileNotFoundError(f"Missing Psych Engine limo assets: {folder}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas = ImageOps.fit(Image.open(folder/'limoSunset.png').convert('RGBA'), (1280,720))
    for asset, bottom, target_width in (('bgLimo',610,1280),('limoDrive',735,1460)):
        frame = next(iter(ET.parse(folder/f'{asset}.xml').getroot())).attrib
        x,y,w,h = (int(frame[k]) for k in ('x','y','width','height'))
        sheet = Image.open(folder/f'{asset}.png').convert('RGBA')
        crop = sheet.crop((x,y,x+w,y+h))
        if frame.get('rotated') == 'true': crop = crop.transpose(Image.Transpose.ROTATE_90)
        image = Image.new('RGBA',(int(frame.get('frameWidth',crop.width)),int(frame.get('frameHeight',crop.height))))
        image.alpha_composite(crop,(-int(frame.get('frameX',0)),-int(frame.get('frameY',0))))
        image = image.resize((target_width, round(image.height*target_width/image.width)))
        canvas.alpha_composite(image,((1280-target_width)//2,bottom-image.height))
    canvas.save(destination)


def target_packages(mods_root):
    packages = []
    for path in sorted(mods_root.glob('*')):
        manifest_path = path/'mod.json'
        if not path.is_dir() or not (path/'songs').is_dir() or not manifest_path.is_file():
            continue
        manifest = json.loads(manifest_path.read_bytes())
        if str(manifest.get('id', '')).startswith('fnf-') and not manifest.get('sourceOnly', False):
            packages.append(path)
    return packages


def has_limo_stage(package):
    songs = [json.loads(p.read_bytes()) for p in (package/'songs').glob('*/song.json')]
    return any(song.get('stage') == 'limo' for song in songs)


if __name__ == '__main__':
    import sys
    packages = target_packages(ROOT/'mods')
    for package in packages:
        configure(package)
    if len(sys.argv)>1:
        for package in packages:
            if has_limo_stage(package):
                add_limo_floor(Path(sys.argv[1]), package)

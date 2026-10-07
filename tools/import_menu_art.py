"""Import the user's menu PNG/XML art without importing engine code."""
import argparse
import json
import re
from pathlib import Path
from PIL import Image, ImageOps


def entries(file):
    # alphabet.xml contains unescaped punctuation in names; read attributes
    # directly instead of accepting external XML entities or dropping glyphs.
    return [dict(re.findall(r'(\w+)="([^"]*)"', tag))
            for tag in re.findall(r'<SubTexture\s+(.*?)/>', file.read_text(encoding='utf-8-sig'), re.S)]


def crop(sheet, frame):
    x,y,w,h = (int(frame[k]) for k in ('x','y','width','height'))
    part = sheet.crop((x,y,x+w,y+h))
    if frame.get('rotated') == 'true': part = part.transpose(Image.Transpose.ROTATE_90)
    canvas = Image.new('RGBA',(int(frame.get('frameWidth',part.width)),int(frame.get('frameHeight',part.height))))
    canvas.alpha_composite(part,(-int(frame.get('frameX',0)),-int(frame.get('frameY',0))))
    return canvas


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('psych_root',type=Path)
    parser.add_argument('jave_root',type=Path)
    args=parser.parse_args()
    source=args.psych_root/'assets/shared/images'
    mod_root=args.jave_root/'mods'/'fnf-menus'
    mod_root.mkdir(parents=True,exist_ok=True)
    manifest=mod_root/'mod.json'
    if not manifest.is_file():
        manifest.write_text(json.dumps({
            'id':'fnf-menus','name':'FNF Menus','version':'1.0.0',
            'author':'User-supplied content','description':'Locally imported menu artwork.',
            'enabled':True,'order':-10,
        },indent=2)+'\n')
    output=mod_root/'assets/imported/menus'
    output.mkdir(parents=True,exist_ok=True)
    for name in ('menuBG','menuBGMagenta','menuBGBlue'):
        Image.open(source/f'{name}.png').convert('RGBA').save(output/f'{name}.png')
    gray=ImageOps.grayscale(Image.open(source/'menuDesat.png'))
    ImageOps.colorize(gray,'#5b327f','#d2a5e8').save(output/'menuPurple.png')
    ImageOps.colorize(gray,'#4260a0','#d8f3ff').save(output/'menuCool.png')
    for button in ('story_mode','freeplay','mods','options','credits'):
        frames=entries(source/'mainmenu'/f'menu_{button}.xml')
        prefixes=sorted({re.sub(r'\d+$','',f['name']) for f in frames})
        print(button,prefixes)
        idle=next((p for p in prefixes if 'idle' in p.lower() or 'basic' in p.lower()),prefixes[0])
        selected=next((p for p in prefixes if 'selected' in p.lower() or 'white' in p.lower()),next(p for p in prefixes if p!=idle))
        sheet=Image.open(source/'mainmenu'/f'menu_{button}.png').convert('RGBA')
        meta={}
        for pose,prefix in (('idle',idle),('left',selected)):
            matches=sorted((f for f in frames if re.sub(r'\d+$','',f['name'])==prefix),key=lambda f:f['name'])
            images=[crop(sheet,f) for f in matches]
            w=max(im.width for im in images); h=max(im.height for im in images)
            dest=output/'buttons'/button/pose
            dest.mkdir(parents=True,exist_ok=True)
            for i,im in enumerate(images):
                canvas=Image.new('RGBA',(w,h)); canvas.alpha_composite(im,((w-im.width)//2,(h-im.height)//2))
                canvas.save(dest/f'frame_{i:03d}.png')
            meta[pose]={'frames':len(images),'fps':24,'loop':True,'width':w,'height':h}
        (output/'buttons'/button/'animation.json').write_text(json.dumps(meta,indent=2)+'\n')
    alphabet=entries(source/'alphabet.xml')
    sheet=Image.open(source/'alphabet.png').convert('RGBA')
    glyphs={}
    glyph_dir=output/'alphabet'; glyph_dir.mkdir(exist_ok=True)
    for character in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-+.:!?/':
        choices=[f for f in alphabet if f['name'].lower().startswith(character.lower()+' bold')]
        if not choices:
            print('Glyph unavailable:',character); continue
        image=crop(sheet,sorted(choices,key=lambda f:f['name'])[0])
        file=f'{ord(character):02x}.png'; image.save(glyph_dir/file)
        glyphs[character]={'file':file,'width':image.width,'height':image.height}
    (glyph_dir/'glyphs.json').write_text(json.dumps(glyphs,indent=2)+'\n')
    weeks=output/'weeks'; weeks.mkdir(exist_ok=True)
    for file in (source/'storymenu').glob('*.png'):
        Image.open(file).convert('RGBA').save(weeks/file.name)
    (output/'IMPORT_NOTICE.txt').write_text('Menu artwork imported from the user-supplied PsychEngine installation. Original rights apply; no redistribution permission is granted. Jave implementation and branding remain independent.\n')
    print('Menu assets imported to',output)


if __name__=='__main__': main()

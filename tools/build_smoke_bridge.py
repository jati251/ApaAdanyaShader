"""Tag only campfire particle sprites for the shader/Minecraft switch.

Local derivative assets are read from the installed client/selected packs.
Visible pixels and particle simulation are preserved. Run with Pillow.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile
from PIL import Image

TAG=(0,255,0,1)
PACK_NAME='AA-Volumetric-Smoke-Bridge.zip'


def build(instance,client,enable=False):
    instance=Path(instance);client=Path(client)
    options=instance/'options.txt';lines=options.read_text().splitlines()
    selected=json.loads(next(line[14:] for line in lines if line.startswith('resourcePacks:')))
    readers=[zipfile.ZipFile(client)]
    for entry in selected:
        if not entry.startswith('file/') or entry=='file/'+PACK_NAME:continue
        p=instance/'resourcepacks'/entry[5:]
        if p.is_dir():readers.append(p)
        elif p.is_file():readers.append(zipfile.ZipFile(p))

    def asset(name):
        for reader in reversed(readers):
            if isinstance(reader,Path):
                p=reader/name
                if p.is_file():return p.read_bytes()
            elif name in reader.namelist():return reader.read(name)
        raise FileNotFoundError(name)

    version=json.loads(readers[0].read('version.json'))['pack_version']
    fmt=[version['resource_major'],version['resource_minor']]
    out=instance/'resourcepacks'/PACK_NAME;out.parent.mkdir(parents=True,exist_ok=True)
    # Never overwrite a selected third-party pack or any original texture.
    files={};manifest=[]
    for kind in ('campfire_cosy_smoke','campfire_signal_smoke'):
        definition=json.loads(asset('assets/minecraft/particles/'+kind+'.json'))
        replacement=[]
        for identifier in definition['textures']:
            namespace,name=identifier.split(':',1) if ':' in identifier else ('minecraft',identifier)
            original=asset(f'assets/{namespace}/textures/particle/{name}.png')
            digest=hashlib.sha256(original).hexdigest()[:16]
            new_id='apaadanya:smoke_bridge/'+digest
            replacement.append(new_id)
            target='assets/apaadanya/textures/particle/smoke_bridge/'+digest+'.png'
            if target in files:continue
            image=Image.open(io.BytesIO(original)).convert('RGBA');before=image.copy();w,h=image.size
            corners=[(x,y) for x in (0,1,w-2,w-1) for y in (0,1,h-2,h-1)]
            padded=False
            if any(image.getpixel(p)[3]!=0 for p in corners):
                padded=True
                canvas=Image.new('RGBA',(w+4,h+4));canvas.paste(image,(2,2));image=canvas;w,h=image.size
                corners=[(x,y) for x in (0,1,w-2,w-1) for y in (0,1,h-2,h-1)]
            for p in corners:image.putpixel(p,TAG)
            if not padded:
                a,b=before.tobytes(),image.tobytes()
                assert all(a[i:i+4]==b[i:i+4] or a[i+3]==0 and b[i+3]<=1 for i in range(0,len(a),4))
            buffer=io.BytesIO();image.save(buffer,format='PNG');files[target]=buffer.getvalue()
            manifest.append(dict(original=identifier,marker=new_id,size=[w,h],padded=padded))
        definition['textures']=replacement
        files['assets/minecraft/particles/'+kind+'.json']=(json.dumps(definition,indent=2)+'\n').encode()
    files['pack.mcmeta']=(json.dumps({'pack':{'description':'AA Smoke Bridge | campfire shader/vanilla switch','min_format':fmt,'max_format':fmt}},indent=2)+'\n').encode()
    files['README.txt']=b'Keep this small pack above other packs. Shader option: Particles > Smoke Source.\nShader hides tagged campfire billboards; Minecraft mode or unsupported hardware restores them.\nOther particles and source packs are untouched. Rebuild after changing a pack which edits campfire smoke.\n'
    files['smoke-bridge-manifest.json']=(json.dumps(dict(client_version=version,selected_packs=selected,sprites=manifest),indent=2)+'\n').encode()
    with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
        for name,data in files.items():z.writestr(name,data)
    for reader in readers:
        if isinstance(reader,zipfile.ZipFile):reader.close()
    if enable:
        selected=[x for x in selected if x!='file/'+PACK_NAME]+['file/'+PACK_NAME]
        options.write_text('\n'.join('resourcePacks:'+json.dumps(selected,separators=(',',':')) if line.startswith('resourcePacks:') else line for line in lines)+'\n')
    print(f'PASS: {len(manifest)} tagged sprites; campfire-only JSON; {out}; enabled={enable}')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--instance',type=Path,default=Path(__file__).resolve().parents[3])
    parser.add_argument('--client',type=Path,required=True)
    parser.add_argument('--enable',action='store_true')
    args=parser.parse_args();build(args.instance,args.client,args.enable)

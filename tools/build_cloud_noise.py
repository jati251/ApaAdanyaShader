"""Bake the shader's hash13 lattice on the native GPU (GLSL 330).

The shipped raw R16F texture accepts float32 upload data. It is 512 KiB on the
GPU, repeats at 64 cells and uses the same cubic-interpolated value-noise model.
Run this only when intentionally regenerating the shipped asset.
"""
import array
import pathlib
import sys
from quality_checks import Fixture


def setup():
    validator=pathlib.Path(__file__).with_name('validate.py')
    api={'__file__':str(validator)}
    exec(compile(validator.read_text().split('\ntry:\n    total = 0',1)[0],str(validator),'exec'),api)
    return api


def main():
    api=setup()
    try:
        f=Fixture(api,64,4096)
        values=dict(api['resolve']('LOW'),UPSCALE_QUALITY='0')
        prefix=api['source'](api['ROOT']/'prepare.fsh',dict(values,__compat_fixture=True),False).split('in vec2 texcoord;')[0]
        fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){ivec2 q=ivec2(gl_FragCoord.xy);color=vec4(hash13(vec3(q.x,q.y%64,q.y/64)),0,0,1);}
'''
        program=f.program('prepare.fsh',values,fragment=fragment)
        target=f.texture(None,0)
        pixels=f.render(program,[target],{'viewWidth':64.,'viewHeight':4096.})
        data=array.array('f',pixels[::4])
        if sys.byteorder!='little':data.byteswap()
        out=api['ROOT']/'textures/cloud_noise.bin'
        out.parent.mkdir(exist_ok=True)
        out.write_bytes(data.tobytes())
        print(f'PASS: {len(data)} GPU lattice values -> {out} ({out.stat().st_size} bytes)',flush=True)
        f.close()
    finally:
        api['driver'].close()


if __name__=='__main__':main()

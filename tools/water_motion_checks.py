"""Perspective-plane rendering of the real water optical path during camera motion."""
import math
from quality_checks import Fixture


def run(api):
    f=Fixture(api,320,180)
    values=dict(api['resolve']('REALISM'),WATER_OCTAVES='7',WATER_WAVES='0.85',
                WATER_REFRACTION=False,WATER_CAUSTICS=False,SHADOWS=False,CLOUD_SHADOWS=False)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    pixels=f.w*f.h
    f.texture([.08,.12,.10,1]*pixels,0)
    f.texture([1,1,1,1]*pixels,1)
    f.texture([1,0,0,1]*pixels,2)
    sky=[]
    for y in range(64):
        elevation=(y+.5)/64*math.pi-math.pi/2
        for x in range(128):
            azimuth=(x+.5)/128*math.tau-math.pi
            cloud=max(0,math.sin(azimuth*3+.4)*math.cos(elevation*12)-.05)*.55
            haze=math.exp(-abs(elevation)*4)
            sky.extend((.15+.22*haze+cloud,.25+.22*haze+cloud,.4+.16*haze+cloud,1))
    f.texture(sky,3,128,64)
    target=f.texture(None,4); material=f.texture(None,5)
    code=api['source'](api['ROOT']/'gbuffers_water.fsh',values,False)
    code=code.replace('in vec2 texcoord,lmcoord;','in vec2 texcoord;\n#define lmcoord vec2(0,1)')
    code=code.replace('in vec4 glcolor;','#define glcolor vec4(1)')
    code=code.replace('in vec3 viewNormal,viewPos,worldPos;', '''
vec3 testRay(vec2 uv) { return vec3((uv.x-.5)*3.555556,(uv.y-.5)*2.0-.6,-1); }
vec3 testPlane(vec2 uv) {
    vec3 ray=testRay(uv);
    return ray*(cameraPosition.y/max(-ray.y,.002));
}
#define viewNormal vec3(0,1,0)
#define viewPos testPlane(gl_FragCoord.xy/vec2(viewWidth,viewHeight))
#define worldPos (viewPos+cameraPosition)
''')
    code=code.replace('in vec4 tangent;','').replace('flat in float materialId;','const float materialId=1003;')
    # Derivatives are already evaluated before this synthetic plane's horizon.
    code=code.replace('    materialData=vec4(WATER_ROUGHNESS',
        '    if(testRay(gl_FragCoord.xy/vec2(viewWidth,viewHeight)).y>=0.0) {color=vec4(0,0,0,1); return;}\n    materialData=vec4(WATER_ROUGHNESS')
    uniforms=dict(viewWidth=float(f.w),viewHeight=float(f.h),gbufferModelView=identity,
        gbufferModelViewInverse=identity,gbufferProjection=identity,gbufferProjectionInverse=identity,
        sunPosition=(0.,1.,0.),shadowLightPosition=(0.,-1.,0.),frameTimeCounter=12.,
        frameTime=1/60,near=.05,far=256.,gtexture=1,colortex6=0,depthtex1=2,colortex7=3,isEyeInWater=0)
    program=f.program('composite7.fsh',values,fragment=code)
    frames={}
    for rain in (0.,1.):
        for height in (.15,1.62,2.87):
            current=f.render(program,[target,material],dict(uniforms,rainStrength=rain,cameraPosition=(0.,height,0.)))
            nearby=f.render(program,[target,material],dict(uniforms,rainStrength=rain,cameraPosition=(0.,height+.002,0.)))
            difference=sum(abs(a-b) for a,b in zip(current,nearby))/len(current)
            assert difference<.006, f'Perspective water changed abruptly over a 2mm camera step: {difference:.6f}'
            frames[rain,height]=current
    # Missed screen rays must reproduce the identical filtered environment,
    # rather than change the lobe when the SSR option is enabled.
    no_ssr=dict(values,SSR=False)
    # The prepared test geometry and main body are identical; only remove SSR.
    no_ssr_code=code.replace('#define SSR\n','// #define SSR\n')
    program=f.program('composite7.fsh',no_ssr,fragment=no_ssr_code)
    miss=f.render(program,[target,material],dict(uniforms,rainStrength=0.,cameraPosition=(0.,1.62,0.)))
    error=max(abs(a-b) for a,b in zip(miss,frames[0.,1.62]))
    assert error<.0002, f'Missed SSR rays changed environment reflection: {error:.6f}'
    prefix=code[:code.rfind('void main(){')]
    pole=prefix+"""void main(){
        float h=.05+texcoord.y*.9;
        vec3 a=normalize(vec3(sqrt(1-h*h),h,-.00001));
        vec3 b=normalize(vec3(sqrt(1-h*h),h,.00001));
        color=vec4(abs(waterEnvironmentReflection(a,.08)-waterEnvironmentReflection(b,.08)),1);
    }"""
    pole_program=f.program('composite7.fsh',values,fragment=pole)
    discontinuity=f.render(pole_program,[target,material],uniforms)
    assert max(discontinuity[0::4]+discontinuity[1::4]+discontinuity[2::4])<.0002, 'Reflection cone has an axis-switch discontinuity'
    ssr_program=f.program('composite7.fsh',values,fragment=code)
    for angle in (-.3,.3):
        cs,sn=math.cos(angle),math.sin(angle)
        model=[cs,0,-sn,0,0,1,0,0,sn,0,cs,0,0,0,0,1]
        inverse=[cs,0,sn,0,0,1,0,0,-sn,0,cs,0,0,0,0,1]
        rotated=dict(uniforms,gbufferModelView=model,gbufferModelViewInverse=inverse,
            rainStrength=0.,cameraPosition=(0.,1.62,0.))
        traced=f.render(ssr_program,[target,material],rotated)
        fallback=f.render(program,[target,material],rotated)
        error=max(abs(a-b) for a,b in zip(traced,fallback))
        assert error<.0002, f'Rotating camera changed SSR-miss lobe orientation: {error:.6f}'
    print('PASS: GPU perspective water remains continuous over small camera steps at shoreline/jump heights, dry/rainy',flush=True)
    print('PASS: GPU primary-ray SSR misses match filtered environment fallback',flush=True)
    if '--write-previews' in api['sys'].argv:
        from PIL import Image
        out=api['ROOT'].parent/'artifacts'
        out.mkdir(exist_ok=True)
        for (rain,height),data in frames.items():
            rgb=[]
            for y in reversed(range(f.h)):
                for x in range(f.w):
                    pixel=data[(y*f.w+x)*4:(y*f.w+x)*4+3]
                    rgb.extend(int(max(0,min(1,v/(1+v)))**(1/2.2)*255) for v in pixel)
            Image.frombytes('RGB',(f.w,f.h),bytes(rgb)).save(out/f'water-plane-rain-{int(rain)}-height-{height:.2f}.png')
    f.close()

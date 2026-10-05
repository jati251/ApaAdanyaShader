"""Render the real water fragment with alternating fluid-quad light values."""
import ctypes as c
from quality_checks import Fixture


def run(api):
    f=Fixture(api,64,32)
    values=dict(api['resolve']('REALISM'),SSR=False,WATER_REFRACTION=False,
                WATER_CAUSTICS=False,SHADOWS=False)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    pixels=f.w*f.h
    f.texture([0.2,0.4,0.6,1]*pixels,0)
    f.texture([1,1,1,1]*pixels,1)
    f.texture([1,0,0,1]*pixels,2)
    f.texture([0.3,0.4,0.6,1]*pixels,3)
    target=f.texture(None,4); material=f.texture(None,5)
    outputs={}
    for checker in (False,True):
        code=api['source'](api['ROOT']/'gbuffers_water.fsh',values,False)
        light='mix(0.15,0.95,step(0.5,fract(gl_FragCoord.x/8.0)))' if checker else '0.95'
        code=code.replace('in vec2 texcoord,lmcoord;',
            'in vec2 texcoord;\n#define lmcoord vec2(0.0,'+light+')')
        code=code.replace('in vec4 glcolor;','#define glcolor vec4(1.0)')
        code=code.replace('in vec3 viewNormal,viewPos,worldPos;',
            '#define viewNormal vec3(0.0,1.0,0.0)\n'
            '#define viewPos vec3(0.0,-4.0,-4.0)\n'
            '#define worldPos vec3(gl_FragCoord.x*0.1,64.0,gl_FragCoord.y*0.1)')
        code=code.replace('in vec4 tangent;','')
        code=code.replace('flat in float materialId;','const float materialId=1003.0;')
        p=f.program('composite6.fsh',values,fragment=code)
        f.call('glUseProgram',None,[c.c_uint],p)
        loc=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'eyeBrightnessSmooth')
        f.call('glUniform2i',None,[c.c_int,c.c_int,c.c_int],loc,200,200)
        u=dict(viewWidth=float(f.w),viewHeight=float(f.h),gbufferModelView=identity,
            gbufferModelViewInverse=identity,gbufferProjection=identity,
            gbufferProjectionInverse=identity,cameraPosition=(0.,60.,0.),
            sunPosition=(0.,1.,0.),shadowLightPosition=(0.,-1.,0.),
            frameTimeCounter=3.,gtexture=1,colortex6=0,depthtex1=2,colortex7=3)
        outputs[checker]=f.render(p,[target,material],dict(u,isEyeInWater=1))
    assert max(abs(a-b) for a,b in zip(outputs[False],outputs[True]))<0.0001, \
        'Fluid-quad light values produced a checkerboard on the underwater surface'
    print('PASS: GPU real water underside remains continuous across fluid lightmap tiles',flush=True)

    # Use the actual water helper with a shoreline crossing the water plane.
    code=code.replace('#define viewPos vec3(0.0,-4.0,-4.0)',
                      '#define viewPos vec3(0.0,0.0,-4.0)')
    prefix=code[:code.rfind('void main(){')]
    fragment=prefix+'''void main(){
color=vec4(float(waterReflectionAboveSurface(texcoord,false)),
           float(waterReflectionAboveSurface(texcoord,true)),0,1);}
'''
    p=f.program('composite6.fsh',values,fragment=fragment)
    f.texture([0.5,0,0,1]*pixels,2)
    out=f.render(p,[target,material],u)
    for y in range(f.h):
        for x in range(f.w):
            index=(y*f.w+x)*4
            expected=1.0 if (y+0.5)/f.h*2-1>=-0.02 else 0.0
            assert abs(out[index]-expected)<0.0001, 'Water SSR reflected a submerged surface from above'
            assert out[index+1]>0.999, 'Underwater reflection was incorrectly rejected'
    print('PASS: GPU shoreline reflections reject submerged geometry above water',flush=True)

    scene=[]; depths=[]
    for y in range(f.h):
        for x in range(f.w):
            bright=(x+y)%2
            scene.extend((float(bright),)*3+(1,))
            depths.extend((1.0 if bright else 0.5,0,0,1))
    f.texture(scene,0); f.texture(depths,2)
    fragment=prefix+'void main(){color=vec4(waterReflectionSample(texcoord,0.14),1);}'
    p=f.program('composite6.fsh',values,fragment=fragment)
    out=f.render(p,[target,material],u)
    dark=[out[(y*f.w+x)*4] for y in range(f.h//2+3,f.h-3)
          for x in range(3,f.w-3) if (x+y)%2==0]
    assert min(dark)>0.15 and max(dark)<0.5, 'Rough reflection did not integrate sky/foliage edge coverage'
    print('PASS: GPU rough water reflections filter high-contrast sky/foliage edges',flush=True)
    f.close()

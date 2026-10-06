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
    f.texture([0.3,0.4,0.6,1]*(128*64),3,128,64)
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
    fragment=prefix+'''void main(){
        vec2 slope=vec2(0.18,-0.12);
        vec3 a=waterSurfaceNormal(normalize(vec3(0.12,1,0)),slope);
        vec3 b=waterSurfaceNormal(normalize(vec3(-0.12,1,0)),slope);
        vec3 side=waterSurfaceNormal(vec3(1,0,0),slope);
        color=vec4(length(a-b),length(side-vec3(1,0,0)),length(a),1);
    }'''
    p=f.program('composite6.fsh',values,fragment=fragment)
    out=f.render(p,[target,material],u)
    assert max(out[0::4])<1e-6, 'Fluid triangles have different wave planes'
    assert max(out[1::4])<1e-6, 'Waterfall normals were deformed by top-surface waves'
    assert max(abs(v-1) for v in out[2::4])<1e-6, 'Water surface normal is not normalized'
    print('PASS: GPU water top normals match across fluid triangles; waterfall normals preserved',flush=True)
    normal_fragment=code.replace('#define viewPos vec3(0.0,0.0,-4.0)',
        'uniform vec3 testViewPosition;\n#define viewPos testViewPosition')
    normal_fragment=normal_fragment.replace('    bool validBehind;',
        '    color=vec4(worldDirection(N)*0.5+0.5,1.0); return;\n    bool validBehind;')
    f.texture([1,1,1,1]*pixels,1)
    p=f.program('composite6.fsh',values,fragment=normal_fragment)
    low=f.render(p,[target,material],dict(u,isEyeInWater=0,testViewPosition=(0.,-0.05,-4.)))
    jumped=f.render(p,[target,material],dict(u,isEyeInWater=0,testViewPosition=(0.,-1.8,-4.)))
    difference=max(abs(a-b) for a,b in zip(low,jumped))
    assert difference<1e-5, f'Jumping changed a fixed world-space wave normal: {difference:.6f}'
    approached=f.render(p,[target,material],dict(u,isEyeInWater=0,testViewPosition=(0.,-0.2,-1.)))
    assert max(abs(a-b) for a,b in zip(low,approached))<1e-5, 'Approaching changed a fixed world-space wave normal'
    print('PASS: GPU actual water normals stay anchored during a camera jump at fixed wave time',flush=True)

    # Exercise the complete optical path at a shoreline grazing angle,
    # including wave facets facing away from the camera.
    optics=api['source'](api['ROOT']/'gbuffers_water.fsh',values,False)
    optics=optics.replace('in vec2 texcoord,lmcoord;', 'in vec2 texcoord;\n#define lmcoord vec2(0,1)')
    optics=optics.replace('in vec4 glcolor;','#define glcolor vec4(1)')
    optics=optics.replace('in vec3 viewNormal,viewPos,worldPos;',
        '#define viewNormal vec3(0,1,0)\n#define viewPos vec3(0,-0.05,-8)\n'
        '#define worldPos vec3(gl_FragCoord.x*0.5,64,gl_FragCoord.y*0.5)')
    optics=optics.replace('in vec4 tangent;','').replace('flat in float materialId;','const float materialId=1003;')
    optics=optics.replace('vec3 waterColor = waterBodyColor(thickness,lmcoord.y);','vec3 waterColor = vec3(0);')
    optics=optics.replace('if(!underwater) transmitted += waveSSS;','')
    f.texture([0,0,0,1]*pixels,0)
    f.texture([1,0,0,1]*pixels,2)
    f.texture([1,1,1,1]*(128*64),3,128,64)
    diagnostic=optics.replace('color = vec4(max(result, vec3(0.0)), 1.0);',
        'color = vec4(abs(R-reflect(-V,N)),1);')
    p=f.program('composite6.fsh',values,fragment=diagnostic)
    out=f.render(p,[target,material],dict(u,isEyeInWater=0))
    error=max(out[0::4]+out[1::4]+out[2::4])
    assert error<1e-5, f'Water reflection ray collapses onto a fixed horizon: {error:.6f}'
    diagnostic=optics.replace('color = vec4(max(result, vec3(0.0)), 1.0);',
        'color = vec4(max(result,vec3(0)),dot(N,V));')
    p=f.program('composite6.fsh',values,fragment=diagnostic)
    out=f.render(p,[target,material],dict(u,isEyeInWater=0))
    backfaces=[out[i] for i in range(0,len(out),4) if out[i+3]<-0.01]
    assert backfaces and max(backfaces)<1e-5, 'Back-facing wave facets became bright mirrors'
    print('PASS: GPU actual grazing water optics retain curved rays and mask hidden facets',flush=True)

    f.texture(scene,0)
    blur_values=dict(values,MOTION_BLUR=True,MOTION_BLUR_LOW_LATENCY=True,UPSCALE_QUALITY='0')
    blur_prefix=api['source'](api['ROOT']/'composite6.fsh',blur_values,False).split('in vec2 texcoord;')[0]
    fragment=blur_prefix+'''in vec2 texcoord; layout(location=0) out vec4 color;
    void main(){vec3 now=textureScreen(colortex0,texcoord).rgb;
    color=vec4(applyMotionBlur(texcoord,now),1);}'''
    p=f.program('composite6.fsh',blur_values,fragment=fragment)
    f.texture([0.8,0,0,1]*pixels,2)
    f.texture([0.14,1,0,0.25]*pixels,6)
    blur_u=dict(u,colortex0=0,colortex2=6,depthtex0=2,
        gbufferPreviousModelView=identity,gbufferPreviousProjection=identity,
        previousCameraPosition=(0.,0.,0.),frameCounter=20,frameTime=1/60)
    still=f.render(p,[target],dict(blur_u,cameraPosition=(0.,0.,0.)))
    jumped=f.render(p,[target],dict(blur_u,cameraPosition=(0.,0.5,0.)))
    assert max(abs(a-b) for a,b in zip(still,jumped))<1e-5, 'Motion blur dragged the water pattern during a jump'
    f.texture([0.14,1,0,0.0]*pixels,6)
    solid=f.render(p,[target],dict(blur_u,cameraPosition=(0.,0.5,0.)))
    assert max(abs(a-b) for a,b in zip(still,solid))>.1, 'Opaque motion blur was disabled along with water'
    print('PASS: GPU jumping preserves water pixels while opaque camera motion blur remains active',flush=True)
    taa_values=dict(values,TAA=True,DOF=False,BLOOM=False,UPSCALE_QUALITY='0')
    taa_prefix=api['source'](api['ROOT']/'prepare.fsh',taa_values,False).split('in vec2 texcoord;')[0]
    taa_prefix+='\nuniform sampler2D colortex0;\n'+api['expand'](api['ROOT']/'lib/taa.glsl')
    fragment=taa_prefix+"""in vec2 texcoord; layout(location=0) out vec4 color;
    void main(){float z; vec3 now=textureScreen(colortex0,texcoord).rgb;
    vec3 resolved=applyTAA(texcoord,now,z); color=vec4(resolved,z);}"""
    p=f.program('composite6.fsh',taa_values,fragment=fragment)
    n,far=.05,256.0
    pa,pb=-(far+n)/(far-n),-2*far*n/(far-n)
    proj=[1,0,0,0,0,1,0,0,0,0,pa,-1,0,0,pb,0]
    inv=[1,0,0,0,0,1,0,0,0,0,0,1/pb,0,0,-1,pa/pb]
    pattern=[]
    for y in range(f.h):
        for x in range(f.w): pattern.extend([.45 if (x+y)%2 else .55]*3+[1])
    f.texture(pattern,0)
    f.texture([(-pa+pb/4)*.5+.5,0,0,1]*pixels,2)
    f.texture([.14,1,0,.25]*pixels,6)
    taa_u=dict(blur_u,gbufferProjection=proj,gbufferProjectionInverse=inv,
        gbufferPreviousProjection=proj,colortex13=7,cameraPosition=(0.,0.,0.))
    histories=[]
    for old in (.48,.52):
        f.texture([old,old,old,4]*pixels,7)
        histories.append(f.render(p,[target],taa_u))
    assert max(abs(v+3) for v in histories[0][3::4])<1e-5, 'Water history remained reusable by opaque surfaces'
    assert max(abs(a-b) for a,b in zip(*histories))<1e-5, 'TAA reprojected old water reflections using flat mesh motion'
    f.texture([.14,1,0,0]*pixels,6)
    solid=f.render(p,[target],taa_u)
    assert max(abs(a-b) for i,(a,b) in enumerate(zip(histories[1],solid)) if i%4<3)>.001, 'Opaque temporal antialiasing was disabled'
    print('PASS: GPU water optics ignore incompatible TAA history while opaque history stays active',flush=True)
    f.close()

"""Native GPU regressions for material decoding, diffuse energy and solar PCSS."""
from quality_checks import Fixture


def run(api):
    f=Fixture(api,64,32)
    values=dict(api['resolve']('REALISM'),SHADOWS=False)
    prefix=api['source'](api['ROOT']/'dh_terrain.fsh',values,False).split('uniform sampler2D depthtex0;')[0]
    target=f.texture(None,0)
    def draw(body,uniforms=None):
        p=f.program('prepare.fsh',values,fragment=prefix+'in vec2 texcoord;\nlayout(location=0) out vec4 color;\nvoid main(){'+body+'}')
        return f.render(p,[target],uniforms or {})
    # Source-defined conductor constants have distinct gold/copper/silver spectra.
    gold=draw('color=vec4(conductorF0(231,vec3(1)),1);')[:3]
    copper=draw('color=vec4(conductorF0(234,vec3(1)),1);')[:3]
    silver=draw('color=vec4(conductorF0(237,vec3(1)),1);')[:3]
    assert 0.93<gold[0]<0.97 and 0.75<gold[1]<0.79 and 0.35<gold[2]<0.40
    assert copper[0]>copper[1]>copper[2] and min(silver)>0.91
    assert max(draw('color=vec4(diffuseResponse(vec3(1),vec3(0.9),1.0),1);')[:3])==0.0, 'Metal has diffuse bounce'
    decoded=draw('float r=0.78,m=0,e=0,s=0,p=0.5;vec3 f0=vec3(0.04);decodeLabPBR(vec4(0.7,10.0/255.0,0,1),vec3(1),r,f0,m,e,s,p);color=vec4(r,f0.r,m,e);')
    assert abs(decoded[0]-0.3)<1e-5 and abs(decoded[1]-10/255)<1e-5 and decoded[2:4]==[0.0,0.0]
    opaque=draw('float r=0.78,m=0,e=0,s=0,p=0.5;vec3 f0=vec3(0.04);decodeLabPBR(vec4(0,0,0,1),vec3(1),r,f0,m,e,s,p);color=vec4(r,f0.r,m,e);')
    assert abs(opaque[0]-0.78)<1e-5 and abs(opaque[1]-0.04)<1e-5
    # AO=0 removes ambient only: direct sun + emission must remain.
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    uniforms=dict(gbufferModelViewInverse=identity,shadowLightPosition=(0.,0.,1.),sunPosition=(0.,1.,0.),rainStrength=0.)
    result=draw('float a;vec3 c=shadeMaterial(vec3(0.5),vec3(0,0,1),vec3(0,0,-2),vec2(0,1),0.78,1.0,0.0,vec3(0.04),0.0,1.0,a);color=vec4(c*(1.0-a),a);',uniforms)
    assert min(result[:3])>2.5 and 0<result[3]<0.2, 'AO attenuated emission/direct sunlight'
    print('PASS: GPU LabPBR conductors, linear F0, alpha sentinel, zero metal diffuse and ambient-only AO',flush=True)
    f.close()

    f=Fixture(api,64,32)
    values=dict(api['resolve']('REALISM'),CLOUD_SHADOWS=False)
    prefix=api['source'](api['ROOT']/'dh_terrain.fsh',values,False).split('uniform sampler2D depthtex0;')[0]
    frag=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){float v=shadowVisibility(vec3((texcoord.x-0.5)*0.10,0,0),vec3(0,0,1),1.0,true);color=vec4(v,v,v,1);}
'''
    program=f.program('prepare.fsh',values,fragment=frag)
    target=f.texture(None,0)
    uniforms=dict(shadowtex0=1,shadowProjection=identity,shadowModelView=identity)
    f.texture([1,0,0,1]*(64*32),1)
    lit=f.render(program,[target],uniforms)
    assert min(lit)>0.999, 'Empty blocker search shadowed a lit receiver'
    f.texture([0.1,0,0,1]*(64*32),1)
    dark=f.render(program,[target],uniforms)
    assert max(dark[i] for i in range(0,len(dark),4))<0.001
    # A sharp blocker edge must become wider when separation increases.
    def edge(d):
        f.texture([v for y in range(32) for x in range(64) for v in ((d if x<32 else 1),0,0,1)],1)
        return f.render(program,[target],uniforms)
    close,far=edge(0.503),edge(0.35)
    width=lambda pixels:sum(0.01<pixels[(16*64+x)*4]<0.99 for x in range(64))
    assert width(far)>width(close), 'PCSS penumbra did not grow with blocker distance'
    print('PASS: GPU solar PCSS lit/shadowed bounds and increasing blocker-distance penumbra',flush=True)
    f.close()
    check_exposure(api)
    check_temporal_indirect(api)
    check_natural_light(api)
    if '--benchmark' in api['sys'].argv:
        benchmark_matte_reflections(api)


def check_exposure(api):
    f=Fixture(api,1,1)
    values=api['resolve']('REALISM')
    p=f.program('deferred6.fsh',values)
    target=f.texture(None,0)
    u=dict(colortex0=1,colortex16=2,frameCounter=0,frameTime=1/60,
           cameraPosition=(0.,0.,0.),previousCameraPosition=(0.,0.,0.))
    def draw(luma,previous,**extra):
        f.texture([luma,luma,luma,1],1)
        f.texture([previous,0,0,1],2)
        return f.render(p,[target],dict(u,**extra))[0]
    assert abs(draw(1.,0.)-0.35)<0.001
    assert abs(draw(0.001,0.)-3.0)<0.001
    bright=draw(1.,1.,frameCounter=20)
    dark=draw(0.001,1.,frameCounter=20)
    assert 0.35<bright<1.<dark<3., 'Exposure adapted instantly or in the wrong direction'
    assert abs(draw(1.,float('nan'),frameCounter=20)-0.35)<0.001
    assert abs(draw(1.,1.,frameCounter=20,cameraPosition=(100.,0.,0.))-0.35)<0.001
    # Adaptation integrates elapsed time, rather than one fixed blend per frame.
    once=draw(0.001,1.,frameCounter=20,frameTime=1/30)
    twice=draw(0.001,dark,frameCounter=20,frameTime=1/60)
    assert abs(once-twice)<0.0001
    print('PASS: GPU exposure limits, measured luminance, gradual/frame-rate-independent adaptation and reset',flush=True)
    f.close()


def check_temporal_indirect(api):
    f=Fixture(api,16,16)
    values=api['resolve']('REALISM')
    prefix=api['source'](api['ROOT']/'deferred3.fsh',values,False).split('in vec2 texcoord;')[0]
    frag=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){color=stabilizeIndirect(texcoord,viewPosition(texcoord,0.97509751),vec3(0,0,1),vec4(0),vec4(2,2,2,0.7));}
'''
    p=f.program('deferred3.fsh',values,fragment=frag)
    target=f.texture(None,0)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    n,z=0.1,1024.
    a,b=-(z+n)/(z-n),-2*z*n/(z-n)
    projection=[1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0]
    inverse=[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    u=dict(viewWidth=16.,viewHeight=16.,gbufferProjection=projection,gbufferProjectionInverse=inverse,
           gbufferModelViewInverse=identity,gbufferPreviousModelView=identity,gbufferPreviousProjection=projection,
           colortex17=1,colortex18=2,frameCounter=20,frameTime=1/60,
           cameraPosition=(0.,0.,0.),previousCameraPosition=(0.,0.,0.))
    f.texture([1,1,1,0.7]*256,1)
    def draw(geometry,**extra):
        f.texture(geometry*256,2)
        return f.render(p,[target],dict(u,**extra))[(8*16+8)*4]
    assert abs(draw([0,0,1,4])-1.12)<0.001, 'Static indirect history was not reused'
    assert abs(draw([0,0,1,40])-2)<0.001, 'Disoccluded background history was reused'
    assert abs(draw([0,1,0,4])-2)<0.001, 'Normal discontinuity history was reused'
    assert abs(draw([0,0,1,4],cameraPosition=(10.,0.,0.))-2)<0.001
    assert abs(draw([0,0,1,4],frameCounter=0)-2)<0.001
    print('PASS: GPU signal-specific GI/AO reprojection, static reuse, depth/normal rejection and camera reset',flush=True)
    f.close()


def check_natural_light(api):
    f=Fixture(api,16,16)
    values=api['resolve']('REALISM')
    prefix=api['source'](api['ROOT']/'dh_terrain.fsh',values,False).split('uniform sampler2D depthtex0;')[0]
    prefix+=api['expand'](api['ROOT']/'lib/atmosphere.glsl')+api['expand'](api['ROOT']/'lib/color_grading.glsl')
    target=f.texture(None,0)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    u=dict(gbufferModelViewInverse=identity,sunPosition=(0.,1.,0.),rainStrength=0.)
    def draw(body,**extra):
        frag=prefix+'in vec2 texcoord;layout(location=0) out vec4 color;void main(){'+body+'}'
        p=f.program('prepare.fsh',values,fragment=frag)
        return f.render(p,[target],dict(u,**extra))[:4]
    linear=draw('color=vec4(srgbToLinear(vec3(0.5)),1);')
    assert max(abs(x-0.21404114) for x in linear[:3])<1e-5
    roundtrip=draw('color=vec4(linearToSrgb(srgbToLinear(vec3(0.02,0.5,0.95))),1);')
    assert max(abs(x-y) for x,y in zip(roundtrip[:3],(0.02,0.5,0.95)))<1e-5
    day=draw('color=vec4(lightColor(),1);')
    assert max(day[:3])/min(day[:3])<1.1, 'Noon sunlight has a strong color cast'
    sunset=draw('color=vec4(lightColor(),1);',sunPosition=(1.,0.04,0.))
    assert sunset[0]>sunset[1]>sunset[2], 'Neutral daylight removed the sunset coloration'
    fog=draw('color=vec4(clearAirOpticalDepth(8.0,64.0),clearAirOpticalDepth(12.0,64.0),clearAirOpticalDepth(200.0,64.0),clearAirOpticalDepth(800.0,64.0));')
    assert fog[0]==fog[1]==0 and 0<fog[2]<fog[3]<1
    disc=draw('vec3 d=normalize(sunPosition);color=vec4(length(atmosphereBackground(d)),length(skyRadiance(d)),0,1);')
    assert disc[1]>disc[0]*5 and disc[0]<2., 'Fog background contains a bright solar disk'
    grey=draw('color=vec4(linearToSrgb(tonemapKhronos(vec3(0.18))),1);')
    assert max(grey[:3])-min(grey[:3])<1e-5 and 0.39<grey[0]<0.43
    print('PASS: GPU sRGB reference/roundtrip, neutral noon/warm sunset, near-clear/distance fog, disk-free fog and neutral middle gray',flush=True)
    f.close()


def benchmark_matte_reflections(api):
    """Isolated native GPU timer; deliberately not an estimate of gameplay FPS."""
    import ctypes as c
    backup=api['ROOT'].parent.parent.parent/'.codex-backups/natural-lighting-20261005/shaders'
    if not backup.exists():
        print('SKIP: matte-reflection benchmark requires the preserved pre-optimization shader source',flush=True)
        return
    f=Fixture(api,960,540)
    values=dict(api['resolve']('REALISM'),SSAO=False,SSGI=False,HALF_RES_LIGHTING=False,CLOUDS='0')
    root=api['ROOT']
    try:
        api['ROOT']=backup
        old=f.program('deferred5.fsh',values)
    finally:
        api['ROOT']=root
    new=f.program('deferred5.fsh',values)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    n,z=0.1,1024.
    a,b=-(z+n)/(z-n),-2*z*n/(z-n)
    projection=[1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0]
    inverse=[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    count=f.w*f.h
    f.texture([0.2,0.2,0.2,1]*count,0)
    f.texture([0.5,0.5,1,1]*count,1)
    f.texture([0.78,1,0,0]*count,2)
    f.texture([0.04,0.04,0.04,0]*count,3)
    depth=(-a+b/4)*0.5+0.5
    f.texture([depth,0,0,1]*count,4)
    f.texture([0.2,0.3,0.5,1]*(128*64),5,w=128,h=64)
    target=f.texture(None,6);copy=f.texture(None,7)
    u=dict(viewWidth=float(f.w),viewHeight=float(f.h),gbufferProjection=projection,gbufferProjectionInverse=inverse,
           gbufferModelViewInverse=identity,colortex0=0,colortex1=1,colortex2=2,colortex3=3,depthtex0=4,colortex7=5)
    query=c.c_uint()
    f.call('glGenQueries',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(query))
    times=[]
    for p in (old,new):
        f.render(p,[target,copy],u)
        for _ in range(16): f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0004,0,6)
        f.call('glFinish',None,[])
        f.call('glBeginQuery',None,[c.c_uint,c.c_uint],0x88BF,query)
        for _ in range(100): f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0004,0,6)
        f.call('glEndQuery',None,[c.c_uint],0x88BF)
        ns=c.c_ulonglong()
        f.call('glGetQueryObjectui64v',None,[c.c_uint,c.c_uint,c.POINTER(c.c_ulonglong)],query,0x8866,c.byref(ns))
        times.append(ns.value/100/1e6)
    f.call('glDeleteQueries',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(query))
    print(f'GPU BENCHMARK: isolated matte reflection pass 960x540, 100 draws: before {times[0]:.3f} ms, after {times[1]:.3f} ms; not gameplay FPS',flush=True)
    f.close()

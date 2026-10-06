"""Distant Horizons projection, LOD shading and filtered-water GPU regressions."""
import math
from quality_checks import Fixture

IDENTITY=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]

def run(api):
    f=Fixture(api,64,32)
    values=dict(api['resolve']('REALISM'),SHADOWS=False,CLOUD_SHADOWS=False)
    prefix=api['source'](api['ROOT']/'prepare.fsh',values,False).split('in vec2 texcoord;')[0]
    target=f.texture(None,0)
    def draw(body,extra='',uniforms=None):
        p=f.program('prepare.fsh',values,fragment=prefix+extra+'in vec2 texcoord;layout(location=0) out vec4 color;void main(){'+body+'}')
        return f.render(p,[target],uniforms or {})
    near,far=2.,4096.
    a,b=-(far+near)/(far-near),-2*far*near/(far-near)
    inverse=[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    # z/w must agree with full reconstruction even when x/y row terms are nonzero.
    skew=list(inverse);skew[2]=0.013;skew[7]=0.0007
    for matrix in (inverse,skew):
        out=draw('float d=0.96+0.035*texcoord.x;vec4 p=testInverse*vec4(texcoord*2.0-1.0,d*2.0-1.0,1);color=vec4(abs(projectedViewDepth(testInverse,texcoord,d)-p.z/p.w)/max(abs(p.z/p.w),1.0));',
                 'uniform mat4 testInverse;',dict(testInverse=matrix))
        assert max(out)<1e-4, 'DH z/w reconstruction lost asymmetric projection terms'
    # Independently allocated DH depth must never reuse the vanilla sampler size.
    f.texture([1,0,0,1]*(64*32),1)
    depths=[]
    for y in range(9):
        for x in range(17):
            z=120. if x<8 else 240.
            depths.extend(((-a+b/z)*0.5+0.5,0,0,1))
    f.texture(depths,2,17,9)
    extra='#define AA_TRACE_DH\nuniform sampler2D dhDepthTex1;uniform sampler2D testDepth;uniform mat4 dhProjectionInverse;\n'+api['expand'](api['ROOT']/'lib/trace.glsl')
    out=draw('bool valid;float z=traceSurfaceDepth(testDepth,screenTextureSize(testDepth),traceDHDepthSize(),texcoord,valid);color=vec4(z,float(valid),0,1);',extra,
             dict(testDepth=1,dhDepthTex1=2,dhProjectionInverse=inverse,gbufferProjectionInverse=inverse))
    assert abs(out[(16*64+8)*4]+120)<0.01 and abs(out[(16*64+56)*4]+240)<0.03
    assert min(out[1::4])==1
    values['UPSCALE_QUALITY']='1'
    prefix=api['source'](api['ROOT']/'prepare.fsh',values,False).split('in vec2 texcoord;')[0]
    scaled=draw('bool valid;float z=traceSurfaceDepth(testDepth,screenTextureSize(testDepth),traceDHDepthSize(),texcoord,valid);color=vec4(z,float(valid),0,1);',extra,
                dict(testDepth=1,dhDepthTex1=2,dhProjectionInverse=inverse,gbufferProjectionInverse=inverse))
    assert abs(scaled[(16*64+38)*4]+120)<0.01, 'DH FSR sampling did not use its own active allocation'
    values['UPSCALE_QUALITY']='0'
    prefix=api['source'](api['ROOT']/'prepare.fsh',values,False).split('in vec2 texcoord;')[0]
    # Optical path equals full bottom xyz on the same perspective ray at center/edges.
    out=draw('float surfaceZ=-30.0;float bottomZ=-60.0;float ds=(-testA+testB/30.0)*0.5+0.5;float db=(-testA+testB/60.0)*0.5+0.5;vec4 ps=testInverse*vec4(texcoord*2.0-1.0,ds*2.0-1.0,1);vec4 pb=testInverse*vec4(texcoord*2.0-1.0,db*2.0-1.0,1);vec3 vp=ps.xyz/ps.w;float fast=max(vp.z-projectedViewDepth(testInverse,texcoord,db),0.0)*length(vp)/max(-vp.z,0.01);color=vec4(abs(fast-length(pb.xyz/pb.w-vp)));',
             'uniform mat4 testInverse;uniform float testA,testB;',dict(testInverse=inverse,testA=a,testB=b))
    assert max(out)<0.002, 'DH scalar water thickness differs from full perspective reconstruction'
    print('PASS: GPU DH z/w including asymmetric projections, independent depth sizes and perspective water thickness',flush=True)
    f.close()

    f=Fixture(api,32,16); target=f.texture(None,0)
    values=dict(api['resolve']('REALISM'),SHADOWS=False,CLOUD_SHADOWS=False)
    terrain=api['source'](api['ROOT']/'dh_terrain.fsh',values,False).split('uniform sampler2D depthtex0;')[0]
    def shade(vp,held=0,full=False):
        code=terrain.replace('#define AA_DH_TERRAIN','') if full else terrain
        fragment=code+'uniform vec3 testPosition;in vec2 texcoord;layout(location=0) out vec4 color;void main(){float a;vec3 c=shadeMaterial(vec3(0.3,0.4,0.2),vec3(0,1,0),testPosition,vec2(0.3,1),0.78,0,0,vec3(0.04),0,1,a);color=vec4(c,a);}'
        p=f.program('prepare.fsh',values,fragment=fragment)
        return f.render(p,[target],dict(testPosition=vp,gbufferModelViewInverse=IDENTITY,
            sunPosition=(0.,1.,0.),shadowLightPosition=(0.,1.,0.2),heldBlockLightValue=held))[:4]
    near=shade((0,-0.2,-30))
    assert max(abs(x-y) for x,y in zip(near,shade((0,-0.2,-30),full=True)))<1e-5
    assert max(abs(x-y) for x,y in zip(near,shade((0,-0.2,-30),held=15)))<1e-5
    for distance in (64.,96.,128.):
        before=shade((0,-0.2,-distance+0.001)); after=shade((0,-0.2,-distance-0.001))
        assert max(abs(x-y) for x,y in zip(before,after))<0.001, 'DH shading transition popped'
    far=shade((0,-0.2,-800))
    assert all(math.isfinite(x) and x>=0 for x in far) and 0<=far[3]<=1
    print('PASS: GPU DH near-shading parity, held-light exclusion, finite distant lighting and smooth 64/96/128-block transitions',flush=True)
    f.close()

    f=Fixture(api,64,32); target=f.texture(None,0)
    prefix=api['source'](api['ROOT']/'prepare.fsh',values,False).split('in vec2 texcoord;')[0]
    extra=api['expand'](api['ROOT']/'lib/environment.glsl')+api['expand'](api['ROOT']/'lib/water_reflection.glsl')
    # Constant cache energy must be preserved by both filters. Bright stripes ensure
    # reduced-tap DH reflection remains filtered instead of turning into a single mirror.
    f.texture([0.3,0.4,0.6,1]*(128*64),1,128,64)
    fragment=prefix+extra+'in vec2 texcoord;layout(location=0) out vec4 color;void main(){vec3 r=normalize(vec3(texcoord.x-0.5,0.02,1));color=vec4(waterLODEnvironmentReflection(r,0.12),1);}'
    p=f.program('prepare.fsh',values,fragment=fragment)
    out=f.render(p,[target],dict(colortex7=1))
    assert max(abs(out[i]-(0.3,0.4,0.6,1)[i%4]) for i in range(len(out)))<1e-5
    cache=[]
    for y in range(64):
        for x in range(128):
            c=1. if y%2 else 0.
            cache.extend((c,c,c,1))
    f.texture(cache,1,128,64)
    out=f.render(p,[target],dict(colortex7=1))
    assert all(math.isfinite(x) and 0<=x<=1 for x in out)
    assert 0.1<sum(out[0::4])/(64*32)<0.9
    print('PASS: GPU DH four-tap world-space reflection preserves constant energy and filters high-contrast sky',flush=True)
    f.close()


def benchmark(api):
    """Isolate shader costs with GPU timer queries; no gameplay FPS extrapolation."""
    import ctypes as c
    backup=api['ROOT'].parent.parent.parent/'.codex-backups/dh-audit-20261006/shaders'
    if not backup.exists():
        print('SKIP: DH benchmark needs the preserved pre-audit source',flush=True)
        return
    f=Fixture(api,960,540)
    values=dict(api['resolve']('REALISM'),SHADOWS=False,CLOUD_SHADOWS=False)
    root=api['ROOT']
    try:
        api['ROOT']=backup
        old=api['source'](backup/'dh_terrain.fsh',values,False).split('uniform sampler2D depthtex0;')[0]
    finally:
        api['ROOT']=root
    new=api['source'](root/'dh_terrain.fsh',values,False).split('uniform sampler2D depthtex0;')[0]
    body='in vec2 texcoord;layout(location=0) out vec4 color;void main(){vec3 vp=vec3((texcoord.x-0.5)*1600.0,-300.0,-1200.0);float a;vec3 N=normalize(vec3(texcoord.x-0.5,1,0));color=vec4(shadeMaterial(vec3(0.3,0.4,0.2),N,vp,vec2(0.3,1),0.78,0,0,vec3(0.04),0,1,a),a);}'
    terrain=[f.program('prepare.fsh',values,fragment=prefix+body) for prefix in (old,new)]
    prefix=api['source'](root/'prepare.fsh',values,False).split('in vec2 texcoord;')[0]
    prefix+=api['expand'](root/'lib/environment.glsl')+api['expand'](root/'lib/water_reflection.glsl')
    reflection=[f.program('prepare.fsh',values,fragment=prefix+'in vec2 texcoord;layout(location=0) out vec4 color;void main(){vec3 r=normalize(vec3(texcoord.x-0.5,texcoord.y-0.5,1));color=vec4('+fn+'(r,0.08),1);}') for fn in ('waterEnvironmentReflection','waterLODEnvironmentReflection')]
    cache=[]
    for y in range(64):
        for x in range(128): cache.extend((x/128,y/64,0.3,1))
    f.texture(cache,1,128,64)
    target=f.texture(None,0)
    u=dict(colortex7=1,gbufferModelViewInverse=IDENTITY,shadowLightPosition=(0.,1.,0.2),sunPosition=(0.,1.,0.),heldBlockLightValue=15)
    query=c.c_uint();f.call('glGenQueries',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(query))
    for label,programs in (('far terrain shading',terrain),('filtered water environment',reflection)):
        times=[]
        for p in programs:
            f.render(p,[target],u)
            for _ in range(16):f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0004,0,6)
            f.call('glFinish',None,[])
            f.call('glBeginQuery',None,[c.c_uint,c.c_uint],0x88BF,query)
            for _ in range(100):f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0004,0,6)
            f.call('glEndQuery',None,[c.c_uint],0x88BF)
            ns=c.c_ulonglong();f.call('glGetQueryObjectui64v',None,[c.c_uint,c.c_uint,c.POINTER(c.c_ulonglong)],query,0x8866,c.byref(ns))
            times.append(ns.value/100/1e6)
        print(f'GPU DH BENCHMARK: isolated {label} 960x540, 100 draws: before {times[0]:.3f} ms, after {times[1]:.3f} ms; not gameplay FPS',flush=True)
    f.call('glDeleteQueries',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(query))
    f.close()

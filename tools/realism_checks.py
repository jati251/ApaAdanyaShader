"""GPU regressions for dark silhouettes, sky motion and distant reflection travel."""
import math
from quality_checks import Fixture


def run(api):
    check_dh_frame_order(api)
    f=Fixture(api,97,55)
    w,h=f.w,f.h
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    near,far=0.05,1024.0
    a,b=-(far+near)/(far-near),-2*far*near/(far-near)
    projection=[1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0]
    inverse=[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    depth=lambda z:(-a+b/z)*0.5+0.5
    values=dict(api['resolve']('EXTREME'),UPSCALE_QUALITY='0')
    prefix=api['source'](api['ROOT']/'composite7.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;
layout(location=0) out vec4 color;
void main(){color=vec4(applyMotionBlur(texcoord,textureScreen(colortex0,texcoord).rgb),1.0);}
'''
    program=f.program('final.fsh',values,fragment=fragment)
    scene=[]; depths=[]
    for y in range(h):
        for x in range(w):
            foreground=x<w//2
            c=0.02 if foreground else 0.95
            scene.extend((c,c,c,1))
            depths.extend((depth(12) if foreground else 1,0,0,1))
    f.texture(scene,0); f.texture(depths,1); f.texture([0,0,0,0]*(w*h),2)
    target=f.texture(None,3)
    angle=0.22; cs,sn=math.cos(angle),math.sin(angle)
    rotation=[cs,0,-sn,0,0,1,0,0,sn,0,cs,0,0,0,0,1]
    u=dict(viewWidth=float(w),viewHeight=float(h),near=near,far=far,
           frameTime=1/60,frameCounter=20,gbufferProjection=projection,
           gbufferProjectionInverse=inverse,gbufferPreviousProjection=projection,
           gbufferModelView=identity,gbufferModelViewInverse=identity,
           gbufferPreviousModelView=rotation,cameraPosition=(0.,0.,0.),
           previousCameraPosition=(0.,0.,0.),colortex0=0,depthtex0=1,colortex2=2)
    moving=f.render(program,[target],u)
    dark=[moving[(y*w+x)*4] for y in range(h) for x in range(w//2)]
    assert max(dark)<0.0201, 'Bright sky bled into a dark terrain silhouette during rotation'
    assert max(abs(moving[i]-scene[i]) for i in range(len(scene)))<0.0001
    # Sky has angular motion only; walking cannot turn stars into translation trails.
    gradient=[]
    for y in range(h):
        for x in range(w):
            c=(x%3)*0.3
            gradient.extend((c,c,c,1))
    f.texture(gradient,0); f.texture([1,0,0,1]*(w*h),1)
    sky=f.render(program,[target],dict(u,gbufferPreviousModelView=identity,cameraPosition=(1.,0.,0.)))
    assert max(abs(sky[i]-gradient[i]) for i in range(len(sky)))<0.0001, 'Sky blur used camera translation'
    print('PASS: GPU motion blur, dark silhouette isolation and translation-free sky',flush=True)
    f.close()

    f=Fixture(api,64,32)
    values=api['resolve']('REALISM_RT')
    prefix=api['source'](api['ROOT']/'prepare.fsh',values,False).split('in vec2 texcoord;')[0]
    trace=api['expand'](api['ROOT']/'lib/trace.glsl')
    fragment=prefix+trace+'''uniform sampler2D testDepth;
in vec2 texcoord;
layout(location=0) out vec4 color;
void main(){vec2 hit;float confidence;
bool found=traceScreen(testDepth,vec3(0,0,-2),vec3(0,0,-1),0.22,56,hit,confidence);
color=vec4(float(found),confidence,0,1);}
'''
    p=f.program('prepare.fsh',values,fragment=fragment)
    f.texture([depth(120),0,0,1]*(f.w*f.h),1)
    target=f.texture(None,0)
    out=f.render(p,[target],dict(gbufferProjection=projection,gbufferProjectionInverse=inverse,
                              near=near,testDepth=1,viewWidth=float(f.w),viewHeight=float(f.h)))
    assert min(out[0::4])>0.99, 'Reflection travel missed the distant coast'
    assert min(out[1::4])>0.1 and max(out[1::4])<=1.0, 'Distant reflection confidence invalid'
    print('PASS: GPU 120-block reflection travel and bounded intersection confidence',flush=True)
    # DH uses a different near/far mapping; reading its depth with vanilla's matrix is wrong.
    dhNear,dhFar=2.0,4096.0
    da,db=-(dhFar+dhNear)/(dhFar-dhNear),-2*dhFar*dhNear/(dhFar-dhNear)
    dhInverse=[1,0,0,0,0,1,0,0,0,0,0,1/db,0,0,-1,da/db]
    f.texture([1,0,0,1]*(f.w*f.h),1)
    f.texture([(-da+db/120)*0.5+0.5,0,0,1]*(f.w*f.h),2)
    dhFragment=fragment.replace(prefix+trace,prefix+'''#define AA_TRACE_DH
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjectionInverse;
'''+trace)
    dhProgram=f.program('prepare.fsh',values,fragment=dhFragment)
    dhOut=f.render(dhProgram,[target],dict(gbufferProjection=projection,
        gbufferProjectionInverse=inverse,dhProjectionInverse=dhInverse,dhDepthTex1=2,
        near=near,testDepth=1,viewWidth=float(f.w),viewHeight=float(f.h)))
    assert min(dhOut[0::4])>0.99 and min(dhOut[1::4])>0.1, 'DH fallback used the wrong depth projection'
    print('PASS: GPU distant reflection fallback with separate DH projection',flush=True)
    f.close()


def check_dh_frame_order(api):
    """Old opaque-copy silhouettes must not suppress this frame's sky/clouds."""
    f=Fixture(api,64,32)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    near,far=0.05,1024.0
    a,b=-(far+near)/(far-near),-2*far*near/(far-near)
    projection=[1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0]
    inverse=[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    pixels=f.w*f.h
    f.texture([0.8,0.2,0.45,1]*pixels,0)  # conspicuous clear color, like the reported band
    f.texture([1,0,0,1]*pixels,1)        # vanilla sky this frame
    f.texture([1,0,0,1]*pixels,2)        # DH sky this frame
    f.texture([1,0,0,1]*pixels,3)        # baseline opaque copy
    target=f.texture(None,4); opaque=f.texture(None,5)
    uniforms=dict(viewWidth=float(f.w),viewHeight=float(f.h),near=near,far=far,
        gbufferProjection=projection,gbufferProjectionInverse=inverse,
        dhProjectionInverse=inverse,gbufferModelViewInverse=identity,
        cameraPosition=(0.,80.,0.),sunPosition=(0.,-1.,0.),frameTimeCounter=3.,
        colortex0=0,depthtex0=1,dhDepthTex0=2,dhDepthTex1=3)
    for entry,profile in [('deferred5.fsh','POTATO'),('deferred1.fsh','REALISM')]:
        values=api['resolve'](profile)
        fragment=api['source'](api['ROOT']/entry,values,True)
        program=f.program(entry,values,fragment=fragment)
        f.texture([1,0,0,1]*pixels,2)
        f.texture([1,0,0,1]*pixels,3)
        targets=[target,opaque] if entry=='deferred5.fsh' else [target]
        baseline=f.render(program,targets,uniforms)
        # The opaque copy still carries a coastline from the previous camera orientation.
        stale=[]
        for y in range(f.h):
            for x in range(f.w):
                d=(-a+b/120)*0.5+0.5 if x>=f.w//2 else 1.0
                stale.extend((d,0,0,1))
        f.texture(stale,3)
        moving=f.render(program,targets,uniforms)
        error=max(abs(x-y) for x,y in zip(baseline,moving))
        assert error<0.0001, f'{entry}: stale DH opaque copy changed current sky/clouds ({error:.4f})'
        # Still recognize real terrain in this frame; ignoring DH altogether is not a fix.
        current=[]
        for y in range(f.h):
            for x in range(f.w):
                d=(-a+b/120)*0.5+0.5 if x<f.w//2 else 1.0
                current.extend((d,0,0,1))
        f.texture(current,2)
        f.texture([1,0,0,1]*pixels,3)
        actual=f.render(program,targets,uniforms)
        left=((f.h//2)*f.w+f.w//4)*4
        if entry=='deferred5.fsh':
            assert abs(actual[left]-0.8)<0.0001, 'Current DH terrain was replaced by sky'
        else:
            assert actual[left+3]<0, 'Clouds rendered through current DH terrain'
    print('PASS: GPU DH camera-pan sky/clouds ignore stale pre-translucent depth',flush=True)
    f.close()


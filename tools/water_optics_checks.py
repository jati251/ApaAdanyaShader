"""Actual water optics on a perspective plane, with refraction enabled and camera motion."""
import math
from quality_checks import Fixture


def run(api):
    f=Fixture(api,160,90)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    values=dict(api['resolve']('REALISM_FAST'),WATER_REFRACTION=True,WATER_CAUSTICS=False,
                SHADOWS=False,CLOUD_SHADOWS=False,LIGHT_SPACE_FALLBACK=False,
                VOXEL_TRACING=False,UPSCALE_QUALITY='0')
    near,far=.05,256.
    fy=1/math.tan(math.radians(65)/2); fx=fy*f.h/f.w
    a=-(far+near)/(far-near); b=-2*far*near/(far-near)
    projection=[fx,0,0,0,0,fy,0,0,0,0,a,-1,0,0,b,0]
    inverse=[1/fx,0,0,0,0,1/fy,0,0,0,0,0,1/b,0,0,-1,a/b]
    pitch=math.radians(60); cs,sn=math.cos(pitch),math.sin(pitch)
    model=[1,0,0,0,0,cs,sn,0,0,-sn,cs,0,0,0,0,1]
    model_inverse=[1,0,0,0,0,cs,-sn,0,0,sn,cs,0,0,0,0,1]
    vertex='''#version 330 core
uniform mat4 gbufferProjection,gbufferModelView;
uniform vec3 cameraPosition,testVertexBias;
out vec2 texcoord,lmcoord; out vec4 glcolor,tangent;
out vec3 viewNormal,viewPos,worldPos; flat out float materialId;
void main(){
    const vec2 corners[6]=vec2[6](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,0),vec2(1,1),vec2(0,1));
    vec2 uv=corners[gl_VertexID]; texcoord=uv; lmcoord=vec2(0,1);
    viewNormal=mat3(gbufferModelView)*vec3(0,1,0);
    vec3 ray=vec3((uv*2-1)/vec2(gbufferProjection[0][0],gbufferProjection[1][1]),-1);
    viewPos=ray*(-cameraPosition.y/dot(viewNormal,ray))+testVertexBias;
    // Plane depth is affine in screen coordinates. Actual rasterized z is used by water.
    float ndc=-gbufferProjection[2][2]-gbufferProjection[3][2]*dot(viewNormal,ray)/cameraPosition.y;
    gl_Position=vec4(uv*2-1,ndc,1); worldPos=vec3(0);
    glcolor=vec4(1); tangent=vec4(1,0,0,1); materialId=1003;
}'''
    def fragment(opts):
        code=api['source'](api['ROOT']/'gbuffers_water.fsh',opts,False)
        # A fullscreen planar fixture reconstructs the varying world coordinate
        # per pixel, avoiding affine interpolation of a perspective-plane position.
        return code.replace('in vec3 viewNormal,viewPos,worldPos;',
            'in vec3 viewNormal,viewPos;\n#define worldPos '
            '((gbufferModelViewInverse*vec4(waterFragmentPosition(),1)).xyz+cameraPosition)')
    sky=[]
    for y in range(64):
        for x in range(128):
            cloud=.35*max(0,math.sin(x*.16)*math.cos(y*.4))
            sky.extend((.12+cloud,.25+cloud,.4+cloud,1))
    f.texture([1,1,1,1]*(f.w*f.h),1)
    f.texture(sky,3,128,64)
    target=f.texture(None,4); material=f.texture(None,5)
    base=dict(viewWidth=float(f.w),viewHeight=float(f.h),gbufferProjection=projection,
        gbufferProjectionInverse=inverse,gbufferModelView=model,gbufferModelViewInverse=model_inverse,
        sunPosition=(0.,1.,0.),shadowLightPosition=(0.,-1.,0.),frameTimeCounter=12.,
        near=near,far=far,frameTime=1/60,isEyeInWater=0,gtexture=1,colortex6=0,depthtex1=2,
        colortex7=3,rainStrength=0.,testVertexBias=(0.,0.,0.))
    def scene(height,forebank=False):
        depths=[]; colors=[]
        for y in range(f.h):
            ry=(2*(y+.5)/f.h-1)/fy
            for x in range(f.w):
                rx=(2*(x+.5)/f.w-1)/fx
                # An opaque floor, or a dry bank above the water on the left.
                bottom=-3. if not forebank or x>=f.w//2 else .08
                t=-(height-bottom)/(cs*ry-sn)
                depths.extend(((-a+b/t)*.5+.5,0,0,1))
                wx=rx*t; wz=(sn*ry-cs)*t
                color=.3+.12*math.sin(wx*1.7)+.1*math.cos(wz*.7)
                colors.extend((color,color*.8,color*.55,1))
        f.texture(colors,0); f.texture(depths,2)
    code=fragment(values)
    p=f.program('composite7.fsh',values,fragment=code,vertex_source=vertex)
    diagnostics=code.replace('color = vec4(max(result, vec3(0.0)), 1.0);',
        'color=vec4((refractUV-screenUV)*vec2(viewWidth/viewHeight,1),refractWeight,1);')
    pd=f.program('composite7.fsh',values,fragment=diagnostics,vertex_source=vertex)
    flat_values=dict(values,WATER_WAVES='0.0')
    flat_code=fragment(flat_values).replace('color = vec4(max(result, vec3(0.0)), 1.0);',
        'color=vec4((refractUV-screenUV)*vec2(viewWidth/viewHeight,1),refractWeight,1);')
    pf=f.program('composite7.fsh',flat_values,fragment=flat_code,vertex_source=vertex)
    for height in (.15,1.62,2.87):
        scene(height)
        u=dict(base,cameraPosition=(0.,height,0.))
        current=f.render(p,[target,material],u)
        biased=f.render(p,[target,material],dict(u,testVertexBias=(.03,.15,-.2)))
        assert max(abs(x-y) for x,y in zip(current,biased))<1e-5, \
            'Water optics drift when interpolated vertex camera frame differs from rasterized depth'
        d=f.render(pd,[target,material],u)
        assert all(math.isfinite(v) for v in current+d), 'Non-finite water optics near camera'
        maximum=max(math.hypot(d[i],d[i+1]) for i in range(0,len(d),4))
        assert maximum<=.012001, f'Near-camera refraction jumps too far: {maximum}'
        flat=f.render(pf,[target,material],u)
        assert max(abs(v) for i,v in enumerate(flat) if i%4<2)<1e-6, \
            'Flat water still scales/translates the entire riverbed when moving the camera'
        for rain in (0.,1.):
            reference=f.render(p,[target,material],dict(u,rainStrength=rain))
            scene(height+.002)
            moved=f.render(p,[target,material],dict(u,rainStrength=rain,cameraPosition=(0.,height+.002,0.)))
            error=sum(abs(x-y) for x,y in zip(reference,moved))/len(reference)
            assert error<.006, f'Refraction-enabled water changes abruptly over 2mm: {error}'
            scene(height)
    scene(1.62,True)
    bank=f.render(pd,[target,material],dict(base,cameraPosition=(0.,1.62,0.)))
    assert max(bank[(y*f.w+x)*4+2] for y in range(f.h) for x in range(f.w//2-4))<1e-6, \
        'Refraction warped dry foreground terrain across the shoreline'
    no_ssr=dict(values,SSR=False)
    scene(1.62)
    ssr=f.render(p,[target,material],dict(base,cameraPosition=(0.,1.62,0.)))
    pm=f.program('composite7.fsh',no_ssr,fragment=fragment(no_ssr),vertex_source=vertex)
    missed=f.render(pm,[target,material],dict(base,cameraPosition=(0.,1.62,0.)))
    assert max(abs(x-y) for x,y in zip(ssr,missed))<.0002, \
        'SSR misses change the environment reflection lobe'
    print('PASS: GPU depth-based water optics ignore vertex-camera mismatch at near/jump heights',flush=True)
    print('PASS: GPU refraction enabled: bounded distortion, no flat-plane zoom, dry-bank rejection, 2mm dry/rain motion',flush=True)
    print('PASS: GPU depth-based water SSR misses match environment fallback',flush=True)
    # DH water rasterizes with a different projection from vanilla terrain.
    dh_near,dh_far=2.,4096.
    da=-(dh_far+dh_near)/(dh_far-dh_near); db=-2*dh_far*dh_near/(dh_far-dh_near)
    dh_projection=[fx,0,0,0,0,fy,0,0,0,0,da,-1,0,0,db,0]
    dh_inverse=[1/fx,0,0,0,0,1/fy,0,0,0,0,0,1/db,0,0,-1,da/db]
    dh_code=api['source'](api['ROOT']/'dh_water.fsh',values,True)
    dh_code=dh_code.replace('in vec3 viewNormal, viewPos, worldPos;',
        '''in vec3 viewNormal,viewPos;
vec3 testDHSurface(){vec4 p=dhProjectionInverse*vec4(gl_FragCoord.xy/vec2(viewWidth,viewHeight)*2-1,gl_FragCoord.z*2-1,1);return p.xyz/p.w;}
#define worldPos ((gbufferModelViewInverse*vec4(testDHSurface(),1)).xyz+cameraPosition)''')
    dh_program=f.program('composite7.fsh',values,fragment=dh_code,vertex_source=vertex)
    dh_depth=[]
    for y in range(f.h):
        ry=(2*(y+.5)/f.h-1)/fy
        t=-48/(cs*ry-sn)
        dh_depth.extend([(-da+db/t)*.5+.5,0,0,1]*f.w)
    f.texture(dh_depth,6)
    f.texture([1,0,0,1]*(f.w*f.h),2)
    normal_target=f.texture(None,7)
    dh_u=dict(base,cameraPosition=(0.,45.,0.),gbufferProjection=dh_projection,
              dhProjectionInverse=dh_inverse,dhDepthTex1=6,depthtex0=2)
    dh_now=f.render(dh_program,[target,normal_target,material],dh_u)
    dh_biased=f.render(dh_program,[target,normal_target,material],dict(dh_u,testVertexBias=(.2,.5,-.4)))
    assert max(abs(x-y) for x,y in zip(dh_now,dh_biased))<1e-5, \
        'DH water reflection/transmission drift with a vertex-camera mismatch'
    assert max(dh_now[0::4])>.02, 'DH perspective fixture discarded all visible water'
    print('PASS: GPU DH water optics use their own raster projection and ignore vertex-camera mismatch',flush=True)
    f.close()
    # At native resolution the roughness lobe should integrate an edge over more
    # than the old one-pixel radius, without blurring low-roughness mirrors.
    f=Fixture(api,640,360)
    colors=[]
    for y in range(f.h):
        for x in range(f.w): colors.extend((float(x>=f.w//2),)*3+(1,))
    f.texture(colors,0); f.texture([1,0,0,1]*(f.w*f.h),2)
    target=f.texture(None,4)
    prefix=api['source'](api['ROOT']/'gbuffers_water.fsh',values,False).split('void main(){')[0]
    u=dict(base,viewWidth=float(f.w),viewHeight=float(f.h),gbufferProjection=identity,
           gbufferProjectionInverse=identity,gbufferModelViewInverse=identity)
    outputs=[]
    for roughness in (.06,.14):
        fragment=prefix+f'void main(){{color=vec4(waterReflectionSample(gl_FragCoord.xy/vec2(viewWidth,viewHeight),{roughness}),1);}}'
        program=f.program('composite7.fsh',values,fragment=fragment)
        outputs.append(f.render(program,[target],u))
    index=((f.h//2)*f.w+f.w//2-3)*4
    assert outputs[0][index]<1e-5 and outputs[1][index]>.04, \
        'Native rough-water reflection still has a one-pixel edge filter'
    assert min(outputs[1])>=0 and max(outputs[1])<=1.00001, 'Reflection filter creates ringing/energy overshoot'
    f.texture([.3,.4,.6,1]*(f.w*f.h),0)
    constant=f.render(program,[target],u)
    assert max(abs(v-(.3,.4,.6,1)[i%4]) for i,v in enumerate(constant))<1e-5, \
        'Rough-water reflection filter changes constant radiance'
    print('PASS: GPU native rough reflection integrates edges, retains mirror detail and preserves radiance',flush=True)
    f.close()

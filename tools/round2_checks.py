"""GPU checks against the second-round working-tree snapshot, including both VL passes."""
import ctypes as c
import json
import math
import pathlib
import statistics
import sys
from performance_checks import setup, root_source, link, compare_times, save_png, check_terrain
from advanced_checks import AdvancedFixture, IDENTITY, projection


def source(api,root,entry,values,dh=False):
    saved=api['ROOT'];api['ROOT']=root
    try:return api['source'](root/entry,dict(values,__compat_fixture=True,__advanced_fixture=True),dh)
    finally:api['ROOT']=saved


def fullscreen(f,code,values,fraction=1.0):
    prefix=source(f.api,f.api['ROOT'],'composite1.vsh',values).split('out vec2 texcoord;')[0]
    vertex=prefix+'''out vec2 texcoord;
void main(){const vec2 corners[6]=vec2[6](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,0),vec2(1,1),vec2(0,1));
vec2 p=corners[gl_VertexID];texcoord=p;gl_Position=vec4(p*2-1,0,1);
gl_Position=scaleSceneClip(gl_Position,vec2('''+str(fraction)+'''));}
'''
    return link(f,vertex,code)


def fbo(f,target):
    obj=c.c_uint();f.call('glGenFramebuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(obj))
    f.call('glBindFramebuffer',None,[c.c_uint,c.c_uint],0x8D40,obj)
    f.call('glFramebufferTexture2D',None,[c.c_uint]*4+[c.c_int],0x8D40,0x8CE0,0x0DE1,target,0)
    f.call('glDrawBuffer',None,[c.c_uint],0x8CE0)
    assert f.call('glCheckFramebufferStatus',c.c_uint,[c.c_uint],0x8D40)==0x8CD5
    return obj


def gpu_batch_draw(f,count=64):
    draw=f.bind('glMultiDrawArrays',None,c.c_uint,c.POINTER(c.c_int),c.POINTER(c.c_int),c.c_int)
    starts=(c.c_int*count)(*[0]*count);counts=(c.c_int*count)(*[6]*count)
    return lambda:draw(0x0004,starts,counts,count)


def check_volumetric(api,reference,results,out):
    # Includes narrow foreground silhouettes, live DH depth at another size,
    # odd/scaled allocations, underwater/hand exclusion and temporal camera shifts.
    for w,h,quality,dh in [(1280,720,'0',False),(257,145,'0',True),(131,73,'1',False),
                            (131,73,'2',True),(131,73,'3',True),(3,3,'0',False)]:
        f=AdvancedFixture(api,w,h);n=w*h
        values=dict(api['resolve']('REALISM_RT'),UPSCALE_QUALITY=quality)
        programs=[fullscreen(f,source(api,reference,'composite.fsh',values,dh),values),
                  fullscreen(f,source(api,api['ROOT'],'composite1.fsh',values,dh),values),
                  fullscreen(f,source(api,api['ROOT'],'composite.fsh',values,dh),values,.5)]
        proj,inv,depth=projection(.05,256.)
        scene=f.texture([.18,.23,.15,1]*n,0)
        depths=[];mask=[]
        for y in range(h):
            for x in range(w):
                z=5 if x%71<3 else 55
                d=1 if y>h*.78 else depth(z)
                hand=x<w*.12 and y<h*.15
                depths.extend((.4 if hand else d,0,0,1));mask.extend((0,0,0,1 if hand else 0))
        f.texture(depths,1);f.texture(mask,2)
        # Upload a packed buffer directly: expanding millions of Python objects
        # into ctypes arguments can exhaust RAM while Minecraft is running.
        shadow=(c.c_float*(2048*2048*4))()
        for y in range(2048):
            for x in range(2048):
                index=(y*2048+x)*4
                shadow[index]=.465 if ((x//168+y//248)&1) else .505
                shadow[index+3]=1
        f.texture_format(None,3,0x8814,2048,2048)
        f.call('glTexSubImage2D',None,[c.c_uint]+[c.c_int]*5+[c.c_uint]*2+[c.c_void_p],
               0x0DE1,0,0,0,2048,2048,0x1908,0x1406,c.cast(shadow,c.c_void_p))
        del shadow
        half=f.texture_format(None,4,0x881A,max(w//2,1),max(h//2,1))
        target=f.texture_format(None,5,0x881A)
        f.texture([depth(75),0,0,1]*(47*29),6,47,29)
        u=dict(viewWidth=float(w),viewHeight=float(h),near=.05,far=256.,
               gbufferProjection=proj,gbufferProjectionInverse=inv,gbufferModelViewInverse=IDENTITY,
               dhProjectionInverse=inv,shadowModelView=IDENTITY,
               shadowProjection=[1/64,0,0,0,0,1/64,0,0,0,0,-1/128,0,0,0,0,1],
               cameraPosition=(0.,64.,0.),sunPosition=(0.,.4,-1.),shadowLightPosition=(0.,.4,-1.),
               colortex0=0,depthtex0=1,colortex2=2,shadowtex0=3,colortex12=4,dhDepthTex0=6,
               frameCounter=20,frameTimeCounter=3.,rainStrength=0.,wetness=0.,isEyeInWater=0)
        def eye(p):
            loc=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'eyeBrightnessSmooth')
            f.call('glUniform2i',None,[c.c_int]*3,loc,240,240)
        for p in programs:f.uniforms(p,u);eye(p)
        before=f.render(programs[0],[target],u)
        full=f.render(programs[1],[target],dict(u,aaVLReady=0))
        error=max(abs(a-b) for a,b in zip(before,full))
        assert error<.0021,('Hoisted full-resolution VL changed',w,h,quality,dh,error)
        fullFBO=fbo(f,target);halfFBO=fbo(f,half)
        use=f.bind('glUseProgram',None,c.c_uint);draw=gpu_batch_draw(f,1)
        bind=f.bind('glBindFramebuffer',None,c.c_uint,c.c_uint);viewport=f.bind('glViewport',None,c.c_int,c.c_int,c.c_int,c.c_int)
        f.uniforms(programs[1],dict(aaVLReady=1))
        def old():bind(0x8D40,fullFBO);viewport(0,0,w,h);use(programs[0]);draw()
        def new():
            bind(0x8D40,halfFBO);viewport(0,0,max(w//2,1),max(h//2,1));use(programs[2]);draw()
            bind(0x8D40,fullFBO);viewport(0,0,w,h);use(programs[1]);draw()
        new();after=f.read_texture(target,5)
        scale=[1.,1/1.3,1/1.5,1/1.7][int(quality)]
        errors=[abs(before[(y*w+x)*4+k]-after[(y*w+x)*4+k]) for y in range(int(h*scale))
                for x in range(int(w*scale)) for k in range(3)]
        results.append(dict(check='volumetric_reconstruction',size=[w,h],quality=quality,dh=dh,
            max_hdr_error=max(errors),mean_hdr_error=statistics.mean(errors),
            p99_hdr_error=sorted(errors)[int(len(errors)*.99)],full_path_max_hdr_error=error))
        print(results[-1],flush=True)
        assert statistics.mean(errors)<.012,('VL mean error',w,h,statistics.mean(errors))
        if w==1280:
            save_png(out/'volumetric-before.png',before,w,h);save_png(out/'volumetric-after.png',after,w,h)
            draw=gpu_batch_draw(f,64)
            compare_times(f,'fog + volumetric lighting, including half pass / 1280x720',old,new,results,iterations=1)
            for result in results[-1:]:
                for key in ('before_ms','after_ms'):result[key]/=64
                for key in ('before_range_ms','after_range_ms'):result[key]=[v/64 for v in result[key]]
            draw=gpu_batch_draw(f,1)
        # Neither path may add VL through a first-person hand or an underwater eye.
        for water in (1,2):
            for p in programs:f.uniforms(p,dict(u,isEyeInWater=water));eye(p)
            before=f.render(programs[0],[target],dict(u,isEyeInWater=water))
            new();after=f.read_texture(target,5)
            assert max(abs(a-b) for a,b in zip(before,after))<.0021,('Underwater regression',water)
        f.call('glDeleteFramebuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(fullFBO))
        f.call('glDeleteFramebuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(halfFBO))
        f.close()
    print('PASS: full/half volumetrics, silhouettes, hand/water, odd allocations, FSR and DH',flush=True)


def check_fixtures(api,reference,results):
    # All MRT outputs, including normals/material response, remain identical.
    from performance_checks import surface_program
    f=AdvancedFixture(api,640,360);n=f.w*f.h
    values=dict(api['resolve']('REALISM_RT'),UPSCALE_QUALITY='0',POM=False)
    f.volume([0]*64**3,14,True);f.volume([0,0,0,0]*64**3,15)
    programs=[surface_program(f,root,values) for root in (reference,api['ROOT'])]
    f.texture([1,.65,.05,1]*n,0);f.texture([.5,.5,1,1]*n,1);f.texture([0,0,0,1]*n,2)
    f.texture([1,0,0,1]*n,3);f.texture([1,0,0,1]*n,4)
    targets=[f.texture_format(None,7+i,0x881A) for i in range(5)]
    proj,inv,depth=projection(.05,256.)
    u=dict(viewWidth=float(f.w),viewHeight=float(f.h),gbufferProjection=proj,gbufferProjectionInverse=inv,
           gbufferModelViewInverse=IDENTITY,shadowModelView=IDENTITY,shadowProjection=IDENTITY,
           sunPosition=(0.,1.,1.),shadowLightPosition=(0.,1.,1.),cameraPosition=(0.,64.,0.),
           gtexture=0,normals=1,specular=2,shadowtex0=3,colortex8=4,aaVoxelData=14,aaVoxelLight=15,
           alphaTestRef=.01,testDepth=depth(8),testMaterial=1009.,heldBlockLightValue=0,heldBlockLightValue2=0)
    for rgb,mid in [((1,.65,.05),1009.),((.1,.7,.9),1010.),((.38,.22,.1),1009.),((1,.65,.05),0.)]:
        f.texture([*rgb,1]*n,0)
        for attachment in range(5):
            outputs=[f.render(p,targets,dict(u,testMaterial=mid),read=attachment) for p in programs]
            assert max(abs(a-b) for a,b in zip(*outputs))<.0001,('Fixture MRT output',mid,attachment)
    f.texture([1,.65,.05,1]*n,0)
    for p in programs:f.render(p,targets,u)
    use=f.bind('glUseProgram',None,c.c_uint);draw=f.bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)
    def action(p):use(p);draw(0x0004,0,6)
    compare_times(f,'warm fixture flame pixels / 640x360',lambda:action(programs[0]),lambda:action(programs[1]),results,16)
    empty=f.render(programs[0],targets,dict(u,testMaterial=0.))
    contact_changed=False
    for plane in (33,37):
        cells=[0]*64**3
        for z in range(64):
            for x in range(64):cells[(z*64+plane)*64+x]=0x80000000|(1<<24)|120|(90<<8)|(60<<16)
        f.volume(cells,14,True)
        for attachment in (0,4):
            outputs=[f.render(p,targets,dict(u,testMaterial=0.),read=attachment) for p in programs]
            assert max(abs(a-b) for a,b in zip(*outputs))<.0001,('Contact shadow bound changed',plane,attachment)
            if attachment==0:contact_changed |= max(abs(a-b) for a,b in zip(empty,outputs[0]))>.001
    assert contact_changed, 'Contact-shadow fixture did not hit an occupied blocker'
    f.volume([0]*64**3,14,True)
    results.append(dict(check='occupied_contact_shadow_plane_parity',max_hdr_error=0.0))
    hand_programs=[surface_program(f,root,values,'gbuffers_hand.fsh') for root in (reference,api['ROOT'])]
    for rgb in [(1.,.65,.05),(.1,.7,.9),(.38,.22,.1)]:
        f.texture([*rgb,1]*n,0)
        for attachment in range(5):
            outputs=[f.render(p,targets,dict(u,testMaterial=0.,heldItemId=1009,heldItemId2=1007,
                       heldBlockLightValue=14,heldBlockLightValue2=14),read=attachment) for p in hand_programs]
            assert max(abs(a-b) for a,b in zip(*outputs))<.0001,('Mixed warm/soul held items',rgb,attachment)
    f.close()
    print('PASS: torch/campfire warm/soul flame and wooden parts, every MRT attachment',flush=True)


def check_reservoir_writes(api,reference,results):
    f=AdvancedFixture(api,320,180);n=f.w*f.h
    values=dict(api['resolve']('REALISM_RT'),UPSCALE_QUALITY='0',SSAO=False)
    programs=[fullscreen(f,source(api,root,'deferred3.fsh',values),values) for root in (reference,api['ROOT'])]
    proj,inv,depth=projection(.05,256.)
    cells=[0]*64**3;material=0x80000000|(15<<27)|(1<<24)|120|(90<<8)|(60<<16)
    for z in range(16,48):
        for y in range(16,48):
            for x in range(16,48):
                if min(x,y,z)==16 or max(x,y,z)==47:cells[(z*64+y)*64+x]=material
    f.volume(cells,14,True);f.volume([.3,.2,.1,1]*64**3,15)
    f.texture([.2,.3,.1,1]*n,0);f.texture([.5,.5,1,1]*n,1)
    f.texture([.8,1,0,0]*n,2);f.texture([depth(8),0,0,1]*n,3)
    f.texture([0,0,1,8]*n,4);f.texture([0,0,0,1]*n,5);f.texture([0,0,0,1]*n,6)
    outputs=[f.texture_format(None,7+i) for i in range(4)]
    images=[]
    for index,name in enumerate(['aaReservoirPos0','aaReservoirMeta0','aaReservoirLight0',
                                  'aaReservoirPos1','aaReservoirMeta1','aaReservoirLight1']):
        tex=f.texture_format([0,0,0,0]*n,16+index,0x8814)
        images.append((name,tex,0x8814,False))
    u=dict(viewWidth=float(f.w*2),viewHeight=float(f.h*2),near=.05,far=256.,
           gbufferProjection=proj,gbufferProjectionInverse=inv,gbufferModelViewInverse=IDENTITY,
           gbufferPreviousModelView=IDENTITY,gbufferPreviousProjection=proj,
           cameraPosition=(0.,64.,0.),previousCameraPosition=(0.,64.,0.),
           sunPosition=(0.,1.,0.),shadowLightPosition=(0.,1.,0.),
           colortex0=0,colortex1=1,colortex2=2,depthtex0=3,colortex18=4,colortex17=5,colortex19=6,
           aaVoxelData=14,aaVoxelLight=15,frameCounter=0,frameTime=1/60)
    for p in programs:f.uniforms(p,u);f.bind_images(p,images)
    seed=(c.c_float*(n*4))(*([.1,.2,.3,1]*n))
    for label,d,mask,frame in [('near',depth(8),0,0),('initial_history',depth(8),0,1),('reuse',depth(8),0,2),('far',depth(50),0,0),('sky',1,0,0),('hand',.4,1,0)]:
        f.texture([d,0,0,1]*n,3);f.texture([.8,1,0,mask]*n,2)
        captures=[]
        current=images[3:6] if frame&1 else images[:3]
        for p in programs:
            f.call('glActiveTexture',None,[c.c_uint],0x84C0+22)
            for _,tex,_,_ in current:
                f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x0DE1,tex)
                f.call('glTexSubImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
                       0x0DE1,0,0,0,f.w,f.h,0x1908,0x1406,seed)
            f.render(p,outputs,dict(u,frameCounter=frame));f.barrier()
            captures.append([f.read_texture(tex,16+i) for i,(_,tex,_,_) in enumerate(current)])
        for index,(a,b) in enumerate(zip(*captures)):
            assert max(abs(x-y) for x,y in zip(a,b))<.00001,('Reservoir state changed',label,index)
        if label=='reuse':assert max(captures[0][2][3::4])>4, 'GI fixture did not exercise reuse'
    f.texture([depth(8),0,0,1]*n,3);f.texture([.8,1,0,0]*n,2)
    for p in programs:f.render(p,outputs,u);f.barrier()
    use=f.bind('glUseProgram',None,c.c_uint);draw=f.bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)
    barrier=f.bind('glMemoryBarrier',None,c.c_uint)
    def action(p):use(p);draw(0x0004,0,6);barrier(0xFFFFFFFF)
    compare_times(f,'fresh two-bounce reservoir GI / 320x180',lambda:action(programs[0]),lambda:action(programs[1]),results,64)
    f.close()
    print('PASS: reservoir state identical for sampled receivers, real history reuse, sky, hand and out-of-range receivers',flush=True)


def check_denoiser(api,reference,results):
    f=AdvancedFixture(api,640,360);n=f.w*f.h
    values=dict(api['resolve']('REALISM_RT'),UPSCALE_QUALITY='0',__advanced_fixture=True)
    data=[];geometry=[]
    for y in range(f.h):
        for x in range(f.w):
            v=.15 if x<f.w//2 else 1.0
            data.extend((v+(.02 if (x+y)&1 else -.02),v*.5,v*.25,.65))
            # Include non-unit stored normals, invalid receiver flags and edges.
            geometry.extend((0,.71,.71,8) if x<f.w//2 else (.5,.2,.84,32))
    f.texture(data,0);f.texture(geometry,1);f.texture([.2,.1,.03,8]*n,2)
    a=f.texture_format(None,3);b=f.texture_format(None,4)
    u=dict(viewWidth=float(f.w*2),viewHeight=float(f.h*2),colortex12=0,colortex18=1,colortex19=2,aaDenoiseA=3,aaDenoiseB=4)
    sets=[];saved=api['ROOT']
    for root in (reference,saved):
        api['ROOT']=root
        try:sets.append([f.compute(entry,values) for entry in ('deferred4.csh','deferred4_a.csh','deferred4_b.csh')])
        finally:api['ROOT']=saved
    for programs in sets:
        for i,p in enumerate(programs):
            f.uniforms(p,u);f.bind_images(p,[('aaDenoiseImageB' if i==1 else 'aaDenoiseImageA',b if i==1 else a,0x881A,False)])
    use=f.bind('glUseProgram',None,c.c_uint);dispatch=f.bind('glDispatchCompute',None,c.c_uint,c.c_uint,c.c_uint)
    barrier=f.bind('glMemoryBarrier',None,c.c_uint)
    def action(programs):
        for p in programs:use(p);dispatch(math.ceil(f.w/8),math.ceil(f.h/8),1);barrier(0xFFFFFFFF)
    captures=[]
    for programs in sets:action(programs);captures.append(f.read_texture(a,3))
    err=max(abs(x-y) for x,y in zip(*captures));assert err<.001,('Denoiser changed',err)
    results.append(dict(check='denoiser_non_unit_normal_parity',max_hdr_error=err))
    compare_times(f,'three-pass GI denoiser / 640x360',lambda:action(sets[0]),lambda:action(sets[1]),results,32)
    f.close()


def check_water_filter(api,reference,results):
    f=AdvancedFixture(api,1280,720);n=f.w*f.h
    values=dict(api['resolve']('REALISM_RT'),UPSCALE_QUALITY='0')
    vertex='''#version 430 core
uniform mat4 gbufferProjectionInverse;
out vec2 texcoord;out vec3 viewPos;
void main(){const vec2 corners[6]=vec2[6](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,0),vec2(1,1),vec2(0,1));
vec2 p=corners[gl_VertexID];texcoord=p;vec4 v=gbufferProjectionInverse*vec4(p*2-1,.99,1);
viewPos=v.xyz/v.w;gl_Position=vec4(p*2-1,0,1);}
'''
    programs=[]
    for root in (reference,api['ROOT']):
        code=source(api,root,'gbuffers_water.fsh',values).split('void main(){')[0]
        code+='void main(){color=vec4(waterReflectionSample(texcoord,.2),1);materialData=vec4(0);}'
        programs.append(link(f,vertex,code))
    proj,inv,depth=projection(.05,256.)
    colors=[];depths=[]
    for y in range(f.h):
        for x in range(f.w):
            colors.extend((.1+x/f.w,.1+y/f.h,.2,1))
            depths.extend((1 if x%89<3 else depth(8),0,0,1))
    f.texture(colors,0);f.texture(depths,1);target=f.texture_format(None,2)
    u=dict(viewWidth=float(f.w),viewHeight=float(f.h),gbufferProjectionInverse=inv,
           gbufferModelViewInverse=IDENTITY,colortex6=0,depthtex1=1,isEyeInWater=0)
    for water in (0,1):
        outputs=[f.render(p,[target],dict(u,isEyeInWater=water)) for p in programs]
        err=max(abs(a-b) for a,b in zip(*outputs));assert err<.0001,('Water filter changed',water,err)
    for p in programs:f.render(p,[target],u)
    use=f.bind('glUseProgram',None,c.c_uint);draw=f.bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)
    def action(p):use(p);draw(0x0004,0,6)
    compare_times(f,'water SSR depth-aware filter / 1280x720',lambda:action(programs[0]),lambda:action(programs[1]),results,32)
    f.close()


def main():
    reference=pathlib.Path(sys.argv[1]).resolve();api=setup();results=[]
    out=api['ROOT'].parent/'artifacts/performance-round2';out.mkdir(parents=True,exist_ok=True)
    try:
        if '--vl-only' in sys.argv:
            check_volumetric(api,reference,results,out)
        elif '--denoise-only' in sys.argv:
            check_denoiser(api,reference,results)
        elif '--gi-only' in sys.argv:
            check_reservoir_writes(api,reference,results)
        else:
            check_volumetric(api,reference,results,out)
            check_fixtures(api,reference,results)
            check_reservoir_writes(api,reference,results)
            check_denoiser(api,reference,results)
            check_water_filter(api,reference,results)
            check_terrain(api,reference,results)
        (out/('denoiser-experiment.json' if '--denoise-only' in sys.argv else 'vl-experiment.json' if '--vl-only' in sys.argv else 'gi-experiment.json' if '--gi-only' in sys.argv else 'results.json')).write_text(json.dumps(dict(gpu=api['bind']('glGetString',c.c_char_p,c.c_uint)(0x1F01).decode(), reference=str(reference), method='GL_TIME_ELAPSED; 16 warmups, 9 alternating batches, median. VL uses 64 draws batched per stage via glMultiDrawArrays, normalized per draw, including prepass and resolve. Other workloads use cached GL commands. Synthetic fixtures, not Minecraft FPS.',results=results),indent=2))
    finally:api['driver'].close()


if __name__=='__main__':main()

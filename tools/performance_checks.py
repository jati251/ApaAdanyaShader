"""Native GPU timings and before/after image checks; no Minecraft FPS claims.

python tools/performance_checks.py /path/to/reference/shaders --advanced
The reference must be a complete working tree snapshot, not Git HEAD.
"""
import ctypes as c
import json
import math
import pathlib
import random
import statistics
import struct
import sys
import zlib
from build_cloud_noise import setup
from quality_checks import Fixture
from advanced_checks import AdvancedFixture, IDENTITY, projection


def root_source(api,root,entry,values):
    saved=api['ROOT'];api['ROOT']=root
    try:return api['source'](root/entry,dict(values,__compat_fixture=True,__advanced_fixture=True),False)
    finally:api['ROOT']=saved


def link(f,vertex,fragment):
    a=f.api;vs=f.shader(0x8B31,vertex);fs=f.shader(0x8B30,fragment)
    p=a['create_program']();a['attach'](p,vs);a['attach'](p,fs);a['link'](p)
    status=c.c_int();a['program_status'](p,0x8B82,c.byref(status))
    if not status.value:
        log=c.create_string_buffer(32768);a['program_log'](p,len(log),None,log);raise AssertionError(log.value.decode())
    a['delete_shader'](vs);a['delete_shader'](fs);f.programs.append(p)
    return p


def elapsed(f,action,iterations=4):
    query=c.c_uint();f.call('glGenQueries',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(query))
    f.call('glBeginQuery',None,[c.c_uint,c.c_uint],0x88BF,query)
    for _ in range(iterations):action()
    f.call('glEndQuery',None,[c.c_uint],0x88BF)
    result=c.c_uint64();f.call('glGetQueryObjectui64v',None,[c.c_uint,c.c_uint,c.POINTER(c.c_uint64)],query,0x8866,c.byref(result))
    f.call('glDeleteQueries',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(query))
    assert f.call('glGetError',c.c_uint,[])==0
    return result.value/1e6/iterations


def compare_times(f,name,before,after,results,iterations=4):
    for _ in range(16):before();after()
    f.call('glFinish',None,[])
    old,new=[],[]
    for i in range(9):
        if i&1:
            new.append(elapsed(f,after,iterations));old.append(elapsed(f,before,iterations))
        else:
            old.append(elapsed(f,before,iterations));new.append(elapsed(f,after,iterations))
    a,b=statistics.median(old),statistics.median(new)
    result=dict(workload=name,before_ms=a,after_ms=b,reduction_percent=(1-b/a)*100,
                before_range_ms=[min(old),max(old)],after_range_ms=[min(new),max(new)])
    results.append(result)
    print(f'GPU: {name}: {a:.4f} -> {b:.4f} ms ({result["reduction_percent"]:+.1f}% less time)',flush=True)


def save_png(path,pixels,w,h):
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    rows=[]
    for y in reversed(range(h)):
        row=bytearray([0])
        for x in range(w):
            index=(y*w+x)*4
            for v in pixels[index:index+3]:
                v=max(v,0);v=v/(1+v);v=12.92*v if v<=.0031308 else 1.055*v**(1/2.4)-.055
                row.append(round(max(0,min(1,v))*255))
        rows.append(bytes(row))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))
                     +chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b''))


def cloud_volume(f,unit):
    data=(f.api['ROOT']/'textures/cloud_noise.bin').read_bytes()
    assert len(data)==64**3*4
    tex=c.c_uint();f.call('glGenTextures',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(tex));f.textures.append(tex)
    f.call('glActiveTexture',None,[c.c_uint],0x84C0+unit);f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x806F,tex)
    for prop,val in [(0x2801,0x2601),(0x2800,0x2601),(0x2802,0x2901),(0x2803,0x2901),(0x8072,0x2901)]:
        f.call('glTexParameteri',None,[c.c_uint,c.c_uint,c.c_int],0x806F,prop,val)
    buf=c.create_string_buffer(data)
    f.call('glTexImage3D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
           0x806F,0,0x822D,64,64,64,0,0x1903,0x1406,buf)
    return tex


def check_clouds(api,reference,results,output):
    f=Fixture(api,640,360);values=dict(api['resolve']('REALISM_RT'),UPSCALE_QUALITY='0')
    cloud_volume(f,6);target=f.texture(None,7)
    programs=[]
    for root in (reference,api['ROOT']):
        prefix=root_source(api,root,'prepare.fsh',values).split('in vec2 texcoord;')[0]
        if root==api['ROOT']:prefix=prefix.replace('#define AA_PROCEDURAL_CLOUDS','')
        fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){vec3 rd=normalize(vec3((texcoord.x-.5)*1.6,.06+texcoord.y*.78,1));
color=cloudLayerSteps(rd,gl_FragCoord.xy,CLOUD_STEPS,.5);}
'''
        programs.append(f.program('prepare.fsh',values,fragment=fragment))
    u=dict(viewWidth=float(f.w),viewHeight=float(f.h),cameraPosition=(0.,70.,0.),
           sunPosition=(0.,1.,0.),shadowLightPosition=(0.,1.,0.),gbufferModelViewInverse=IDENTITY,
           frameTimeCounter=0.,rainStrength=0.,aaCloudNoise=6)
    # Verify hardware interpolation against the actual procedural implementation
    # at arbitrary subcell positions away from the intentional periodic boundary.
    prefix=root_source(api,api['ROOT'],'prepare.fsh',values).split('in vec2 texcoord;')[0].replace('#define AA_PROCEDURAL_CLOUDS','')
    frag=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){vec3 p=vec3(texcoord*62.7,.21+fract(texcoord.x*7.13+texcoord.y*2.71)*62.5);
color=vec4(abs(cloudNoise3D(p)-noise3D(p)),0,0,1);}
'''
    p=f.program('prepare.fsh',values,fragment=frag)
    errors=f.render(p,[target],u)[::4]
    assert max(errors)<.008, ('Cloud lattice/interpolation mismatch',max(errors))
    print(f'PASS: native 3D cloud lookup vs procedural noise, max error {max(errors):.6f}',flush=True)
    for label,changes in [('day',{}),('rain',dict(rainStrength=.85)),
                          ('sunset',dict(sunPosition=(1.,.06,0.))),('night',dict(sunPosition=(0.,-1.,0.)))]:
        before,after=[f.render(p,[target],dict(u,**changes)) for p in programs]
        opacity_before=statistics.mean(before[3::4]);opacity_after=statistics.mean(after[3::4])
        assert abs(opacity_before-opacity_after)<.06, (label,'Large cloud coverage shift',opacity_before,opacity_after)
        assert max(after[3::4])>.1, (label,'Clouds disappeared')
        rgb_mae=statistics.mean(abs(a-b) for i,(a,b) in enumerate(zip(before,after)) if i%4!=3)
        results.append(dict(check='cloud_'+label,mean_opacity_before=opacity_before,
                            mean_opacity_after=opacity_after,hdr_rgb_mae=rgb_mae))
        if label=='day':
            save_png(output/'clouds-before.png',before,f.w,f.h);save_png(output/'clouds-after.png',after,f.w,f.h)
    use=f.bind('glUseProgram',None,c.c_uint);draw=f.bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)
    def action(program):use(program);draw(0x0004,0,6)
    for p in programs:f.render(p,[target],u)
    compare_times(f,'cloud layer, 640x360 / 20 steps',lambda:action(programs[0]),lambda:action(programs[1]),results)
    f.close()


def surface_program(f,root,values,entry='gbuffers_terrain.fsh'):
    fragment=root_source(f.api,root,entry,values)
    vertex='''#version 430 core
uniform mat4 gbufferProjectionInverse;
uniform float testDepth,testMaterial;
uniform vec3 cameraPosition;
out vec2 texcoord,lmcoord;out vec4 glcolor;out vec3 viewNormal,viewPos,worldPos;
out vec4 tangent;flat out float materialId;flat out vec4 atlasBounds;
void main(){const vec2 corners[6]=vec2[6](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,0),vec2(1,1),vec2(0,1));
vec2 p=corners[gl_VertexID];texcoord=p;lmcoord=vec2(.1,1);glcolor=vec4(1,1,1,.8);
vec4 vp=gbufferProjectionInverse*vec4(p*2-1,testDepth*2-1,1);viewPos=vp.xyz/vp.w;
worldPos=viewPos+cameraPosition;viewNormal=normalize(vec3(0,.7,.7));tangent=vec4(1,0,0,1);
materialId=testMaterial;atlasBounds=vec4(0,0,1,1);gl_Position=vec4(p*2-1,0,1);}
'''
    return link(f,vertex,fragment)


def check_terrain(api,reference,results):
    f=AdvancedFixture(api,1280,720);n=f.w*f.h
    values=dict(api['resolve']('REALISM_RT'),UPSCALE_QUALITY='0',POM=False)
    f.volume([0]*64**3,14,True);f.volume([0,0,0,0]*64**3,15)
    old=surface_program(f,reference,values);new=surface_program(f,api['ROOT'],values)
    texels=[]
    for y in range(f.h):
        for x in range(f.w):texels.extend((.28+.18*(x/f.w),.34+.10*(y/f.h),.19,1))
    f.texture(texels,0);f.texture([.5,.5,1,1]*n,1);f.texture([0,0,0,1]*n,2)
    shadow=[]
    for y in range(f.h):
        for x in range(f.w):shadow.extend((.46 if x<f.w//2 else .54,0,0,1))
    f.texture(shadow,3);f.texture([1,0,0,1]*n,4)
    targets=[f.texture_format(None,7,0x881A),f.texture_format(None,8,0x881A),
             f.texture_format(None,9,0x8058),f.texture_format(None,10,0x8058),f.texture_format(None,11,0x8058)]
    proj,inv,depth=projection(.05,256)
    f.texture([depth(8),0,0,1]*n,5)
    shadow_matrix=[1/32,0,0,0,0,1/32,0,0,0,0,-1/128,0,0,0,0,1]
    u=dict(viewWidth=float(f.w),viewHeight=float(f.h),gbufferProjection=proj,gbufferProjectionInverse=inv,
           gbufferModelViewInverse=IDENTITY,shadowModelView=IDENTITY,shadowProjection=shadow_matrix,
           sunPosition=(0.,1.,1.),shadowLightPosition=(0.,1.,1.),cameraPosition=(0.,64.,0.),
           gtexture=0,normals=1,specular=2,shadowtex0=3,colortex8=4,depthtex0=5,
           colortex0=7,colortex1=8,colortex2=9,colortex3=10,colortex15=11,
           alphaTestRef=.01,testDepth=depth(8),testMaterial=0.,heldBlockLightValue=0,heldBlockLightValue2=0)
    u.update(aaVoxelData=14,aaVoxelLight=15)
    # Ordinary forward shading must remain identical. Exercise diffuse,
    # fractional subsurface and metals, as well as the emissive overrides below.
    for material,blue,green,label in [(0.,0.,0.,'stone'),(1002.,0.,0.,'leaves'),
                                      (0.,.55,0.,'fractional_subsurface'),(0.,0.,230/255,'metal')]:
        f.texture([.18,green,blue,1]*n,2)
        before=f.render(old,targets,dict(u,testMaterial=material))
        after=f.render(new,targets,dict(u,testMaterial=material))
        errors=[abs(a-b) for i,(a,b) in enumerate(zip(before,after)) if i%4!=3]
        assert max(errors)<.0001, (label,'Ordinary material lighting changed',max(errors))
        results.append(dict(check='terrain_'+label,max_hdr_rgb_error=max(errors),mean_hdr_rgb_error=statistics.mean(errors)))
    f.texture([0,0,0,1]*n,2)
    # Both paths now share the same FBO. Bind it before timing so Python/FBO
    # setup time is excluded from the GPU query as much as possible.
    use=f.bind('glUseProgram',None,c.c_uint);draw_arrays=f.bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)
    def draw(p):
        use(p);draw_arrays(0x0004,0,6)
    for p in (old,new):f.render(p,targets,u)
    compare_times(f,'ordinary terrain, 1280x720 / voxel profile',lambda:draw(old),lambda:draw(new),results)
    # Emissive overrides remain exactly equivalent.
    for mid in (1006.,1007.,1008.,1009.,1010.):
        a=f.render(old,targets,dict(u,testMaterial=mid));b=f.render(new,targets,dict(u,testMaterial=mid))
        assert max(abs(x-y) for x,y in zip(a,b))<.0001, ('Emissive changed',mid)
    for p in (old,new):f.render(p,targets,dict(u,testMaterial=1008.))
    compare_times(f,'lava surface / 1280x720',lambda:draw(old),lambda:draw(new),results)
    print('PASS: ordinary/fractional subsurface/metal/emissive surface parity',flush=True)
    f.close()


def check_voxels(api,reference,results):
    f=AdvancedFixture(api,32,16);values=dict(api['resolve']('REALISM_RT'),__advanced_fixture=True)
    cells=[0]*64**3;material=0x80000000|(1<<24)|120|(90<<8)|(60<<16)
    voxel=f.volume(cells,4,True);light=f.volume(None,5);f.texture([1,0,0,1]*512,1)
    uniforms=dict(gbufferModelViewInverse=IDENTITY,shadowModelView=IDENTITY,shadowProjection=IDENTITY,
                  cameraPosition=(0.,64.,0.),sunPosition=(0.,1.,0.),shadowLightPosition=(0.,1.,0.),
                  aaVoxelData=4,aaVoxelLight=5,shadowtex0=1)
    old_root=api['ROOT'];programs=[]
    for root in (reference,old_root):
        api['ROOT']=root
        try:programs.append(f.compute('shadowcomp.csh',values))
        finally:api['ROOT']=old_root
    images=[('aaVoxelLightImage',light,0x881A,True)]
    rnd=random.Random(17)
    for label in ('terrain','cave','dense','empty'):
        cells=[0]*64**3
        for z in range(64):
            for x in range(64):
                top=20+round(7*math.sin(x*.15)*math.cos(z*.11))
                for y in range(64):
                    solid=(y<=top) if label=='terrain' else ((y<12 or 40<=y<44) if label=='cave' else (rnd.random()<.35 if label=='dense' else False))
                    if solid:cells[(z*64+y)*64+x]=material
        f.call('glActiveTexture',None,[c.c_uint],0x84C0+4);f.call('glBindTexture',None,[c.c_uint]*2,0x806F,voxel)
        buf=(c.c_uint*len(cells))(*cells)
        f.call('glTexSubImage3D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],0x806F,0,0,0,0,64,64,64,0x8D94,0x1405,buf)
        captures=[]
        for p,groups in zip(programs,[(16,16,16),(16,1,64)]):
            f.dispatch(p,groups,uniforms,images);captures.append(f.read_texture(light,5,volume=True))
        assert max(abs(a-b) for a,b in zip(*captures))<.00001, ('Voxel column visibility changed',label)
        for p in programs:f.uniforms(p,uniforms);f.bind_images(p,images)
        use=f.bind('glUseProgram',None,c.c_uint);dispatch=f.bind('glDispatchCompute',None,c.c_uint,c.c_uint,c.c_uint)
        barrier=f.bind('glMemoryBarrier',None,c.c_uint)
        def action(p,groups):use(p);dispatch(*groups);barrier(0xFFFFFFFF)
        compare_times(f,'voxel cache / '+label,lambda:action(programs[0],(16,16,16)),
                      lambda:action(programs[1],(16,1,64)),results,iterations=64)
    # Compare ray traversal on sparse and dense grids, including zero direction
    # components and exact cell-edge/corner ties. Use identical rays per pixel.
    cells=[material if x==40 or y==48 else 0 for z in range(64) for y in range(64) for x in range(64)]
    buf=(c.c_uint*len(cells))(*cells)
    f.call('glActiveTexture',None,[c.c_uint],0x84C0+4);f.call('glBindTexture',None,[c.c_uint]*2,0x806F,voxel)
    f.call('glTexSubImage3D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],0x806F,0,0,0,0,64,64,64,0x8D94,0x1405,buf)
    prefixes=[root_source(api,r,'deferred3.fsh',values).split('in vec2 texcoord;')[0]
              for r in (reference,old_root)]
    ray_programs=[]
    for prefix in prefixes:
        frag=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;uniform vec3 testDirection;uniform float spread;
void main(){vec3 p,n;uint m;vec3 d=normalize(testDirection+vec3(texcoord-.5,0)*spread);
bool hit=traceVoxelWorld(vec3(0,64,0),d,96,p,n,m);color=vec4(hit?p:vec3(0),hit?1:0);}
'''
        ray_programs.append(f.program('deferred3.fsh',values,fragment=frag))
    target=f.texture(None,0)
    for direction in ((1.,0.,0.),(0.,1.,0.),(1.,1.,1.),(-1.,.03,0.),(0.,0.,-1.)):
        captures=[f.render(p,[target],dict(uniforms,testDirection=direction)) for p in ray_programs]
        assert max(abs(a-b) for a,b in zip(*captures))<.00001, ('Voxel DDA changed',direction)
        if direction==(1.,0.,0.):assert captures[0][3]==1, 'DDA fixture did not hit its wall'
    f.w,f.h=512,288
    f.call('glViewport',None,[c.c_int]*4,0,0,f.w,f.h)
    target=f.texture(None,0)
    for p in ray_programs:f.render(p,[target],dict(uniforms,testDirection=(.25,.15,-1.),spread=1.7))
    use=f.bind('glUseProgram',None,c.c_uint);draw=f.bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)
    def rays(p):use(p);draw(0x0004,0,6)
    compare_times(f,'voxel DDA / divergent rays, 512x288',lambda:rays(ray_programs[0]),lambda:rays(ray_programs[1]),results,iterations=16)
    print('PASS: voxel cache parity on terrain/cave/dense/empty grids and DDA ray/tie parity',flush=True)
    f.close()


def check_hiz(api,reference,results):
    for w,h,quality,dh in [(1280,720,'0',False),(129,73,'0',False),(97,55,'2',False),
                            (31,17,'0',False),(97,55,'1',True),(97,55,'3',True)]:
        f=AdvancedFixture(api,w,h);values=dict(api['resolve']('REALISM'),UPSCALE_QUALITY=quality)
        proj,inv,depth=projection(.05,256)
        inv[2]=.07;inv[6]=-.04
        data=[]
        for y in range(h):
            for x in range(w):data.extend((1 if (x+y)%7==0 else depth(3 if x%29==0 else 8+y*.03),0,0,1))
        f.texture(data,0)
        if dh:f.texture([depth(12),0,0,1]*(41*23),2,41,23)
        atlas=f.texture_format(None,1,0x8230)
        u=dict(viewWidth=float(w),viewHeight=float(h),near=.05,gbufferProjectionInverse=inv,
               dhProjectionInverse=inv,depthtex0=0,dhDepthTex0=2,aaHiZ=1)
        programs=[];current=api['ROOT']
        api['ROOT']=reference
        try:
            for entry in ('deferred.csh','deferred_a.csh','deferred_b.csh','deferred_c.csh'):
                programs.append(f.compute(entry,values,dh))
        finally:api['ROOT']=current
        new=f.compute('deferred.csh',values,dh)
        scale=[1.,1/1.3,1/1.5,1/1.7][int(quality)];aw,ah=int(w*scale),int(h*scale)
        images=[('aaHiZImage',atlas,0x8230,False)]
        for p in programs+[new]:f.uniforms(p,u);f.bind_images(p,images)
        use=f.bind('glUseProgram',None,c.c_uint);dispatch=f.bind('glDispatchCompute',None,c.c_uint,c.c_uint,c.c_uint)
        barrier=f.bind('glMemoryBarrier',None,c.c_uint)
        def old_action():
            for level,p in enumerate(programs):
                use(p);dispatch(math.ceil((aw//(2<<level))/8),math.ceil((ah//(2<<level))/8),1);barrier(0xFFFFFFFF)
        def new_action():use(new);dispatch(math.ceil(aw/16),math.ceil(ah/16),1);barrier(0xFFFFFFFF)
        old_action();a=f.read_texture(atlas,1)
        new_action();b=f.read_texture(atlas,1)
        errors=[]
        for level in range(4):
            dx=0 if level==0 else aw//2
            dy=0 if level<2 else ah//4+(ah//8 if level==3 else 0)
            for y in range(ah//(2<<level)):
                for x in range(aw//(2<<level)):
                    index=((y+dy)*w+x+dx)*4
                    errors.extend(abs(a[index+i]-b[index+i]) for i in (0,1))
        assert max(errors,default=0)<.00001, ('Single-dispatch Hi-Z bounds differ',w,h,quality,dh,max(errors))
        if w==1280:compare_times(f,'Hi-Z pyramid / four passes to one, 1280x720',old_action,new_action,results,iterations=32)
        f.close()
    print('PASS: all Hi-Z min/max levels, thin geometry, odd/small viewports, FSR and DH depth sizes match',flush=True)


def main():
    assert len(sys.argv)>1 and '--advanced' in sys.argv,'Supply reference shaders and --advanced'
    reference=pathlib.Path(sys.argv[1]).resolve();assert (reference/'lib/common.glsl').is_file()
    api=setup();results=[]
    output=api['ROOT'].parent/'artifacts/performance';output.mkdir(parents=True,exist_ok=True)
    try:
        check_terrain(api,reference,results)
        check_clouds(api,reference,results,output)
        check_voxels(api,reference,results)
        check_hiz(api,reference,results)
        device=api['bind']('glGetString',c.c_char_p,c.c_uint)(0x1F01).decode()
        (output/'results.json').write_text(json.dumps(dict(gpu=device,reference=str(reference),
            method='GL_TIME_ELAPSED; 16 warmups, 9 alternating batches, median; prebound uniforms/FBO/images; synthetic workloads, not Minecraft FPS',
            results=results),indent=2))
        print('PASS: performance comparison and images saved to '+str(output),flush=True)
    finally:api['driver'].close()


if __name__=='__main__':main()

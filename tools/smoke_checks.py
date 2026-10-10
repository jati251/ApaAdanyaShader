"""Actual campfire vertex capture, 3D smoke integration and depth-aware upsampling.

Run: python tools/validate.py --advanced --smoke-only --profile=MEDIUM
These native OpenGL fixtures do not measure Minecraft FPS or Iris bindings.
"""
import ctypes as c
import json
import math
import statistics
from advanced_checks import AdvancedFixture, IDENTITY, projection
from performance_checks import cloud_volume, elapsed, save_png


def uint_volume(f,unit):
    tex=c.c_uint();f.call('glGenTextures',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(tex));f.textures.append(tex)
    f.call('glActiveTexture',None,[c.c_uint],0x84C0+unit);f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x806F,tex)
    for prop,val in [(0x2801,0x2600),(0x2800,0x2600),(0x2802,0x812F),(0x2803,0x812F),(0x8072,0x812F)]:
        f.call('glTexParameteri',None,[c.c_uint,c.c_uint,c.c_int],0x806F,prop,val)
    f.call('glTexImage3D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
           0x806F,0,0x8236,32,32,32,0,0x8D94,0x1405,(c.c_uint*(32**3))())
    return tex


def update_obstacles(f,tex,unit,camera,blocks):
    data=[0]*(32**3);origin=[math.floor(x)-16 for x in camera]
    for position in blocks:
        x,y,z=[math.floor(position[i])-origin[i] for i in range(3)]
        if all(0<=v<32 for v in (x,y,z)):data[(z*32+y)*32+x]=1
    f.call('glActiveTexture',None,[c.c_uint],0x84C0+unit);f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x806F,tex)
    f.call('glTexSubImage3D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
           0x806F,0,0,0,0,32,32,32,0x8D94,0x1405,(c.c_uint*len(data))(*data))


def flow_cache(f,values,table,obstacles,mature=True):
    paths=f.texture_format(None,10,internal=0x8814,w=22,h=128)
    program=f.compute('shadowcomp1.csh',values)
    def rebuild(camera,time=5.):
        f.dispatch(program,(2,1,1),dict(cameraPosition=camera,frameTimeCounter=time),
            [('aaSmokeEmitterImage',table,0x8236,False),('aaSmokeObstacleImage',obstacles,0x8236,True),('aaSmokePathImage',paths,0x8814,False)])
        if mature:
            # Geometry fixtures exercise an established plume; spawn tests use mature=False.
            f.call('glActiveTexture',None,[c.c_uint],0x84C0+10)
            f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x0DE1,paths)
            emitters=f.read_texture(table,7,128,1,integer=True)
            ages=[v for emitter in emitters for v in ((1.5 if emitter else 0),0,0,0)]
            f.call('glActiveTexture',None,[c.c_uint],0x84C0+10)
            f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x0DE1,paths)
            f.call('glTexSubImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
                   0x0DE1,0,21,0,1,128,0x1908,0x1406,(c.c_float*len(ages))(*ages))
    return paths,rebuild


def uint_texture(f, unit, values):
    tex=f.texture(None,unit,len(values),1)
    for prop in (0x2801,0x2800):
        f.call('glTexParameteri',None,[c.c_uint,c.c_uint,c.c_int],0x0DE1,prop,0x2600)
    f.call('glTexImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
           0x0DE1,0,0x8236,len(values),1,0,0x8D94,0x1405,(c.c_uint*len(values))(*values))
    return tex


def update_uint(f,tex,unit,values):
    f.call('glActiveTexture',None,[c.c_uint],0x84C0+unit)
    f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x0DE1,tex)
    f.call('glTexSubImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
           0x0DE1,0,0,0,len(values),1,0x8D94,0x1405,(c.c_uint*len(values))(*values))


def primary_slot(world):
    return (world[0]*73856093^world[1]*19349663^world[2]*83492791)&63


def overflow_slot(world):
    h=(world[0]*1597334677+world[1]*3812015801+world[2]*2798796415)&0xffffffff
    return 64+((h^(h>>16))&63)


def source_table(camera,sources):
    origin=[math.floor(x)-16 for x in camera];table=[0]*128;packed_sources=[]
    for position,soul in sources:
        world=[math.floor(x) for x in position]
        cell=[world[i]-origin[i] for i in range(3)]
        assert all(0<=v<32 for v in cell)
        priority=int(max(1,min(1023,1023-sum((world[i]+.5-camera[i])**2 for i in range(3)))))
        packed=cell[0]|cell[1]<<5|cell[2]<<10|int(soul)<<15|1<<16|priority<<17
        slot=primary_slot(world);table[slot]=max(table[slot],packed)
        packed_sources.append((world,slot,packed))
    for world,slot,packed in packed_sources:
        if table[slot]!=packed:
            other=overflow_slot(world);table[other]=max(table[other],packed)
    return table


def source_masks(table):
    masks=[0]*4
    for slot,emitter in enumerate(table):
        if emitter:masks[slot//32]|=1<<(slot%32)
    return masks


def run(api):
    blocks=(api['ROOT']/'block.properties').read_text()
    assert 'block.1012=minecraft:campfire:lit=true' in blocks
    assert 'block.1013=minecraft:soul_campfire:lit=true' in blocks
    assert blocks.count('minecraft:campfire')==1 and blocks.count('minecraft:soul_campfire')==1
    values=dict(api['resolve']('MEDIUM'),__advanced_fixture=True,__native_compile=True,
                VOXEL_TRACING=False,HARDWARE_PCF=False,VOLUMETRIC_LIGHT=False)
    check_spawn_and_final_pass(api,values)
    check_capture(api,values)
    check_flow_history(api,values)
    check_roof_fan(api,values)
    check_smooth_response(api,values)
    check_many_seams(api,values)
    check_reconstruction_edges(api,values)
    check_integration(api,values)
    check_particle_switch(api,values)


def check_spawn_and_final_pass(api,values):
    f=AdvancedFixture(api,8,8);count=f.w*f.h
    camera=(.5,2.7,6.);source=(.5,.5,.5)
    registered=source_table(camera,[(source,False)])
    slot=next(i for i,v in enumerate(registered) if v)
    table=uint_texture(f,7,registered);presence=uint_texture(f,8,source_masks(registered))
    obstacles=uint_volume(f,11)
    paths,rebuild=flow_cache(f,values,table,obstacles,mature=False)
    def age(): return f.read_texture(paths,10,22,128)[(slot*22+21)*4]
    curves=[]
    for fps in (30,60):
        update_uint(f,table,7,[0]*128);rebuild(camera,0.)
        update_uint(f,table,7,registered);rebuild(camera,5.)
        assert age()==0, 'A newly placed source starts fully opaque'
        samples=[]
        for frame in range(1,int(1.5*fps)+1):
            rebuild(camera,5.+frame/fps);a=age()
            t=min(a/1.5,1);samples.append(t*t*(3-2*t))
        assert samples[-1]>.999 and max(b-a for a,b in zip([0]+samples,samples))<.04
        curves.append(samples)
    assert max(abs(a-b) for a,b in zip(curves[0],curves[1][1::2]))<.0001
    update_uint(f,table,7,source_table((1.1,2.7,6.),[(source,False)]))
    rebuild((1.1,2.7,6.),6.6)
    assert age()>1.49, 'Camera grid shift restarts spawn fade'
    update_uint(f,table,7,[0]*128);rebuild(camera,6.7)
    assert age()==0, 'Source removal retains age'

    # Run the unmodified final composite, rather than only the smoke library.
    f.texture([.2,.2,.2,1]*count,0);f.texture([1,0,0,1]*count,1)
    f.texture([0,0,0,0]*count,2);cloud_volume(f,9)
    f.texture([.1,.15,.2,.5]*count,14)
    f.texture([1,128,0,128]*count,15)
    target=f.texture(None,16)
    p=f.program('composite1.fsh',dict(values,FOG_ENABLED=False))
    proj,inv,_=projection()
    u=dict(colortex0=0,depthtex0=1,colortex2=2,colortex21=14,colortex12=15,
           aaSmokeSources=7,aaSmokePresence=8,aaSmokePaths=10,aaSmokeObstacles=11,aaCloudNoise=9,
           cameraPosition=camera,gbufferProjectionInverse=inv,gbufferModelViewInverse=IDENTITY,
           viewWidth=8.,viewHeight=8.,far=128.,isEyeInWater=0)
    update_uint(f,presence,8,[0]*4)
    empty=f.render(p,[target],u)
    for bank in range(4):
        masks=[0]*4;masks[bank]=1
        update_uint(f,presence,8,masks)
        result=f.render(p,[target],u)
        assert max(abs(a-b) for a,b in zip(empty,result))>.03, ('Final composite ignores emitter bank',bank)
    print('PASS: actual final composite accepts all four emitter banks; spawn fade is smooth at 30/60 FPS and survives grid shifts',flush=True)
    f.close()


def check_capture(api,values):
    f=AdvancedFixture(api,8,8)
    p=api['create_program']()
    for path in ('shadow_cutout.vsh','shadow_cutout.fsh'):
        shader=api['compile_one'](api['ROOT']/path,values,False)
        api['attach'](p,shader);api['delete_shader'](shader)
    api['link'](p);status=c.c_int();api['program_status'](p,0x8B82,c.byref(status));assert status.value
    f.programs.append(p)
    table=uint_texture(f,7,[0]*128);presence=uint_texture(f,8,[0]*4)
    obstacles=uint_volume(f,11)
    f.uniforms(p,dict(aa_ModelView=IDENTITY,aa_Projection=IDENTITY,shadowModelViewInverse=IDENTITY,
                     shadowModelView=IDENTITY,shadowProjection=IDENTITY,aa_NormalMatrix=IDENTITY[:9]))
    f.bind_images(p,[('aaSmokeEmitterImage',table,0x8236,False),('aaSmokePresenceImage',presence,0x8236,False),('aaSmokeObstacleImage',obstacles,0x8236,True)])
    f.call('glBindFramebuffer',None,[c.c_uint,c.c_uint],0x8D40,0)

    def capture(camera,position,material,clear=True):
        if clear:
            update_uint(f,table,7,[0]*128);update_uint(f,presence,8,[0]*4)
            update_obstacles(f,obstacles,11,camera,[])
        f.uniforms(p,dict(cameraPosition=camera))
        # at_midBlock transforms a mesh vertex to the centre of its real block.
        relative=tuple(position[i]-camera[i]-.5 for i in range(3))+(1.,)
        for name,attribute in dict(aa_Vertex=relative,aa_Color=(1.,1.,1.,1.),aa_Normal=(0.,1.,0.,0.),
                                   mc_Entity=(float(material),0.,0.,0.),at_midBlock=(32.,32.,32.,0.)).items():
            location=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],p,name.encode())
            if location>=0:
                f.call('glDisableVertexAttribArray',None,[c.c_uint],location)
                f.call('glVertexAttrib4f',None,[c.c_uint]+[c.c_float]*4,location,*attribute)
        f.call('glEnable',None,[c.c_uint],0x8C89)
        f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0,0,1)
        f.call('glDisable',None,[c.c_uint],0x8C89);f.barrier()
        return f.read_texture(table,7,128,1,integer=True)

    position=(-2.5,63.5,3.5)
    for camera in [(-2.8,64.3,8.9),(-1.99,65.7,7.8),(-3.01,63.01,5.01)]:
        for material,soul in [(1012,False),(1013,True),(1006,False),(1007,True)]:
            got=capture(camera,position,material)
            assert got==source_table(camera,[(position,soul)]), ('Unstable source/camera origin',got,camera)
            assert f.read_texture(presence,8,4,1,integer=True)==source_masks(got)
        for material in [0,1003,1009,1010,1011]:
            assert not any(capture(camera,position,material)), ('Non-emitter produced environmental smoke',material)
            assert f.read_texture(presence,8,4,1,integer=True)==[0]*4
    camera=(0.,64.,8.);near=(.5,63.5,3.5)
    # Find a different, farther cell hashing to the same slot.
    near_slot=next(i for i,x in enumerate(source_table(camera,[(near,False)])) if x)
    far=next((x+.5,63.5,z+.5) for x in range(-7,8) for z in range(-3,8)
             if (x+.5,63.5,z+.5)!=near and sum((v-camera[i])**2 for i,v in enumerate((x+.5,63.5,z+.5)))>26
             and source_table(camera,[((x+.5,63.5,z+.5),True)])[near_slot])
    for first,second in [(near,far),(far,near)]:
        capture(camera,first,1012 if first==near else 1013)
        got=capture(camera,second,1012 if second==near else 1013,False)
        assert got==source_table(camera,[(near,False),(far,True)]), 'Collision winner depends on draw order'
    # Dense burning areas retain displaced sources in the overflow bank. Check
    # the actual vertex atomics and reverse draw order, including duplicate faces.
    crowded=[((x+.5,63.5,z+.5),bool((x+z)%3==0)) for x in range(-3,4) for z in range(1,8)]
    expected=source_table(camera,crowded)
    assert sum(bool(v) for v in expected)>40, 'Dense emitter table loses too many sources'
    for order in (crowded,list(reversed(crowded))):
        for index,(position,soul) in enumerate(order):
            got=capture(camera,position,1007 if soul else 1006,clear=index==0)
        assert got==expected, 'Dense source capture depends on draw order'
        assert f.read_texture(presence,8,4,1,integer=True)==source_masks(got)
        got=capture(camera,order[-1][0],1007 if order[-1][1] else 1006,False)
        assert got==expected, 'Duplicate fire geometry changes smoke sources'
    capture(camera,near,1012)
    capture(camera,(.5,64.5,3.5),0,False)
    f.call('glActiveTexture',None,[c.c_uint],0x84C0+11);f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x806F,obstacles)
    occupancy=(c.c_uint*(32**3))()
    f.call('glGetTexImage',None,[c.c_uint,c.c_int,c.c_uint,c.c_uint,c.c_void_p],0x806F,0,0x8D94,0x1405,occupancy)
    origin=[math.floor(x)-16 for x in camera]
    cell=[math.floor(v)-origin[i] for i,v in enumerate((.5,64.5,3.5))]
    assert occupancy[(cell[2]*32+cell[1])*32+cell[0]]==1, 'Real shadow vertices did not capture overhead obstacle'
    source_cell=[math.floor(v)-origin[i] for i,v in enumerate(near)]
    assert occupancy[(source_cell[2]*32+source_cell[1])*32+source_cell[0]]==0, 'Emitter blocks its own plume'
    print('PASS: real campfire shadow vertex atomics; warm/soul, negative coordinates, jumps, non-emitter exclusion, nearest-source collision order',flush=True)
    f.close()


def check_flow_history(api,values):
    f=AdvancedFixture(api,8,8);camera=(.99,2.7,6.);source=(.5,.5,.5)
    table=uint_texture(f,7,source_table(camera,[(source,False)]))
    obstacles=uint_volume(f,11);paths,rebuild=flow_cache(f,values,table,obstacles)
    rebuild(camera,5.);baseline=f.read_texture(paths,10,22,128)
    slot=next(i for i,v in enumerate(source_table(camera,[(source,False)])) if v)
    def restore(data):
        f.call('glActiveTexture',None,[c.c_uint],0x84C0+10)
        f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x0DE1,paths)
        f.call('glTexSubImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
               0x0DE1,0,0,0,22,128,0x1908,0x1406,(c.c_float*len(data))(*data))
    rebuild(camera,5.+1/60);advanced=f.read_texture(paths,10,22,128)
    start=slot*22*4
    delta=max(abs(a-b) for a,b in zip(baseline[start:start+64],advanced[start:start+64]))
    assert 1e-5<delta<.04, ('History does not move smoothly',delta)
    restore(baseline);moved=(1.01,3.01,6.)
    update_uint(f,table,7,source_table(moved,[(source,False)]));rebuild(moved,5.+1/60)
    shifted=f.read_texture(paths,10,22,128)
    for i in range(16):
        for component in range(4):
            index=start+i*4+component
            correction=math.floor(moved[0])-math.floor(camera[0]) if component in (0,2) else 0
            assert abs(shifted[index]+correction-advanced[index])<1e-4, 'History jumps at camera grid boundary'
    update_uint(f,table,7,source_table(camera,[(source,False)]))
    trajectories=[]
    for fps in (30,60):
        restore(baseline)
        for frame in range(1,fps+1):rebuild(camera,5.+frame/fps)
        trajectories.append(f.read_texture(paths,10,22,128)[start:start+64])
    assert max(abs(a-b) for a,b in zip(*trajectories))<.08, 'Flow speed depends strongly on frame rate'
    # Add a roof after smoke is already moving, then run the persistent path.
    restore(baseline);update_obstacles(f,obstacles,11,camera,[(.5,1.5,.5)])
    previous_spread=0.
    for frame in range(1,61):
        rebuild(camera,5.+frame/60)
        data=f.read_texture(paths,10,22,128)
        spread=data[start+71]
        assert previous_spread<=spread+.00001 and spread-previous_spread<.1, 'Roof widening snaps instead of relaxing'
        previous_spread=spread
    update_obstacles(f,obstacles,11,camera,[])
    # Compare long-pause reset against a genuinely empty cache, at the same clock.
    update_uint(f,table,7,source_table(camera,[(source,False)]))
    restore(baseline);rebuild(camera,8.);paused=f.read_texture(paths,10,22,128)
    restore([0.]*len(baseline));rebuild(camera,8.);fresh=f.read_texture(paths,10,22,128)
    assert max(abs(a-b) for a,b in zip(paused,fresh))<1e-5, 'Stale history survives long pause'
    # A different world cell in the same hash must not inherit the old plume.
    other=next((x+.5,.5,z+.5) for x in range(-6,7) for z in range(-2,8)
               if (x+.5,.5,z+.5)!=source and source_table(camera,[((x+.5,.5,z+.5),False)])[slot])
    update_uint(f,table,7,source_table(camera,[(other,False)]))
    restore(baseline);rebuild(camera,5.+1/60);changed=f.read_texture(paths,10,22,128)
    restore([0.]*len(baseline));rebuild(camera,5.+1/60);fresh=f.read_texture(paths,10,22,128)
    assert max(abs(a-b) for a,b in zip(changed,fresh))<1e-5, 'Hash replacement inherits unrelated smoke'
    update_uint(f,table,7,[0]*128);rebuild(camera,5.+2/60)
    assert max(abs(v) for v in f.read_texture(paths,10,22,128))==0, 'Removed source retains stale flow'
    print('PASS: GPU smoke history advects smoothly; jumping camera origins preserve world flow; pauses/hash replacements/removed sources reset history',flush=True)
    f.close()


def check_roof_fan(api,values):
    f=AdvancedFixture(api,8,8);camera=(.5,2.7,6.);source=(.5,.5,.5)
    table=uint_texture(f,7,source_table(camera,[(source,False)]));presence=uint_texture(f,8,[0xffffffff]*4)
    obstacles=uint_volume(f,11);paths,rebuild=flow_cache(f,values,table,obstacles)
    cloud_volume(f,9);f.texture([1,0,0,1]*64,4);target=f.texture(None,0)
    prefix=api['source'](api['ROOT']/'composite1.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;uniform vec3 testPoint;
void main(){int slot=int(smokeSourceSlot(ivec3(0)));float ceiling=texelFetch(aaSmokePaths,ivec2(16,slot),0).w;
color=vec4(smokeDensity(testPoint,vec3(.5),slot,ceiling,vec2(frameTimeCounter)));}
'''
    density=f.program('composite1.fsh',values,fragment=fragment)
    u=dict(aaSmokeSources=7,aaSmokePresence=8,aaSmokePaths=10,aaSmokeObstacles=11,aaCloudNoise=9,shadowtex0=4,
           cameraPosition=camera,gbufferModelViewInverse=IDENTITY,shadowModelView=IDENTITY,shadowProjection=IDENTITY,
           sunPosition=(.2,1.,.1),shadowLightPosition=(.2,1.,.1),frameTimeCounter=5.)
    slot=next(i for i,v in enumerate(source_table(camera,[(source,False)])) if v);start=slot*22*4
    for height in (1,2,3):
        block=(.5,height+.5,.5);update_obstacles(f,obstacles,11,camera,[block]);rebuild(camera)
        data=f.read_texture(paths,10,22,128);roof=data[start+80:start+84]
        assert roof[3]==8, ('Single block did not open all eight sides',height,roof)
        assert max(f.render(density,[target],dict(u,testPoint=block)))==0, 'Roof volume leaks into solid block'
        for d in range(8):
            angle=d*math.pi/4;best=0
            for h in (.15,.35,.65):
                point=(source[0]+roof[2]*math.cos(angle),source[1]+roof[0]+h,source[2]+roof[2]*math.sin(angle))
                best=max(best,max(f.render(density,[target],dict(u,testPoint=point))))
            assert best>.015, ('Missing side of spreading smoke',height,d,best)
        # All in-roof sections remain centred on the source over multiple frames.
        for frame in range(1,61):
            rebuild(camera,5.+frame/60);moving=f.read_texture(paths,10,22,128)
            assert moving[start+80:start+84]==roof, 'Roof route switches as billows move'
            for i in range(16):
                h=i*.5
                if not(roof[0]<=h<=roof[1]+.35):continue
                row=moving[start+i*4:start+i*4+4]
                origin=[math.floor(x)-16 for x in camera]
                assert abs((row[0]+row[2])*.5+origin[0]-source[0])<1e-4
                assert abs((row[1]+row[3])*.5+origin[2]-source[2])<1e-4
    # End-to-end 8-step ray integration: small camera/time changes under a roof
    # must not make the scattering layer alternate between visible and missing.
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;uniform vec3 testRay;
void main(){color=renderSmoke(testRay,20);}
'''
    render=f.program('composite1.fsh',values,fragment=fragment)
    update_obstacles(f,obstacles,11,camera,[(.5,2.5,.5)]);rebuild(camera)
    alpha=[]
    for frame in range(90):
        moved=(.5+.003*math.sin(frame*.1),2.7,6.+.002*math.cos(frame*.1));time=5.+frame/60
        update_uint(f,table,7,source_table(moved,[(source,False)]))
        update_obstacles(f,obstacles,11,moved,[(.5,2.5,.5)]);rebuild(moved,time)
        direction=(source[0]-moved[0],1.7-moved[1],source[2]-moved[2])
        length=math.sqrt(sum(x*x for x in direction));ray=tuple(x/length for x in direction)
        result=f.render(render,[target],dict(u,cameraPosition=moved,frameTimeCounter=time,testRay=ray))[:4]
        assert all(math.isfinite(v) for v in result), 'Non-finite scattering below roof'
        alpha.append(result[3])
    assert min(alpha)>.03, ('Spreading cap vanishes with small camera motion',min(alpha))
    assert max(abs(a-b) for a,b in zip(alpha,alpha[1:]))<.035, ('8-step roof smoke flickers',alpha)
    # Stacked blocks and a sealed broad roof remain bounded and do not extinguish
    # the local density underneath the ceiling.
    update_uint(f,table,7,source_table(camera,[(source,False)]))
    for blocks,sealed in [([(.5,2.5,.5),(.5,3.5,.5)],False),
                           ([(x+.5,2.5,z+.5) for x in range(-7,8) for z in range(-7,8)],True)]:
        update_obstacles(f,obstacles,11,camera,blocks);rebuild(camera)
        data=f.read_texture(paths,10,22,128);roof=data[start+80:start+84]
        assert (roof[3]==0)==sealed, ('Incorrect sealed/stacked roof state',roof)
        assert max(f.render(density,[target],dict(u,testPoint=(.5,1.5,.5))))>.01, 'Smoke below ceiling disappears'
    # Extending a horizontal beam keeps its nearby edge and local spread,
    # regardless of its length or orientation. Wide ceilings cannot produce
    # smoke above the roof without a reachable local edge.
    for axis in (0,2):
        spreads=[]
        for half_length in (0,2,6,10):
            blocks=[]
            for n in range(-half_length,half_length+1):
                block=[.5,2.5,.5];block[axis]+=n;blocks.append(tuple(block))
            update_obstacles(f,obstacles,11,camera,blocks);rebuild(camera)
            data=f.read_texture(paths,10,22,128);roof=data[start+80:start+84]
            spreads.append(roof[2])
            assert data[start+67]>7, 'Narrow beam prevents smoke escaping its nearby sides'
            for d in range(8):
                angle=d*math.pi/4
                point=(.5+3*math.cos(angle),2.,.5+3*math.sin(angle))
                assert max(f.render(density,[target],dict(u,testPoint=point)))==0, 'Long beam produces an oversized smoke ring'
        assert max(spreads)<=1.25, ('Roof exceeds local spreading budget',axis,spreads)
        assert max(spreads[1:])-min(spreads[1:])<1e-5, ('Beam length inflates smoke',axis,spreads)
    blocks=[(x+.5,2.5,z+.5) for x in range(-2,3) for z in range(-2,3)]
    update_obstacles(f,obstacles,11,camera,blocks);rebuild(camera)
    data=f.read_texture(paths,10,22,128)
    assert data[start+67]<1.5, 'Smoke resumes above a broad roof without a reachable exit'
    assert max(f.render(density,[target],dict(u,testPoint=(.5,3.5,.5))))==0
    print('PASS: compact smoke on eight roof sides; centred flow; 8-step camera-motion stability; stacked/sealed roofs; long X/Z beams do not inflate or form oversized rings',flush=True)
    f.close()


def check_smooth_response(api,values):
    f=AdvancedFixture(api,8,8);camera=(.5,2.7,6.);source=(.5,.5,.5)
    table=uint_texture(f,7,source_table(camera,[(source,False)]))
    obstacles=uint_volume(f,11);paths,rebuild=flow_cache(f,values,table,obstacles)
    cloud_volume(f,9);target=f.texture(None,0)
    slot=next(i for i,v in enumerate(source_table(camera,[(source,False)])) if v);start=slot*84
    prefix=api['source'](api['ROOT']/'composite1.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
uniform int testMode;uniform float testHeight,testDensity;uniform vec3 testFire;
void main(){int slot=int(smokeSourceSlot(ivec3(0)));vec4 roof=texelFetch(aaSmokePaths,ivec2(20,slot),0);
if(testMode==0)color=vec4(smokeIllumination(testHeight,testDensity,vec3(.18,.18,.185),vec3(.2,.18,.15),testFire),1);
else if(testMode==1)color=vec4(smokeFlowShape(testHeight,slot,roof),1);
else color=vec4(smokeDensity(vec3(.5,2.5,.5),vec3(.5),slot,7.5,vec2(5)));}
'''
    p=f.program('composite1.fsh',values,fragment=fragment)
    u=dict(aaSmokeSources=7,aaSmokePaths=10,aaSmokeObstacles=11,aaCloudNoise=9,
           cameraPosition=camera,testMode=0,testHeight=2.,testDensity=.1,testFire=(1.,.24,.035))
    # Changing density must change brightness, not the balance of light colors.
    for fire in ((1.,.24,.035),(.08,.55,.85)):
        colors=[]
        for density in (.05,.3,.9):
            rgb=f.render(p,[target],dict(u,testFire=fire,testDensity=density))[:3]
            colors.append([v/sum(rgb) for v in rgb])
        assert max(abs(a-b) for a,b in zip(colors[0],colors[-1]))<1e-5, 'Density/expansion changes smoke hue'
    final_spreads=[]
    for fps in (30,60):
        update_obstacles(f,obstacles,11,camera,[]);rebuild(camera,5.)
        update_obstacles(f,obstacles,11,camera,[(.5,2.5,.5)])
        spreads=[]
        for frame in range(1,2*fps+1):
            rebuild(camera,5.+frame/fps);data=f.read_texture(paths,10,22,128)
            spreads.append(data[start+71])
            assert max(f.render(p,[target],dict(u,testMode=2)))==0, 'Temporal relaxation leaks into solid roof'
        assert 0<spreads[0]<.15 and spreads[-1]>.7, 'Roof response is immediate or fails to expand'
        assert all(0<=b-a<.15 for a,b in zip(spreads,spreads[1:])), 'Roof response has temporal expansion jumps'
        final_spreads.append(spreads[-1])
        update_obstacles(f,obstacles,11,camera,[])
        decaying=[]
        for frame in range(1,2*fps+1):
            rebuild(camera,7.+frame/fps);data=f.read_texture(paths,10,22,128)
            decaying.append(data[start+71])
        assert decaying[0]>spreads[-1]*.85 and decaying[-1]<.001, 'Removing roof snaps the shape or leaves stale spread'
        assert all(0<=a-b<.15 for a,b in zip(decaying,decaying[1:])), 'Roof removal has temporal jumps'
    assert abs(final_spreads[0]-final_spreads[1])<.001, 'Widening response depends on frame rate'
    update_obstacles(f,obstacles,11,camera,[(.5,2.5,.5)]);rebuild(camera,12.)
    # The production flow shape has a continuous tangent through half-block
    # cache boundaries, avoiding visible straight-sided expansion segments.
    for height in (.5,1.,1.5,2.,2.5,3.,3.5,4.,4.5,5.):
        spreads=[f.render(p,[target],dict(u,testMode=1,testHeight=height+delta))[2] for delta in (-.001,0.,.001)]
        left=(spreads[1]-spreads[0])/.001;right=(spreads[2]-spreads[1])/.001
        assert abs(left-right)<.015, ('Expansion tangent breaks at cache node',height,left,right)
    print('PASS: stable warm/soul smoke hue across density; gradual block placement/removal at 30/60 FPS; solid clipping during transition; continuous expansion tangents',flush=True)
    f.close()


def check_many_seams(api,values):
    f=AdvancedFixture(api,8,8);camera=(.5,8.5,6.);source=(.5,.5,.5)
    table=uint_texture(f,7,source_table(camera,[(source,False)]))
    presence=uint_texture(f,8,source_masks(source_table(camera,[(source,False)])))
    obstacles=uint_volume(f,11);paths,rebuild=flow_cache(f,values,table,obstacles)
    cloud_volume(f,9);target=f.texture(None,0);rebuild(camera)
    prefix=api['source'](api['ROOT']/'composite1.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
uniform vec3 testRay;uniform float testDistance;uniform int testMode;
void main(){if(testMode==0){color=renderSmoke(testRay,testDistance);return;}
vec3 forward=normalize(vec3(.5,3,.5)-cameraPosition),right=vec3(1,0,0),up=normalize(cross(right,forward));
vec3 ray=normalize(forward+right*(texcoord.x-.5)*1.8+up*(texcoord.y-.5)*1.35);
vec3 inv=1.0/mix(ray,vec3(.000001),lessThan(abs(ray),vec3(.000001)));
vec3 a=(vec3(0,2,0)-cameraPosition)*inv,b=(vec3(1,3,1)-cameraPosition)*inv;
vec3 low=min(a,b),high=max(a,b);float entry=max(max(low.x,low.y),low.z),exit=min(min(high.x,high.y),high.z);
float ground=ray.y<-.00001?max(-cameraPosition.y/ray.y,0.0):25.0;bool hit=exit>max(entry,0.0)&&entry<ground;
float distance=hit?max(entry,0.0):ground;vec3 point=cameraPosition+ray*distance;
vec3 bg=hit?vec3(.18,.10,.04):mix(vec3(.035,.075,.012),vec3(.05,.10,.02),mod(floor(point.x)+floor(point.z),2));
vec4 smoke=renderSmoke(ray,min(distance,25.0));color=vec4(smoke.rgb+bg*(1-smoke.a),1);}
'''
    p=f.program('composite1.fsh',values,fragment=fragment)
    direction=(0.,-5.5,-5.5);length=math.sqrt(sum(v*v for v in direction));ray=tuple(v/length for v in direction)
    u=dict(aaSmokeSources=7,aaSmokePresence=8,aaSmokePaths=10,aaSmokeObstacles=11,aaCloudNoise=9,
           cameraPosition=camera,gbufferModelViewInverse=IDENTITY,sunPosition=(.2,1.,.1),shadowLightPosition=(.2,1.,.1),
           frameTimeCounter=5.,testRay=ray,testDistance=20.,testMode=0)
    f.uniforms(p,u)
    loc=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'eyeBrightnessSmooth')
    f.call('glUniform2i',None,[c.c_int,c.c_int,c.c_int],loc,240,240)
    single=f.render(p,[target],u)[:4]
    crowded=[((x+.5,.5,z+.5),False) for x in range(-2,3) for z in range(-2,3)]
    registered=source_table(camera,crowded)
    update_uint(f,table,7,registered);update_uint(f,presence,8,source_masks(registered));rebuild(camera)
    dense=f.render(p,[target],u)[:4]
    assert dense[3]>single[3]+.1, ('Many fires do not create more smoke',single,dense)
    # Occluder depth does not change sampling positions in all preceding bins.
    # Sweep many foreground distances and ray angles across sampling boundaries.
    for sources in ([(source,False)],crowded):
        registered=source_table(camera,sources)
        update_uint(f,table,7,registered);update_uint(f,presence,8,source_masks(registered));rebuild(camera)
        previous=None
        for step in range(1001):
            result=f.render(p,[target],dict(u,testDistance=2.+step*.012))[:4]
            assert all(math.isfinite(v) and v>=0 for v in result), 'Invalid cropped smoke'
            if previous is not None:
                assert max(abs(a-b) for a,b in zip(previous,result))<.02, ('Foreground clipping produces a rectangular sampling jump',step,previous,result)
            previous=result
        previous=None
        for step in range(121):
            direction=(.0005*(step-60),-5.5,-5.5)
            length=math.sqrt(sum(v*v for v in direction));moving=tuple(v/length for v in direction)
            result=f.render(p,[target],dict(u,testRay=moving))[:4]
            if previous is not None:
                assert max(abs(a-b) for a,b in zip(previous,result))<.015, ('Overlapping plumes change abruptly as ray angle changes',step,previous,result)
            previous=result
    update_obstacles(f,obstacles,11,camera,[(.5,2.5,.5)]);rebuild(camera)
    output=api['ROOT'].parent/'artifacts/volumetric-smoke';output.mkdir(parents=True,exist_ok=True)
    f.w=320;f.h=240;target=f.texture(None,0)
    f.call('glViewport',None,[c.c_int]*4,0,0,f.w,f.h)
    pixels=f.render(p,[target],dict(u,testMode=1))
    save_png(output/'many-fires-above.png',pixels,f.w,f.h)
    front=(.5,2.7,6.)
    registered=source_table(front,crowded)
    update_uint(f,table,7,registered);update_uint(f,presence,8,source_masks(registered))
    update_obstacles(f,obstacles,11,front,[(.5,2.5,.5)]);rebuild(front)
    pixels=f.render(p,[target],dict(u,testMode=1,cameraPosition=front))
    save_png(output/'many-fires-front.png',pixels,f.w,f.h)
    print('PASS: dense fires increase smoke; 128-slot overflow capture; foreground-depth sweep and ray-angle continuity; above-view overlap fixture',flush=True)
    f.close()


def check_reconstruction_edges(api,values):
    f=AdvancedFixture(api,8,8);count=f.w*f.h
    uint_texture(f,7,[0]*128);uint_texture(f,8,[0]*4);uint_volume(f,11)
    f.texture_format(None,10,w=22,h=128);cloud_volume(f,9)
    f.texture([.4,.3,.2,.8]*count,14)
    metadata=f.texture([1,20,1,3.015]*count,15);target=f.texture(None,0)
    prefix=api['source'](api['ROOT']/'composite1.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){color=reconstructSmoke(texcoord,vec3(0,0,-1),3,vec3(0,0,-3),.9,false);}
'''
    p=f.program('composite1.fsh',values,fragment=fragment)
    u=dict(aaSmokeSources=7,aaSmokePresence=8,aaSmokePaths=10,aaSmokeObstacles=11,aaCloudNoise=9,
           colortex21=14,colortex12=15,cameraPosition=(.5,2.7,6.),gbufferModelViewInverse=IDENTITY,
           sunPosition=(.2,1.,.1),shadowLightPosition=(.2,1.,.1),frameTimeCounter=5.)
    alphas=[]
    for step in range(481):
        f.call('glActiveTexture',None,[c.c_uint],0x84C0+15);f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x0DE1,metadata)
        data=[1,20,1,3.015+step*.0001]*count
        f.call('glTexSubImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
               0x0DE1,0,0,0,f.w,f.h,0x1908,0x1406,(c.c_float*len(data))(*data))
        alphas.append(f.render(p,[target],u)[3])
    assert alphas[0]>.79 and alphas[-1]==0, 'Depth-aware upsampling does not retain/reject the correct endpoints'
    assert max(abs(a-b) for a,b in zip(alphas,alphas[1:]))<.008, ('Half-res/full-ray reconstruction has a hard rectangular switch',max(abs(a-b) for a,b in zip(alphas,alphas[1:])))
    print('PASS: reconstruction smoothly crosses the former half-resolution fallback threshold and rejects mismatched geometry',flush=True)
    f.close()


def check_integration(api,values):
    f=AdvancedFixture(api,320,240);count=f.w*f.h
    camera=(.5,2.7,6.);source=(.5,.5,.5)
    table=uint_texture(f,7,source_table(camera,[(source,False)]));presence=uint_texture(f,8,[0xffffffff]*4)
    obstacles=uint_volume(f,11);paths,rebuild=flow_cache(f,values,table,obstacles);rebuild(camera)
    cloud_volume(f,9);f.texture([1,0,0,1]*count,4)
    target=f.texture(None,0)
    prefix=api['source'](api['ROOT']/'composite1.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
uniform vec3 testRay;uniform float testDistance;uniform int testMode;
void main(){vec3 ray=testMode==0?testRay:normalize(vec3((texcoord-.5)*vec2(2.4,1.8),-1));
vec4 smoke=renderSmoke(ray,testDistance);
if(testMode==2){vec3 background=mix(vec3(.015,.03,.065),vec3(.7,.85,.95),texcoord.y);
color=vec4(smoke.rgb+background*(1-smoke.a),1);}else color=smoke;}
'''
    p=f.program('composite1.fsh',values,fragment=fragment)
    u=dict(aaSmokeSources=7,aaSmokePresence=8,aaSmokePaths=10,aaSmokeObstacles=11,aaCloudNoise=9,shadowtex0=4,
           cameraPosition=camera,gbufferModelViewInverse=IDENTITY,shadowModelView=IDENTITY,shadowProjection=IDENTITY,
           sunPosition=(.2,1.,.1),shadowLightPosition=(.2,1.,.1),frameTimeCounter=5.,
           testRay=(0.,0.,-1.),testDistance=20.,testMode=0)
    f.uniforms(p,u)
    loc=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'eyeBrightnessSmooth')
    f.call('glUniform2i',None,[c.c_int,c.c_int,c.c_int],loc,240,240)
    direct=f.render(p,[target],u)[:4]
    assert .03<direct[3]<.99 and min(direct)>=0, ('No meaningful 3D smoke',direct)
    f.texture([0,0,0,1]*count,4)
    shadowed=f.render(p,[target],u)[:4]
    assert max(abs(a-b) for a,b in zip(direct,shadowed))<1e-6, 'Overhead shadow probe changes entire smoke color'
    f.texture([1,0,0,1]*count,4)
    assert f.render(p,[target],dict(u,testRay=(1.,0.,0.)))[:4]==[0]*4, 'Smoke outside plume bounds'
    assert f.render(p,[target],dict(u,testDistance=3.))[:4]==[0]*4, 'Smoke behind foreground leaks through'
    partial=f.render(p,[target],dict(u,testDistance=5.5))[:4]
    assert 0<partial[3]<direct[3], ('Depth-truncated smoke not integrated',partial,direct)
    update_uint(f,presence,8,[0]*4)
    assert f.render(p,[target],u)[:4]==[0]*4, 'Empty scene not transparent'
    update_uint(f,presence,8,[0xffffffff]*4)
    inside=(.5,2.7,.5);update_uint(f,table,7,source_table(inside,[(source,False)]))
    rebuild(inside)
    result=f.render(p,[target],dict(u,cameraPosition=inside,testRay=(0.,0.,1.)))[:4]
    assert 0<result[3]<1, ('Camera-inside smoke failed',result)
    update_uint(f,table,7,source_table(camera,[(source,False)]))
    rebuild(camera)
    moved=f.render(p,[target],dict(u,cameraPosition=(.502,2.7,6.)))[:4]
    assert max(abs(direct[i]-moved[i]) for i in range(4))<.015, ('Tiny camera move pops smoke',direct,moved)
    changed=f.render(p,[target],dict(u,frameTimeCounter=5.01))[:4]
    assert max(abs(direct[i]-changed[i]) for i in range(4))<.02, 'Unstable temporal noise'
    for wrap in (80.,6283.1853):
        rebuild(camera,wrap-.0005)
        before=f.render(p,[target],dict(u,frameTimeCounter=wrap-.0005))
        rebuild(camera,wrap+.0005)
        after=f.render(p,[target],dict(u,frameTimeCounter=wrap+.0005))
        assert max(abs(a-b) for a,b in zip(before,after))<.01, 'Smoke animation clock pops at wrap'
    print('PASS: native 3D noise integration, occlusion, depth truncation, camera inside, empty scene, smooth camera/time motion',flush=True)

    output=api['ROOT'].parent/'artifacts/volumetric-smoke';output.mkdir(parents=True,exist_ok=True)
    rebuild(camera)
    pixels=f.render(p,[target],dict(u,testMode=2))
    save_png(output/'campfire-front.png',pixels,f.w,f.h)
    # The same density field seen from a different world direction.
    side_camera=(6.,2.7,.5)
    update_uint(f,table,7,source_table(side_camera,[(source,False)]))
    rebuild(side_camera)
    side_fragment=fragment.replace('vec3((texcoord-.5)*vec2(2.4,1.8),-1)',
                                   'vec3(-1,(texcoord.y-.5)*1.8,(texcoord.x-.5)*2.4)')
    side_program=f.program('composite1.fsh',values,fragment=side_fragment)
    f.uniforms(side_program,u)
    loc=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],side_program,b'eyeBrightnessSmooth')
    f.call('glUniform2i',None,[c.c_int,c.c_int,c.c_int],loc,240,240)
    pixels=f.render(side_program,[target],dict(u,cameraPosition=side_camera,testMode=2))
    save_png(output/'campfire-side.png',pixels,f.w,f.h)
    update_uint(f,table,7,source_table(inside,[(source,False)]))
    rebuild(inside)
    pixels=f.render(p,[target],dict(u,cameraPosition=inside,testMode=2))
    save_png(output/'campfire-inside.png',pixels,f.w,f.h)
    update_uint(f,table,7,source_table(camera,[(source,False)]))
    rebuild(camera)
    update_uint(f,presence,8,[0xffffffff]*4)
    check_reconstruction(api,f,values,u,table,presence)
    check_roof(api,f,values,u,p,target,table,obstacles,paths,rebuild,output)
    f.close()
    benchmark(api,values,output)


def check_reconstruction(api,f,values,u,table,presence):
    # Deliberately give the low-res buffer opaque smoke belonging to a distant
    # surface. A nearby silhouette must reject that value and ray-march to depth.
    prefix=api['source'](api['ROOT']/'composite1.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
uniform float testDepth;uniform float testDistance;
void main(){color=reconstructSmoke(texcoord,vec3(0,0,-1),testDistance,vec3(0,0,-testDistance),testDepth,false);}
'''
    p=f.program('composite1.fsh',values,fragment=fragment)
    f.texture([.4,.3,.2,.8]*(f.w*f.h),14)
    metadata=f.texture([1,20,1,20]*(f.w*f.h),15)
    target=f.texture(None,16)
    near=f.render(p,[target],dict(u,colortex21=14,colortex12=15,testDepth=.9,testDistance=3.))
    assert max(near)==0, 'Low-res smoke blurred across foreground depth silhouette'
    valid=f.render(p,[target],dict(u,colortex21=14,colortex12=15,testDepth=.9,testDistance=20.))[:4]
    assert max(abs(valid[i]-[.4,.3,.2,.8][i]) for i in range(4))<1e-6, 'Valid half-resolution smoke not reconstructed'
    print('PASS: half-resolution smoke reconstruction preserves foreground silhouettes and valid smoke',flush=True)


def check_roof(api,f,values,u,probe,target,table,obstacles,paths,rebuild,output):
    camera=u['cameraPosition'];source=(.5,.5,.5)
    update_obstacles(f,obstacles,11,camera,[(.5,1.5,.5)])
    rebuild(camera)
    slot=next(i for i,v in enumerate(source_table(camera,[(source,False)])) if v)
    data=f.read_texture(paths,10,22,128)
    row=data[(slot*22+1)*4:(slot*22+1)*4+4]
    origin=[math.floor(x)-16 for x in camera]
    side=(row[0]+origin[0],row[1]+origin[2])
    assert abs(row[2]-row[0])*.5>.25, ('Roof did not create gradual lateral spread',row)
    assert data[(slot*22+16)*4+3]>7, 'Single overhead block extinguished plume'
    prefix=api['source'](api['ROOT']/'composite1.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;uniform vec3 testPoint;
void main(){float d=smokeDensity(testPoint,vec3(.5,.5,.5),int(smokeSourceSlot(ivec3(0))),7.5,vec2(5,5));color=vec4(d);}
'''
    p=f.program('composite1.fsh',values,fragment=fragment)
    assert max(f.render(p,[target],dict(u,testPoint=(.5,1.5,.5))))==0, 'Smoke density penetrates solid block'
    # Find the thickest point above the side of the roof, on the cached path.
    best=0.
    for i in range(2,9):
        node=data[(slot*22+i)*4:(slot*22+i)*4+4]
        point=(node[0]+origin[0],.5+i*.5,node[1]+origin[2])
        best=max(best,max(f.render(p,[target],dict(u,testPoint=point))))
    assert best>.02, 'No smoke resumes rising beside the obstruction'
    check_shared_voxels(api,values,camera,source,data)
    f.call('glBindFramebuffer',None,[c.c_uint,c.c_uint],0x8D40,f.fbo)
    f.call('glBindVertexArray',None,[c.c_uint],f.vao)
    f.call('glViewport',None,[c.c_int]*4,0,0,f.w,f.h)
    for unit,tex,kind in [(7,table,0x0DE1),(10,paths,0x0DE1),(11,obstacles,0x806F)]:
        f.call('glActiveTexture',None,[c.c_uint],0x84C0+unit)
        f.call('glBindTexture',None,[c.c_uint,c.c_uint],kind,tex)
    # Real volume render, with an analytically depth-tested roof as background.
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){vec3 ray=normalize(vec3((texcoord-.5)*vec2(2.4,1.8),-1));
vec3 inv=1.0/mix(ray,vec3(.000001),lessThan(abs(ray),vec3(.000001)));
vec3 a=(vec3(0,1,0)-cameraPosition)*inv,b=(vec3(1,2,1)-cameraPosition)*inv;
vec3 low=min(a,b),high=max(a,b);float entry=max(max(low.x,low.y),low.z),exit=min(min(high.x,high.y),high.z);
bool hit=exit>max(entry,0);vec3 background=hit?vec3(.06,.08,.09):mix(vec3(.015,.03,.065),vec3(.7,.85,.95),texcoord.y);
vec4 smoke=renderSmoke(ray,hit?max(entry,0):20);color=vec4(smoke.rgb+background*(1-smoke.a),1);}
'''
    p=f.program('composite1.fsh',values,fragment=fragment);f.uniforms(p,u)
    loc=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'eyeBrightnessSmooth')
    f.call('glUniform2i',None,[c.c_int,c.c_int,c.c_int],loc,240,240)
    pixels=f.render(p,[target],u);save_png(output/'campfire-roof.png',pixels,f.w,f.h)
    # Two neighbouring camera origins produce identical world streamlines.
    original=data
    moved=(1.001,2.7,6.)
    update_uint(f,table,7,source_table(moved,[(source,False)]));update_obstacles(f,obstacles,11,moved,[(.5,1.5,.5)]);rebuild(moved)
    shifted=f.read_texture(paths,10,22,128);new_origin=[math.floor(x)-16 for x in moved]
    for i in range(16):
        index=(slot*22+i)*4
        for component,axis in [(0,0),(1,2),(2,0),(3,2)]:
            assert abs(original[index+component]+origin[axis]-shifted[index+component]-new_origin[axis])<.0001, 'Obstacle detour moves with camera grid'
    print('PASS: overhead block creates local spread and upward continuation; solid-cell rejection and camera-grid-stable world flow',flush=True)


def check_shared_voxels(api,values,camera,source,expected):
    # The RT presets reuse their existing occupancy and ignore the fire's own cube.
    f=AdvancedFixture(api,8,8);values=dict(values,VOXEL_TRACING=True)
    table=uint_texture(f,7,source_table(camera,[(source,False)]))
    cells=[0]*(64**3);origin=[math.floor(x)-32 for x in camera]
    for point in [source,(.5,1.5,.5)]:
        x,y,z=[math.floor(v)-origin[i] for i,v in enumerate(point)]
        cells[(z*64+y)*64+x]=0x800000ff
    voxel=f.volume(cells,11,integer=True);path=f.texture_format(None,10,internal=0x8814,w=22,h=128)
    program=f.compute('shadowcomp1.csh',values)
    f.dispatch(program,(2,1,1),dict(cameraPosition=camera,frameTimeCounter=5.),
        [('aaSmokeEmitterImage',table,0x8236,False),('aaVoxelImage',voxel,0x8236,True),('aaSmokePathImage',path,0x8814,False)])
    actual=f.read_texture(path,10,22,128)
    assert max(abs(a-b) for i,(a,b) in enumerate(zip(actual,expected)) if i%88<84)<.0001, 'Shared voxel obstacle cache differs from standalone smoke grid'
    slot=next(i for i,v in enumerate(source_table(camera,[(source,False)])) if v)
    start=slot*22*4;grid=[math.floor(x)-16 for x in camera]
    # A second registered flame occupies the first escape-side voxel. It must
    # remain an emitter rather than turn into a solid cube blocking its neighbour.
    second=(-.5,1.5,.5)
    update_uint(f,table,7,source_table(camera,[(source,False),(second,False)]))
    x,y,z=[math.floor(v)-origin[i] for i,v in enumerate(second)]
    cells[(z*64+y)*64+x]=0x800000ff
    voxel=f.volume(cells,11,integer=True)
    f.dispatch(program,(2,1,1),dict(cameraPosition=camera,frameTimeCounter=5.),
        [('aaSmokeEmitterImage',table,0x8236,False),('aaVoxelImage',voxel,0x8236,True),('aaSmokePathImage',path,0x8814,False)])
    adjacent=f.read_texture(path,10,22,128)
    assert max(abs(a-b) for a,b in zip(adjacent[start:start+84],actual[start:start+84]))<.0001, 'Adjacent registered fire blocks plume escape'
    print('PASS: tracing presets reuse voxel occupancy with identical local roof spread and self-emitter exclusion',flush=True)
    f.close()


def check_particle_switch(api,values):
    # Native indexed quads use the verified MC 26.3 max/max, max/min,
    # min/min, min/max UV order. Test an adjacent untagged atlas tile as well.
    from performance_checks import link
    f=AdvancedFixture(api,16,16)
    def tagged_atlas(tag):
        atlas=[]
        for y in range(32):
            for x in range(64):
                marked=x<32 and (x<2 or x>=30) and (y<2 or y>=30)
                atlas.extend(tag if marked else [1,1,1,1])
        return atlas
    atlas=tagged_atlas([19/255,211/255,83/255,0])
    f.texture(atlas,1,64,32);target=f.texture(None,0)
    f.call('glFramebufferTexture2D',None,[c.c_uint]*4+[c.c_int],0x8D40,0x8CE0,0x0DE1,target,0)
    f.call('glDrawBuffer',None,[c.c_uint],0x8CE0)
    vertex_buffer=c.c_uint();index_buffer=c.c_uint()
    f.call('glGenBuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(vertex_buffer))
    f.call('glGenBuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(index_buffer))
    indices=(c.c_uint*6)(0,1,2,0,2,3)
    f.call('glBindBuffer',None,[c.c_uint,c.c_uint],0x8893,index_buffer)
    f.call('glBufferData',None,[c.c_uint,c.c_ssize_t,c.c_void_p,c.c_uint],0x8893,c.sizeof(indices),indices,0x88E4)
    programs={}
    for mode in ('0','1'):
        vertex=api['source'](api['ROOT']/'gbuffers_particles.vsh',dict(values,SMOKE_MODE=mode),False)
        programs[mode]=link(f,vertex,'#version 330 core\nlayout(location=0) out vec4 color;void main(){color=vec4(1);}')
    # Exercise legacy tags, alpha-preserving tags, premultiplication and actual
    # sRGB atlas decoding. Tagging never uses the visible smoke pixel colors.
    variants=[('legacy',[19/255,211/255,83/255,0],False),
              ('legacy-srgb',[19/255,211/255,83/255,0],True),
              ('new',[0,1,0,1/255],False),('new-srgb',[0,1,0,1/255],True),
              ('premultiplied',[0,1/255,0,1/255],False),
              ('premultiplied-srgb',[0,1/255,0,1/255],True)]
    for label,tag,srgb in variants:
        atlas=tagged_atlas(tag)
        f.call('glActiveTexture',None,[c.c_uint],0x84C0+1)
        if srgb:
            payload=(c.c_ubyte*len(atlas))(*(round(v*255) for v in atlas));dtype=0x1401;internal=0x8C43
        else:
            payload=(c.c_float*len(atlas))(*atlas);dtype=0x1406;internal=0x8814
        f.call('glTexImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
               0x0DE1,0,internal,64,32,0,0x1908,dtype,payload)
        for mode,expected in [('0',True),('1',False)]:
            for sprite in (0,1):
                p=programs[mode]
                f.uniforms(p,dict(gtexture=1,aa_ModelView=IDENTITY,aa_Projection=IDENTITY,**{'aa_TextureMatrix[0]':IDENTITY}))
                data=[];u0,u1=sprite*.5,(sprite+1)*.5
                for x,y,u,v in [(1,-1,u1,1),(1,1,u1,0),(-1,1,u0,0),(-1,-1,u0,1)]:data.extend([x,y,0,1,u,v,0,1])
                buf=(c.c_float*len(data))(*data)
                f.call('glBindBuffer',None,[c.c_uint,c.c_uint],0x8892,vertex_buffer)
                f.call('glBufferData',None,[c.c_uint,c.c_ssize_t,c.c_void_p,c.c_uint],0x8892,c.sizeof(buf),buf,0x88E4)
                for name,offset in [('aa_Vertex',0),('aa_MultiTexCoord0',16)]:
                    loc=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],p,name.encode())
                    if loc>=0:
                        f.call('glEnableVertexAttribArray',None,[c.c_uint],loc)
                        f.call('glVertexAttribPointer',None,[c.c_uint,c.c_int,c.c_uint,c.c_ubyte,c.c_int,c.c_void_p],loc,4,0x1406,0,32,c.c_void_p(offset))
                f.call('glClearBufferfv',None,[c.c_uint,c.c_int,c.POINTER(c.c_float)],0x1800,0,(c.c_float*4)(0,0,0,0))
                f.call('glDrawElements',None,[c.c_uint,c.c_int,c.c_uint,c.c_void_p],0x0004,6,0x1405,None)
                pixels=(c.c_float*(16*16*4))()
                f.call('glReadPixels',None,[c.c_int]*4+[c.c_uint,c.c_uint,c.c_void_p],0,0,16,16,0x1908,0x1406,pixels)
                assert f.call('glGetError',c.c_uint,[])==0
                visible=expected or sprite==1
                assert min(pixels)==max(pixels)==float(visible), ('Particle switch/adjacent-sprite isolation failed',mode,sprite,min(pixels),max(pixels))
    for buf in (vertex_buffer,index_buffer):f.call('glDeleteBuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(buf))
    print('PASS: real particle shader switches campfire quads, preserves adjacent particles, and handles sRGB/premultiplied/legacy atlas tags',flush=True)
    f.close()


def benchmark(api,values,output):
    # Isolated real half-resolution production pass at 2560x1440 game resolution.
    f=AdvancedFixture(api,1280,720);count=f.w*f.h
    camera=(.5,2.7,6.);source=(.5,.5,.5)
    table=uint_texture(f,7,source_table(camera,[(source,False)]));presence=uint_texture(f,8,[0xffffffff]*4)
    obstacles=uint_volume(f,11);paths,rebuild=flow_cache(f,values,table,obstacles);rebuild(camera)
    cloud_volume(f,9)
    _,inverse,_=projection()
    f.texture([1,0,0,1]*count,1);f.texture([0,0,0,0]*count,2);f.texture([1,0,0,1]*count,4)
    meta=f.texture_format(None,0);smoke=f.texture_format(None,3)
    results=[]
    for steps in (8,12,16):
        p=f.program('composite.fsh',dict(values,SMOKE_STEPS=str(steps)))
        u=dict(aaSmokeSources=7,aaSmokePresence=8,aaSmokePaths=10,aaSmokeObstacles=11,aaCloudNoise=9,depthtex0=1,colortex2=2,shadowtex0=4,
               viewWidth=2560.,viewHeight=1440.,near=.1,far=128.,isEyeInWater=0,
               cameraPosition=camera,gbufferProjectionInverse=inverse,gbufferModelViewInverse=IDENTITY,
               shadowModelView=IDENTITY,shadowProjection=IDENTITY,sunPosition=(.2,1.,.1),shadowLightPosition=(.2,1.,.1),frameTimeCounter=5.)
        f.render(p,[meta,smoke],u,read=1)
        location=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'eyeBrightnessSmooth')
        f.call('glUniform2i',None,[c.c_int,c.c_int,c.c_int],location,240,240)
        def draw():f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0004,0,6)
        for label,sources in [('empty',[]),('one',[(source,False)]),('many',[((x+.5,.5,z+.5),False) for x in (-3,0,3) for z in (-5,-2,1)])]:
            update_uint(f,table,7,source_table(camera,sources));update_uint(f,presence,8,source_masks(source_table(camera,sources)))
            rebuild(camera)
            f.call('glUseProgram',None,[c.c_uint],p)
            for _ in range(8):draw()
            times=[elapsed(f,draw,4) for _ in range(5)]
            results.append(dict(steps=steps,sources=label,median_ms=statistics.median(times),min_ms=min(times),max_ms=max(times)))
            print(f'GPU smoke only: {steps} steps, {label}: {statistics.median(times):.3f} ms at 1280x720',flush=True)
    (output/'gpu-results.json').write_text(json.dumps(dict(gpu=api['get_string'](0x1F01).decode(),
        method='GL_TIME_ELAPSED, 8 warmups, median of five four-draw batches; production half pass, VL off, sky depth; isolated, not gameplay FPS',results=results),indent=2))
    f.close()

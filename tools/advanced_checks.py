"""Native image/compute fixtures for the advanced tracing pipeline."""
import ctypes as c
import math
from quality_checks import Fixture

IDENTITY=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]

class AdvancedFixture(Fixture):
    def texture_format(self,data,unit,internal=0x881A,w=None,h=None):
        tex=self.texture(None,unit,w,h)
        array=(c.c_float*len(data))(*data) if data is not None else None
        self.call('glTexImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
                  0x0DE1,0,internal,w or self.w,h or self.h,0,0x1908,0x1406,array)
        return tex

    def volume(self,data,unit,integer=False):
        tex=c.c_uint();self.call('glGenTextures',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(tex));self.textures.append(tex)
        self.call('glActiveTexture',None,[c.c_uint],0x84C0+unit)
        self.call('glBindTexture',None,[c.c_uint,c.c_uint],0x806F,tex)
        for prop,val in [(0x2801,0x2600),(0x2800,0x2600),(0x2802,0x812F),(0x2803,0x812F),(0x8072,0x812F)]:
            self.call('glTexParameteri',None,[c.c_uint,c.c_uint,c.c_int],0x806F,prop,val)
        array=((c.c_uint if integer else c.c_float)*len(data))(*data) if data is not None else None
        self.call('glTexImage3D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
                  0x806F,0,0x8236 if integer else 0x881A,64,64,64,0,0x8D94 if integer else 0x1908,0x1405 if integer else 0x1406,array)
        return tex

    def uniforms(self,program,values):
        self.call('glUseProgram',None,[c.c_uint],program)
        for name,value in values.items():
            loc=self.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],program,name.encode())
            if isinstance(value,int):self.call('glUniform1i',None,[c.c_int,c.c_int],loc,value)
            elif isinstance(value,float):self.call('glUniform1f',None,[c.c_int,c.c_float],loc,value)
            elif len(value) in (9,16):
                fn='glUniformMatrix3fv' if len(value)==9 else 'glUniformMatrix4fv'
                self.call(fn,None,[c.c_int,c.c_int,c.c_ubyte,c.POINTER(c.c_float)],loc,1,0,(c.c_float*len(value))(*value))
            else:self.call('glUniform3f',None,[c.c_int,c.c_float,c.c_float,c.c_float],loc,*value)

    def bind_images(self,program,images):
        for unit,(name,tex,internal,layered) in enumerate(images):
            self.uniforms(program,{name:unit})
            self.call('glBindImageTexture',None,[c.c_uint,c.c_uint,c.c_int,c.c_ubyte,c.c_int,c.c_uint,c.c_uint],
                      unit,tex,0,int(layered),0,0x88BA,internal)

    def compute(self,entry,values,dh=False):
        a=self.api;code=a['source'](a['ROOT']/entry,dict(values,__advanced_fixture=True),dh)
        shader=self.shader(0x91B9,code);program=a['create_program']();a['attach'](program,shader);a['link'](program)
        status=c.c_int();a['program_status'](program,0x8B82,c.byref(status))
        if not status.value:
            log=c.create_string_buffer(16384);a['program_log'](program,len(log),None,log);raise AssertionError(log.value.decode())
        a['delete_shader'](shader);self.programs.append(program);return program

    def dispatch(self,program,groups,uniforms,images):
        self.uniforms(program,uniforms);self.bind_images(program,images)
        self.call('glDispatchCompute',None,[c.c_uint]*3,*groups)
        self.barrier()
        assert self.call('glGetError',c.c_uint,[])==0

    def barrier(self):self.call('glMemoryBarrier',None,[c.c_uint],0xFFFFFFFF)

    def read_texture(self,tex,unit,w=None,h=None,volume=False,integer=False):
        target=0x806F if volume else 0x0DE1
        self.call('glActiveTexture',None,[c.c_uint],0x84C0+unit);self.call('glBindTexture',None,[c.c_uint]*2,target,tex)
        count=64**3 if volume else (w or self.w)*(h or self.h)
        array=((c.c_uint if integer else c.c_float)*(count if integer else count*4))()
        self.call('glGetTexImage',None,[c.c_uint,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
                  target,0,0x8D94 if integer else 0x1908,0x1405 if integer else 0x1406,array)
        assert self.call('glGetError',c.c_uint,[])==0
        return list(array)

def projection(near=.1,far=128.):
    a,b=-(far+near)/(far-near),-2*far*near/(far-near)
    return [1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0],[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b],lambda z:(-a+b/z)*.5+.5

def run(api):
    check_gi_resource_gate(api)
    check_voxels_and_reservoir(api)
    check_hiz(api)
    check_atrous(api)
    check_rough_reflections(api)

def check_gi_resource_gate(api):
    f=AdvancedFixture(api,16,16)
    values=dict(api['resolve']('REALISM_RT'),__advanced_fixture=True,SSGI=False)
    p=f.program('deferred3.fsh',values)
    for name in ('aaReservoirPos0','aaReservoirPos1','aaReservoirMeta0','aaReservoirMeta1','aaReservoirLight0','aaReservoirLight1'):
        location=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,name.encode())
        assert location==-1, 'GI disabled but unallocated reservoir image remains active: '+name
    print('PASS: GPU GI-off option removes every reservoir image binding',flush=True)
    f.close()

def check_voxels_and_reservoir(api):
    f=AdvancedFixture(api,16,16)
    values=dict(api['resolve']('REALISM_RT'),__advanced_fixture=True,GI_BOUNCES='1',VOXEL_STEPS='96')
    material=0x80000000|(15<<27)|(1<<24)|204|(51<<8)|(26<<16)
    cells=[0]*(64**3)
    for y in range(64):
        for z in range(64):cells[(z*64+y)*64+40]=material
    voxel=f.volume(cells,4,True);light=f.volume(None,5)
    f.texture([1,0,0,1]*256,1)
    u=dict(gbufferModelViewInverse=IDENTITY,shadowModelView=IDENTITY,shadowProjection=IDENTITY,
           cameraPosition=(0.,0.,0.),sunPosition=(0.,1.,0.),shadowLightPosition=(0.,1.,0.),aaVoxelData=4,aaVoxelLight=5,shadowtex0=1)
    compute=f.compute('shadowcomp.csh',values)
    f.dispatch(compute,(16,1,64),u,[('aaVoxelLightImage',light,0x881A,True)])
    prefix=api['source'](api['ROOT']/'deferred3.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;uniform vec3 testDirection;
void main(){vec3 p,n;uint m;bool hit=traceVoxelWorld(vec3(0),testDirection,96,p,n,m);color=vec4(p,hit?1:0);}
'''
    p=f.program('deferred3.fsh',values,fragment=fragment)
    target=f.texture(None,0)
    out=f.render(p,[target],dict(u,testDirection=(1.,0.,0.)))[:4]
    assert abs(out[0]-8)<.002 and out[3]==1, ('Off-screen DDA missed wall',out)
    assert f.render(p,[target],dict(u,testDirection=(0.,0.,1.)))[3]==0, 'Parallel DDA ray hit unrelated geometry'
    field=f.read_texture(light,5,volume=True)
    at=((32*64+32)*64+40)*4
    assert max(abs(field[at+i]-4*[204/255,51/255,26/255][i]) for i in range(3))<.005, 'Emissive compute radiance incorrect'

    # A real vertex image atomic: a clipped/off-screen terrain vertex still
    # deposits occupancy at the block center before raster/depth visibility.
    vs=api['compile_one'](api['ROOT']/'shadow_solid.vsh',values,False)
    fs=api['compile_one'](api['ROOT']/'shadow_solid.fsh',values,False)
    vertex_program=api['create_program']();api['attach'](vertex_program,vs);api['attach'](vertex_program,fs);api['link'](vertex_program)
    status=c.c_int();api['program_status'](vertex_program,0x8B82,c.byref(status));assert status.value
    f.programs.append(vertex_program);api['delete_shader'](vs);api['delete_shader'](fs)
    f.texture([.8,.4,.2,1]*256,6)
    f.call('glBindFramebuffer',None,[c.c_uint,c.c_uint],0x8D40,0)
    f.uniforms(vertex_program,dict(u,gtexture=6,aa_ModelView=IDENTITY,shadowModelViewInverse=IDENTITY,
                                  aa_NormalMatrix=[1,0,0,0,1,0,0,0,1]))
    for name,value in {'aa_Vertex':(12.,0.,0.,1.),'aa_Color':(1.,1.,1.,1.),'aa_Normal':(0.,1.,0.,0.),
                       'mc_Entity':(0.,0.,0.,0.),'at_midBlock':(32.,32.,32.,0.),'mc_midTexCoord':(.5,.5,0.,0.)}.items():
        loc=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],vertex_program,name.encode())
        if loc>=0:f.call('glVertexAttrib4f',None,[c.c_uint]+[c.c_float]*4,loc,*value)
    f.bind_images(vertex_program,[('aaVoxelImage',voxel,0x8236,True)])
    f.call('glEnable',None,[c.c_uint],0x8C89)
    f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0000,0,1)
    f.call('glDisable',None,[c.c_uint],0x8C89);f.barrier()
    captured=f.read_texture(voxel,4,volume=True,integer=True)
    assert captured[(32*64+32)*64+44]!=0, 'Hidden terrain vertex was not voxelized'
    f.call('glBindFramebuffer',None,[c.c_uint,c.c_uint],0x8D40,f.fbo)
    print('PASS: GPU 3D DDA off-screen hit/parallel miss, emissive compute cache and pre-raster vertex atomics',flush=True)

    fragment=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){color=vec4(sampleReservoirGI(texcoord,vec3(0,0,-4),vec3(1,0,0),0.2,texcoord*vec2(16)),1);}
'''
    p=f.program('deferred3.fsh',values,fragment=fragment)
    f.texture([1,0,0,4]*256,2)
    images=[]
    for index,name in enumerate(['aaReservoirPos0','aaReservoirPos1','aaReservoirMeta0','aaReservoirMeta1','aaReservoirLight0','aaReservoirLight1']):
        tex=f.texture([0,0,0,0]*256,8+index);images.append((name,tex,0x8814,False))
    proj,inv,_=projection()
    uniforms=dict(u,viewWidth=16.,viewHeight=16.,colortex18=2,gbufferProjection=proj,gbufferProjectionInverse=inv,
                  gbufferPreviousModelView=IDENTITY,gbufferPreviousProjection=proj,
                  previousCameraPosition=(0.,0.,0.),frameTime=1/60,frameCounter=1)
    f.bind_images(p,images)
    fresh=f.render(p,[target],uniforms);f.barrier()
    assert max(fresh[0::4])>0.1 and max(fresh[0::4])<7, 'Fresh GI reservoir produced no finite energy'
    reused=f.render(p,[target],dict(uniforms,frameCounter=2));f.barrier()
    counts=f.read_texture(images[4][1],12)[3::4]
    assert max(counts)>4 and max(counts)<=32, 'Temporal/spatial reservoir candidates were not reused or not capped'
    f.call('glActiveTexture',None,[c.c_uint],0x84C0+4);f.call('glBindTexture',None,[c.c_uint]*2,0x806F,voxel)
    empty=(c.c_uint*(64**3))()
    f.call('glTexSubImage3D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
           0x806F,0,0,0,0,64,64,64,0x8D94,0x1405,empty)
    gone=f.render(p,[target],dict(uniforms,frameCounter=3));f.barrier()
    assert max(gone[0::4])<1e-5, 'Reservoir reused a removed voxel emitter'
    print('PASS: GPU fresh/path-reused GI reservoirs, bounded sample counts and current-scene visibility revalidation',flush=True)
    f.close()

def check_hiz(api):
    f=AdvancedFixture(api,64,32)
    values=dict(api['resolve']('REALISM'),__advanced_fixture=True)
    proj,inv,depth=projection()
    f.texture([value for y in range(32) for x in range(64) for value in (depth(3 if x==32 else 8),0,0,1)],0)
    atlas=f.texture_format(None,1,0x8230,64,16)
    u=dict(viewWidth=64.,viewHeight=32.,gbufferProjection=proj,gbufferProjectionInverse=inv,depthtex0=0,aaHiZ=1)
    p=f.compute('deferred.csh',values)
    f.dispatch(p,(math.ceil(64/16),math.ceil(32/16),1),u,[('aaHiZImage',atlas,0x8230,False)])
    out=f.read_texture(atlas,1,64,16)
    assert abs(out[16*4]-3)<.001 and abs(out[16*4+1]-8)<.001, 'Thin nearest depth lost in first hierarchy level'
    assert abs(out[(12*64+34)*4]-3)<.001, 'Coarse Hi-Z tile did not retain minimum depth'
    prefix=api['source'](api['ROOT']/'deferred3.fsh',values,False).split('in vec2 texcoord;')[0]
    frag=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){vec2 h;float confidence;bool hit=traceScreen(depthtex0,vec3(-1,0,-2),normalize(vec3(.4,0,-.916)),.18,64,h,confidence);color=vec4(h,confidence,hit?1:0);}
'''
    p=f.program('deferred3.fsh',values,fragment=frag);target=f.texture(None,2)
    plain=f.render(p,[target],dict(u,near=.1,aaHiZReady=0))[:4]
    accelerated=f.render(p,[target],dict(u,near=.1,aaHiZReady=1))[:4]
    assert plain[3]==accelerated[3]==1 and max(abs(plain[i]-accelerated[i]) for i in range(2))<.02, ('Hi-Z changed valid hit',plain,accelerated)
    print('PASS: GPU four-level conservative Hi-Z atlas, thin-depth preservation and accelerated hit agreement',flush=True)
    f.close()

def check_atrous(api):
    f=AdvancedFixture(api,24,16)
    values=dict(api['resolve']('REALISM'),__advanced_fixture=True)
    data=[];geometry=[]
    for y in range(16):
        for x in range(24):
            value=1+(.3 if (x+y)&1 else -.3) if x<12 else 0
            data.extend((value,value*.5,value*.2,.7))
            geometry.extend((0,0,1,4) if x<12 else (1,0,0,20))
    f.texture(data,0);f.texture(geometry,1);f.texture([1,1.09,.09,8]*384,2)
    a=f.texture_format(None,3);b=f.texture_format(None,4)
    u=dict(viewWidth=48.,viewHeight=32.,colortex12=0,colortex18=1,colortex19=2,aaDenoiseA=3,aaDenoiseB=4)
    for index,entry in enumerate(['deferred4.csh','deferred4_a.csh','deferred4_b.csh']):
        p=f.compute(entry,values);target,name=(b,'aaDenoiseImageB') if index==1 else (a,'aaDenoiseImageA')
        f.dispatch(p,(3,2,1),u,[(name,target,0x881A,False)])
    out=f.read_texture(a,3)
    interior=[out[(y*24+x)*4] for y in range(4,12) for x in range(4,8)]
    assert max(interior)-min(interior)<.3, 'A-trous did not reduce GI noise'
    assert max(out[(y*24+12)*4] for y in range(16))<1e-4, 'A-trous crossed a depth/normal discontinuity'
    assert max(abs(out[i+3]-.7) for i in range(0,len(out),4))<.001, 'GI filtering altered constant AO'
    print('PASS: GPU variance-guided a-trous noise reduction, depth/normal boundaries and independent AO',flush=True)
    f.close()

def check_rough_reflections(api):
    f=AdvancedFixture(api,64,32)
    values=dict(api['resolve']('REALISM_RT'),__advanced_fixture=True)
    prefix=api['source'](api['ROOT']/'deferred5.fsh',values,False).split('in vec2 texcoord;')[0]
    frag=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){vec3 h;vec3 r=sampleVisibleGGX(vec3(0,0,1),vec3(0,0,1),.45,texcoord,h);
vec3 w=visibleGGXWeight(vec3(0,0,1),vec3(0,0,1),r,h,.45,vec3(.04));color=vec4(w,length(r));}
'''
    p=f.program('deferred5.fsh',values,fragment=frag);target=f.texture(None,0)
    out=f.render(p,[target],{})
    assert min(out)>=0 and max(out[3::4])<1.001 and min(out[3::4])>.999, 'GGX VNDF generated invalid directions'
    assert max(out[0::4])<=1.001 and sum(out[0::4])/(64*32)<.06, 'GGX importance weight created diffuse energy'
    print('PASS: GPU GGX visible-normal reflection directions and bounded BRDF/PDF weights',flush=True)
    f.close()

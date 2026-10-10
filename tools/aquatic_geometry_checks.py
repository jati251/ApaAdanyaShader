"""Actual shadow capture: aquatic cutouts cast leaf silhouettes, never voxel cubes."""
import ctypes as c
import re
from advanced_checks import AdvancedFixture, IDENTITY
from quality_checks import Fixture


def run(api):
    blocks={}
    for key,names in re.findall(r'^block\.(\d+)=(.*)$',(api['ROOT']/'block.properties').read_text(),re.M):
        for name in names.split(): blocks[name]=int(key)
    plants=('minecraft:seagrass','minecraft:tall_seagrass','minecraft:kelp','minecraft:kelp_plant')
    ids={blocks.get(name,0) for name in plants}
    assert len(ids)==1, 'Aquatic plant halves have inconsistent shader material IDs'
    aquatic=ids.pop()
    # Rasterized shadow alpha: transparent texels preserve the existing light.
    f=Fixture(api,32,16)
    values=dict(api['resolve']('HIGH'),LIGHT_SPACE_FALLBACK=False,VOXEL_TRACING=False,
                WAVING_FOLIAGE=False)
    vertex='''#version 330 core
uniform int testMaterial;
out vec2 texcoord; out vec4 glcolor; flat out float materialId;
void main(){
const vec2 corners[6]=vec2[6](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,0),vec2(1,1),vec2(0,1));
texcoord=corners[gl_VertexID]; gl_Position=vec4(texcoord*2-1,0,1);
glcolor=vec4(1); materialId=float(testMaterial);
}'''
    fs=api['source'](api['ROOT']/'shadow_cutout.fsh',values,False)
    p=f.program('composite7.fsh',values,fragment=fs,vertex_source=vertex)
    # Use a split horizontal silhouette to exercise transparent + opaque texels.
    data=[]
    for y in range(f.h):
        for x in range(f.w): data.extend((.2,.4,.1,float(x>=f.w//2)))
    f.texture(data,0)
    target=f.texture(None,1)
    def draw(material):
        f.call('glFramebufferTexture2D',None,[c.c_uint]*4+[c.c_int],0x8D40,0x8CE0,0x0DE1,target,0)
        f.call('glClearBufferfv',None,[c.c_uint,c.c_int,c.POINTER(c.c_float)],0x1800,0,(c.c_float*4)(0,0,0,0))
        return f.render(p,[target],dict(gtexture=0,testMaterial=material))
    plant=draw(aquatic); solid=draw(0)
    left=(8*f.w+4)*4; right=(8*f.w+28)*4
    assert plant[left+3]==0 and plant[right+3]==1, 'Aquatic shadows still fill transparent plant texels'
    assert solid[left+3]==1 and solid[right+3]==1, 'Solid terrain shadow coverage was changed'
    f.close()
    print('PASS: GPU aquatic cutout shadows preserve transparent holes and solid terrain shadows',flush=True)
    if '--advanced' not in api['sys'].argv:
        assert aquatic==1011, 'Aquatic material classification missing'
        return
    f=AdvancedFixture(api,1,1)
    values=dict(api['resolve']('REALISM_FAST'),__advanced_fixture=True,SMOKE_MODE='0',WAVING_FOLIAGE=False)
    vs=api['compile_one'](api['ROOT']/'shadow_cutout.vsh',values,False)
    fs=api['compile_one'](api['ROOT']/'shadow_cutout.fsh',values,False)
    p=api['create_program'](); api['attach'](p,vs); api['attach'](p,fs); api['link'](p)
    status=c.c_int();api['program_status'](p,0x8B82,c.byref(status)); assert status.value
    f.programs.append(p);api['delete_shader'](vs);api['delete_shader'](fs)
    f.texture([.2,.4,.1,1],0)
    f.uniforms(p,dict(gtexture=0,cameraPosition=(0.,0.,0.),aa_ModelView=IDENTITY,
                shadowModelViewInverse=IDENTITY,shadowModelView=IDENTITY,shadowProjection=IDENTITY,
                aa_NormalMatrix=[1,0,0,0,1,0,0,0,1]))
    for name,value in {'aa_Vertex':(12.,0.,0.,1.),'aa_Color':(1.,1.,1.,1.),
            'aa_Normal':(0.,1.,0.,0.),'at_midBlock':(32.,32.,32.,0.),'mc_midTexCoord':(.5,.5,0.,0.)}.items():
        loc=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],p,name.encode())
        if loc>=0:f.call('glVertexAttrib4f',None,[c.c_uint]+[c.c_float]*4,loc,*value)
    material_location=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'mc_Entity')
    f.call('glBindFramebuffer',None,[c.c_uint,c.c_uint],0x8D40,0)
    fields={}; volumes={}
    for material in (aquatic,1001,0,1002):
        field=f.volume([0]*(64**3),4,True)
        volumes[material]=field
        f.bind_images(p,[('aaVoxelImage',field,0x8236,True)])
        f.call('glVertexAttrib4f',None,[c.c_uint]+[c.c_float]*4,material_location,float(material),0.,0.,0.)
        f.call('glEnable',None,[c.c_uint],0x8C89)
        f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0000,0,1)
        f.call('glDisable',None,[c.c_uint],0x8C89); f.barrier()
        fields[material]=f.read_texture(field,4,volume=True,integer=True)
    assert not any(fields[aquatic]), 'Aquatic vegetation deposits a false solid cube in the reflection/GI volume'
    assert not any(fields[1001]), 'Land grass gained solid voxel coverage'
    index=(32*64+32)*64+44
    assert fields[0][index]!=0 and fields[1002][index]!=0, 'Solid terrain/tree canopy disappeared from voxel tracing'
    assert aquatic==1011, 'Aquatic material classification missing'
    # An actual fallback ray must pass through the empty aquatic cell, while
    # still intersecting the unchanged solid/canopy cells captured above.
    prefix=api['source'](api['ROOT']/'deferred3.fsh',values,False).split('in vec2 texcoord;')[0]
    fragment=prefix+'''in vec2 texcoord; layout(location=0) out vec4 color;
void main(){vec3 point,normal;uint material;
bool hit=traceVoxelWorld(vec3(10,0,0),vec3(1,0,0),32,point,normal,material);
color=vec4(float(hit),point.x,0,1);}'''
    trace=f.program('composite7.fsh',values,fragment=fragment)
    target=f.texture(None,1)
    f.call('glBindFramebuffer',None,[c.c_uint,c.c_uint],0x8D40,f.fbo)
    for material in (aquatic,0,1002):
        f.call('glActiveTexture',None,[c.c_uint],0x84C0+4)
        f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x806F,volumes[material])
        result=f.render(trace,[target],dict(aaVoxelData=4,cameraPosition=(0.,0.,0.)))
        assert result[0]==float(material!=aquatic), 'Reflection fallback ray hits an aquatic cube or loses solid terrain'
    f.close()
    print('PASS: GPU actual voxel writer excludes aquatic/land plants; fallback rays pass through aquatic cells and hit stone/tree canopy',flush=True)

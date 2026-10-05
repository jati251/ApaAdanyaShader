"""Render the production POM helper against known height fields and atlas borders."""
import ctypes as c
import math


def run(api):
    bind, root = api['bind'], api['ROOT']
    w, h = 64, 32
    ids=(c.c_uint*2)()
    bind('glGenTextures',None,c.c_int,c.POINTER(c.c_uint))(2,ids)
    active=bind('glActiveTexture',None,c.c_uint)
    texture=bind('glBindTexture',None,c.c_uint,c.c_uint)
    param=bind('glTexParameteri',None,c.c_uint,c.c_uint,c.c_int)
    upload=bind('glTexImage2D',None,c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p)
    for unit in range(2):
        active(0x84C0+unit)
        texture(0x0DE1,ids[unit])
        for name,value in [(0x2801,0x2601),(0x2800,0x2601),(0x2802,0x812F),(0x2803,0x812F)]:
            param(0x0DE1,name,value)
        upload(0x0DE1,0,0x8814,w,h,0,0x1908,0x1406,None)
    fbo,vao=c.c_uint(),c.c_uint()
    bind('glGenFramebuffers',None,c.c_int,c.POINTER(c.c_uint))(1,c.byref(fbo))
    bind('glBindFramebuffer',None,c.c_uint,c.c_uint)(0x8D40,fbo)
    bind('glFramebufferTexture2D',None,c.c_uint,c.c_uint,c.c_uint,c.c_uint,c.c_int)(0x8D40,0x8CE0,0x0DE1,ids[1],0)
    assert bind('glCheckFramebufferStatus',c.c_uint,c.c_uint)(0x8D40)==0x8CD5
    bind('glGenVertexArrays',None,c.c_int,c.POINTER(c.c_uint))(1,c.byref(vao))
    bind('glBindVertexArray',None,c.c_uint)(vao)
    bind('glViewport',None,c.c_int,c.c_int,c.c_int,c.c_int)(0,0,w,h)

    def shader(kind,source):
        source=source.replace('#version 410 core', '#version '+api['CORE_VERSION']+' core')
        result=api['create_shader'](kind)
        text=c.c_char_p(source.encode())
        api['shader_source'](result,1,c.byref(text),None)
        api['compile_shader'](result)
        status=c.c_int()
        api['shader_status'](result,0x8B81,c.byref(status))
        if not status.value:
            log=c.create_string_buffer(8192)
            api['shader_log'](result,len(log),None,log)
            raise AssertionError(log.value.decode())
        return result
    vs=shader(0x8B31,'''#version 410 core
out vec2 uv;
flat out vec4 atlasBounds;
uniform vec4 testBounds;
void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);uv=p*vec2(0.5,1.0);atlasBounds=testBounds;gl_Position=vec4(p*2.0-1.0,0.0,1.0);}
''')
    header='''#version 410 core
#define POM
#define TERRAIN
#define RESOURCE_NORMALS
#define POM_STEPS 32
#define POM_DISTANCE 24.0
'''
    body='''
uniform sampler2D testHeights;
uniform vec3 testView;
uniform float testDistance;
in vec2 uv;
layout(location=0) out vec4 color;
void main(){vec2 hit=parallaxUV(testHeights,uv,dFdx(uv),dFdy(uv),atlasBounds,testView,testDistance);color=vec4(hit,texture(testHeights,hit).r,1.0);}
'''
    programs=[]
    for depth in (0.25,0.0):
        fs=shader(0x8B30,header+f'#define POM_DEPTH {depth}\n'+(root/'lib/parallax.glsl').read_text()+body)
        program=api['create_program']()
        api['attach'](program,vs)
        api['attach'](program,fs)
        api['link'](program)
        status=c.c_int()
        api['program_status'](program,0x8B82,c.byref(status))
        assert status.value, 'POM fixture link failed'
        api['delete_shader'](fs)
        programs.append(program)
    uniform=bind('glGetUniformLocation',c.c_int,c.c_uint,c.c_char_p)
    def render(height=0.5,view=(0.6,0.0,0.8),distance=4.0,zero=False,bounds=(0,0,0.5,1)):
        data=[]
        for y in range(h):
            for x in range(w):
                alpha=(0.1+0.8*(x+0.5)/(w//2) if height=='ramp' else height) if x<w//2 else 0.0
                data.extend((0.0 if x<w//2 else 1.0,0,0,alpha))
        pixels=(c.c_float*len(data))(*data)
        active(0x84C0)
        texture(0x0DE1,ids[0])
        upload(0x0DE1,0,0x8814,w,h,0,0x1908,0x1406,pixels)
        program=programs[int(zero)]
        bind('glUseProgram',None,c.c_uint)(program)
        bind('glUniform1i',None,c.c_int,c.c_int)(uniform(program,b'testHeights'),0)
        bind('glUniform1f',None,c.c_int,c.c_float)(uniform(program,b'testDistance'),distance)
        bind('glUniform3f',None,c.c_int,c.c_float,c.c_float,c.c_float)(uniform(program,b'testView'),*view)
        bind('glUniform4f',None,c.c_int,c.c_float,c.c_float,c.c_float,c.c_float)(uniform(program,b'testBounds'),*bounds)
        bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)(0x0004,0,3)
        out=(c.c_float*(w*h*4))()
        bind('glReadPixels',None,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p)(0,0,w,h,0x1908,0x1406,out)
        assert bind('glGetError',c.c_uint)()==0
        assert all(math.isfinite(v) for v in out)
        return list(out)
    center=(16*w+32)*4
    start=(32.5/w)*0.5
    flat=render(height=1.0)
    shifted=render()
    assert abs(flat[center]-start)<1e-6, 'Flat height map displaced'
    expected=start-0.6/0.8*0.25*0.5*0.5
    assert abs(shifted[center]-expected)<0.002, 'Constant-height intersection incorrect'
    opposite=render(view=(-0.6,0.0,0.8))
    assert abs(opposite[center]-(2*start-expected))<0.002, 'Tangent direction reversed'
    ramp=render(height='ramp')
    crossing=(0.9-0.8*(start/0.5))/(1-0.8*(0.6/0.8*0.25))
    assert abs(ramp[center]-(start-crossing*0.6/0.8*0.25*0.5))<0.002, 'Sloped height intersection incorrect'
    assert max(shifted[2::4])<1e-5, 'POM read an adjacent atlas tile'
    for kwargs in ({'view':(0,0,1)},{'view':(1,0,0)},{'distance':24.0},{'zero':True},{'bounds':(0,0,0,0)}):
        result=render(**kwargs)
        assert abs(result[center]-start)<1e-6, f'POM bypass failed: {kwargs}'
    partial=render(distance=20.0)
    assert expected<partial[center]<start, 'Distance fade is not gradual'
    print('PASS: GPU POM, flat/constant/sloped heights, ray direction, atlas isolation, distance fade, grazing/head-on/zero-depth/invalid-bounds bypass',flush=True)
    for program in programs: api['delete_program'](program)
    api['delete_shader'](vs)
    bind('glDeleteTextures',None,c.c_int,c.POINTER(c.c_uint))(2,ids)
    bind('glDeleteFramebuffers',None,c.c_int,c.POINTER(c.c_uint))(1,c.byref(fbo))
    bind('glDeleteVertexArrays',None,c.c_int,c.POINTER(c.c_uint))(1,c.byref(vao))

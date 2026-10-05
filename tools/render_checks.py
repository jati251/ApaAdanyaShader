"""Small GPU image tests for the actual lens/tone-map shader; called by validate.py."""
import ctypes as c
import math
import statistics


def run(api):
    bind, source, root, resolve = (api[k] for k in ('bind', 'source', 'ROOT', 'resolve'))
    w, h = 128, 64
    gl_gen_tex = bind('glGenTextures', None, c.c_int, c.POINTER(c.c_uint))
    gl_bind_tex = bind('glBindTexture', None, c.c_uint, c.c_uint)
    gl_active = bind('glActiveTexture', None, c.c_uint)
    gl_image = bind('glTexImage2D', None, c.c_uint, c.c_int, c.c_int, c.c_int, c.c_int, c.c_int, c.c_uint, c.c_uint, c.c_void_p)
    gl_param = bind('glTexParameteri', None, c.c_uint, c.c_uint, c.c_int)
    textures = (c.c_uint * 4)()
    gl_gen_tex(4, textures)
    near, far = 0.05, 256.0
    a, b = -(far+near)/(far-near), -2.0*far*near/(far-near)
    def depth(z):
        return (-a+b/z)*0.5+0.5
    scene, depths, material = [], [], []
    for y in range(h):
        for x in range(w):
            checker = 0.08 if (x+y) % 2 else 2.0
            hand = x > 102 and y < 16
            scene.extend([checker, checker, checker, 1.0])
            depths.extend([0.5 if hand else depth(2.0 if x < 64 else 24.0), 0, 0, 1])
            material.extend([1, 0, 0, float(hand)])
    for i, data in enumerate((scene, depths, material, None)):
        gl_active(0x84C0+i)
        gl_bind_tex(0x0DE1, textures[i])
        gl_param(0x0DE1, 0x2801, 0x2601 if i == 0 else 0x2600)
        gl_param(0x0DE1, 0x2800, 0x2601 if i == 0 else 0x2600)
        gl_param(0x0DE1, 0x2802, 0x812F)
        gl_param(0x0DE1, 0x2803, 0x812F)
        array = (c.c_float * len(data))(*data) if data else None
        gl_image(0x0DE1, 0, 0x8814, w, h, 0, 0x1908, 0x1406, array)
    fbo, vao = c.c_uint(), c.c_uint()
    bind('glGenFramebuffers', None, c.c_int, c.POINTER(c.c_uint))(1, c.byref(fbo))
    bind('glBindFramebuffer', None, c.c_uint, c.c_uint)(0x8D40, fbo)
    bind('glFramebufferTexture2D', None, c.c_uint, c.c_uint, c.c_uint, c.c_uint, c.c_int)(0x8D40,0x8CE0,0x0DE1,textures[3],0)
    assert bind('glCheckFramebufferStatus', c.c_uint, c.c_uint)(0x8D40) == 0x8CD5
    bind('glGenVertexArrays', None, c.c_int, c.POINTER(c.c_uint))(1,c.byref(vao))
    bind('glBindVertexArray', None,c.c_uint)(vao)
    bind('glViewport', None,c.c_int,c.c_int,c.c_int,c.c_int)(0,0,w,h)
    uniform = bind('glGetUniformLocation', c.c_int,c.c_uint,c.c_char_p)
    uniform_i = bind('glUniform1i',None,c.c_int,c.c_int)
    uniform_f = bind('glUniform1f',None,c.c_int,c.c_float)
    uniform_mat = bind('glUniformMatrix4fv',None,c.c_int,c.c_int,c.c_ubyte,c.POINTER(c.c_float))
    identity = (c.c_float * 16)(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)
    inverse = (c.c_float * 16)(2,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b)
    def shader(kind, code):
        code=code.replace('#version 410 core', '#version '+api['CORE_VERSION']+' core')
        obj=api['create_shader'](kind)
        code=c.c_char_p(code.encode())
        api['shader_source'](obj,1,c.byref(code),None)
        api['compile_shader'](obj)
        status=c.c_int()
        api['shader_status'](obj,0x8B81,c.byref(status))
        assert status.value, 'GPU fixture compilation failed'
        return obj
    vs=shader(0x8B31, '#version 410 core\nout vec2 texcoord;\nvoid main(){ vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);texcoord=p;gl_Position=vec4(p*2.0-1.0,0.0,1.0);}')
    def render(dof, autofocus=False):
        values=dict(resolve('HIGH'),DOF=dof,HALF_RES_DOF=False,DOF_AUTOFOCUS=autofocus,BLOOM=False,VIGNETTE=False,DOF_FOCUS_DISTANCE='2.0',DOF_FOCAL_LENGTH='85.0',DOF_FSTOP='1.4')
        fs=shader(0x8B30,source(root/'composite5.fsh',values,False))
        program=api['create_program']()
        api['attach'](program,vs)
        api['attach'](program,fs)
        api['link'](program)
        status=c.c_int()
        api['program_status'](program,0x8B82,c.byref(status))
        assert status.value, 'GPU fixture linking failed'
        bind('glUseProgram',None,c.c_uint)(program)
        for name,i in [('colortex0',0),('depthtex0',1),('colortex2',2)]:
            uniform_i(uniform(program,name.encode()),i)
        for name,value in [('viewWidth',w),('viewHeight',h),('centerDepthSmooth',depth(2.0)),('near',near),('far',far)]:
            uniform_f(uniform(program,name.encode()),value)
        uniform_mat(uniform(program,b'gbufferModelViewInverse'),1,0,identity)
        uniform_mat(uniform(program,b'gbufferProjectionInverse'),1,0,inverse)
        bind('glUniform3f',None,c.c_int,c.c_float,c.c_float,c.c_float)(uniform(program,b'sunPosition'),0,1,0)
        bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)(0x0004,0,3)
        pixels=(c.c_float*(w*h*4))()
        bind('glReadPixels',None,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p)(0,0,w,h,0x1908,0x1406,pixels)
        assert all(math.isfinite(v) for v in pixels), 'Non-finite lens output'
        assert bind('glGetError',c.c_uint)() == 0, 'OpenGL error during lens render'
        api['delete_program'](program)
        api['delete_shader'](fs)
        return list(pixels)
    sharp, blurred, auto = render(False), render(True), render(True,True)
    def region(pixels,x0,x1,y0,y1):
        return [pixels[(y*w+x)*4] for y in range(y0,y1) for x in range(x0,x1)]
    def error(a,b): return max(abs(x-y) for x,y in zip(a,b))
    assert error(region(sharp,8,48,8,56),region(blurred,8,48,8,56)) < 1e-5, 'Focus plane lost detail'
    assert error(region(sharp,106,124,2,12),region(blurred,106,124,2,12)) < 1e-5, 'Hand mask blurred'
    before=statistics.pvariance(region(sharp,80,120,30,58))
    after=statistics.pvariance(region(blurred,80,120,30,58))
    assert after < before*0.5, f'Background did not blur: {before}, {after}'
    assert error(blurred,auto)<0.005, 'Autofocus and manual focus disagree at same distance'
    print(f'PASS: GPU lens images, focus/hand preserved, background variance {before:.5f} -> {after:.5f}, autofocus matched',flush=True)
    api['delete_shader'](vs)
    vs=shader(0x8B31, '#version 410 core\nout vec2 texcoord,lmcoord;out vec4 glcolor;out vec3 viewPos;uniform float testZ;\nvoid main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);texcoord=p;lmcoord=vec2(0.5,1.0);glcolor=vec4(1.0);viewPos=vec3(0.0,0.0,testZ);gl_Position=vec4(p*2.0-1.0,0.0,1.0);}')
    def particle(separation,soft=True,weather=False):
        values=dict(resolve('MEDIUM'),SHADOWS=False,CLOUD_SHADOWS=False,SOFT_PARTICLES=soft)
        path=root/('gbuffers_weather.fsh' if weather else 'gbuffers_particles_translucent.fsh')
        fs=shader(0x8B30,source(path,values,False))
        program=api['create_program']()
        api['attach'](program,vs)
        api['attach'](program,fs)
        api['link'](program)
        status=c.c_int()
        api['program_status'](program,0x8B82,c.byref(status))
        assert status.value, 'Particle fixture linking failed'
        bind('glUseProgram',None,c.c_uint)(program)
        uniform_i(uniform(program,b'gtexture'),0)
        uniform_i(uniform(program,b'depthtex1'),1)
        for name,value in [('viewWidth',w),('viewHeight',h),('testZ',-2.0+separation)]:
            uniform_f(uniform(program,name.encode()),value)
        uniform_mat(uniform(program,b'gbufferModelViewInverse'),1,0,identity)
        uniform_mat(uniform(program,b'gbufferProjectionInverse'),1,0,inverse)
        bind('glUniform3f',None,c.c_int,c.c_float,c.c_float,c.c_float)(uniform(program,b'sunPosition'),0,1,0)
        bind('glDrawArrays',None,c.c_uint,c.c_int,c.c_int)(0x0004,0,3)
        pixel=(c.c_float*4)()
        bind('glReadPixels',None,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p)(32,32,1,1,0x1908,0x1406,pixel)
        assert all(math.isfinite(v) for v in pixel), 'Non-finite particle output'
        assert bind('glGetError',c.c_uint)() == 0
        api['delete_program'](program)
        api['delete_shader'](fs)
        return pixel[3]
    assert particle(0.0)<0.001, 'Particle intersection not faded'
    assert abs(particle(0.175)-0.5)<0.01, 'Particle fade width incorrect'
    assert abs(particle(1.0)-1.0)<0.001, 'Free particle lost opacity'
    assert abs(particle(0.0,False)-1.0)<0.001, 'Soft-particle toggle ineffective'
    assert abs(particle(1.0,True,True)-0.65)<0.001, 'Weather opacity incorrect'
    print('PASS: GPU particles, intersection/midpoint/free-space alpha, off switch, weather opacity',flush=True)
    api['delete_shader'](vs)
    bind('glDeleteTextures',None,c.c_int,c.POINTER(c.c_uint))(4,textures)
    bind('glDeleteFramebuffers',None,c.c_int,c.POINTER(c.c_uint))(1,c.byref(fbo))
    bind('glDeleteVertexArrays',None,c.c_int,c.POINTER(c.c_uint))(1,c.byref(vao))

"""Capture actual shadow vertices at the former radial-culling boundary."""
import ctypes as c
import math


def run(api):
    bind = api['bind']
    values = dict(api['resolve']('HIGH'), shadowDistance='144.0', WAVING_FOLIAGE=False)
    vs = api['compile_one'](api['ROOT'] / 'shadow.vsh', values, False)
    fs = api['compile_one'](api['ROOT'] / 'shadow.fsh', values, False)
    program = api['create_program']()
    api['attach'](program, vs)
    api['attach'](program, fs)
    varying = (c.c_char_p * 1)(b'gl_Position')
    bind('glTransformFeedbackVaryings', None, c.c_uint, c.c_int, c.POINTER(c.c_char_p), c.c_uint)(program, 1, varying, 0x8C8C)
    api['link'](program)
    status = c.c_int()
    api['program_status'](program, 0x8B82, c.byref(status))
    assert status.value, 'Shadow capture program did not link'
    bind('glUseProgram', None, c.c_uint)(program)

    fbo, target = c.c_uint(), c.c_uint()
    bind('glGenFramebuffers', None, c.c_int, c.POINTER(c.c_uint))(1, c.byref(fbo))
    bind('glBindFramebuffer', None, c.c_uint, c.c_uint)(0x8D40, fbo)
    bind('glGenRenderbuffers', None, c.c_int, c.POINTER(c.c_uint))(1, c.byref(target))
    bind('glBindRenderbuffer', None, c.c_uint, c.c_uint)(0x8D41, target)
    bind('glRenderbufferStorage', None, c.c_uint, c.c_uint, c.c_int, c.c_int)(0x8D41, 0x8058, 1, 1)
    bind('glFramebufferRenderbuffer', None, c.c_uint, c.c_uint, c.c_uint, c.c_uint)(0x8D40, 0x8CE0, 0x8D41, target)
    assert bind('glCheckFramebufferStatus', c.c_uint, c.c_uint)(0x8D40) == 0x8CD5

    vao = c.c_uint()
    buffers = (c.c_uint * 2)()
    bind('glGenVertexArrays', None, c.c_int, c.POINTER(c.c_uint))(1, c.byref(vao))
    bind('glBindVertexArray', None, c.c_uint)(vao)
    bind('glGenBuffers', None, c.c_int, c.POINTER(c.c_uint))(2, buffers)
    buffer_bind = bind('glBindBuffer', None, c.c_uint, c.c_uint)
    buffer_data = bind('glBufferData', None, c.c_uint, c.c_ssize_t, c.c_void_p, c.c_uint)
    buffer_bind(0x8892, buffers[0])
    attribute = bind('glGetAttribLocation', c.c_int, c.c_uint, c.c_char_p)(program, b'aa_Vertex')
    assert attribute >= 0
    bind('glEnableVertexAttribArray', None, c.c_uint)(attribute)
    bind('glVertexAttribPointer', None, c.c_uint, c.c_int, c.c_uint, c.c_ubyte, c.c_int, c.c_void_p)(attribute, 4, 0x1406, 0, 0, None)
    buffer_bind(0x8C8E, buffers[1])
    buffer_data(0x8C8E, 12 * 4, None, 0x88E9)
    bind('glBindBufferBase', None, c.c_uint, c.c_uint, c.c_uint)(0x8C8E, 0, buffers[1])
    uniform = bind('glGetUniformLocation', c.c_int, c.c_uint, c.c_char_p)
    matrix = bind('glUniformMatrix4fv', None, c.c_int, c.c_int, c.c_ubyte, c.POINTER(c.c_float))
    identity = (c.c_float * 16)(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)
    projection = (c.c_float * 16)(0.005,0,0,0, 0,0.005,0,0, 0,0,0.005,0, 0,0,0,1)
    for name in (b'aa_ModelView', b'shadowModelViewInverse'):
        matrix(uniform(program, name), 1, 0, identity)
    matrix(uniform(program, b'shadowProjection'), 1, 0, projection)
    bind('glEnable', None, c.c_uint)(0x8C89)  # Rasterizer discard for vertex capture.
    begin = bind('glBeginTransformFeedback', None, c.c_uint)
    end = bind('glEndTransformFeedback', None)
    draw = bind('glDrawArrays', None, c.c_uint, c.c_int, c.c_int)
    read = bind('glGetBufferSubData', None, c.c_uint, c.c_ssize_t, c.c_ssize_t, c.c_void_p)
    try:
        for altitude in (0.0, 80.0, 200.0):
            vertices = ((179., -altitude, -4.), (181., -altitude, -4.), (179., -altitude, 4.))
            data = (c.c_float * 12)(*[v for p in vertices for v in (*p, 1.)])
            buffer_bind(0x8892, buffers[0])
            buffer_data(0x8892, c.sizeof(data), data, 0x88E0)
            begin(0x0004)
            draw(0x0004, 0, 3)
            end()
            error = bind('glGetError', c.c_uint)()
            assert error == 0, f'Shadow capture OpenGL error: {hex(error)}'
            captured = (c.c_float * 12)()
            read(0x8C8E, 0, c.sizeof(captured), captured)
            for i, (x, y, z) in enumerate(vertices):
                x, y, z = x * 0.005, y * 0.005, z * 0.005
                distortion = 0.15 + math.hypot(x, y) * 0.85
                expected = (x / distortion, y / distortion, z * 0.2, 1.)
                assert max(abs(a - b) for a, b in zip(captured[i*4:i*4+4], expected)) < 1e-5, f'Shadow triangle stretched at altitude {altitude}: {list(captured[i*4:i*4+4])} != {expected}'
        assert bind('glGetError', c.c_uint)() == 0, 'OpenGL error during shadow capture'
        print('PASS: GPU shadow triangles preserve projection across distance boundary at ground/80/200 blocks altitude', flush=True)
    finally:
        bind('glDisable', None, c.c_uint)(0x8C89)
        bind('glDeleteBuffers', None, c.c_int, c.POINTER(c.c_uint))(2, buffers)
        bind('glDeleteVertexArrays', None, c.c_int, c.POINTER(c.c_uint))(1, c.byref(vao))
        bind('glDeleteFramebuffers', None, c.c_int, c.POINTER(c.c_uint))(1, c.byref(fbo))
        bind('glDeleteRenderbuffers', None, c.c_int, c.POINTER(c.c_uint))(1, c.byref(target))
        api['delete_program'](program)
        api['delete_shader'](vs)
        api['delete_shader'](fs)

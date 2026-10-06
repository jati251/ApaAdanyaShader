"""Exercise real terrain water vertices with independently bobbed camera uniforms."""
import ctypes as c
import math
from quality_checks import Fixture


def run_entry(api,entry):
    f=Fixture(api,1,1)
    target=f.texture(None,0)
    f.call('glFramebufferTexture2D',None,[c.c_uint]*4+[c.c_int],0x8D40,0x8CE0,0x0DE1,target,0)
    assert f.call('glCheckFramebufferStatus',c.c_uint,[c.c_uint],0x8D40)==0x8CD5
    values=dict(api['resolve']('REALISM'),WAVING_FOLIAGE=False)
    vertex=api['source'](api['ROOT']/(entry+'.vsh'),values,entry=='dh_water')
    vs=f.shader(0x8B31,vertex)
    fs=f.shader(0x8B30,api['source'](api['ROOT']/(entry+'.fsh'),values,entry=='dh_water'))
    p=api['create_program']()
    api['attach'](p,vs); api['attach'](p,fs)
    varying=(c.c_char_p*1)(b'worldPos')
    f.call('glTransformFeedbackVaryings',None,[c.c_uint,c.c_int,c.POINTER(c.c_char_p),c.c_uint],p,1,varying,0x8C8C)
    api['link'](p)
    status=c.c_int()
    api['program_status'](p,0x8B82,c.byref(status))
    assert status.value, 'Water vertex capture failed to link'
    f.call('glUseProgram',None,[c.c_uint],p)
    buffers=(c.c_uint*2)()
    f.call('glGenBuffers',None,[c.c_int,c.POINTER(c.c_uint)],2,buffers)
    f.call('glBindBuffer',None,[c.c_uint,c.c_uint],0x8892,buffers[0])
    location=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'aa_Vertex')
    f.call('glEnableVertexAttribArray',None,[c.c_uint],location)
    f.call('glVertexAttribPointer',None,[c.c_uint,c.c_int,c.c_uint,c.c_ubyte,c.c_int,c.c_void_p],location,4,0x1406,0,0,None)
    material=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'mc_Entity')
    if material>=0:
        f.call('glVertexAttrib4f',None,[c.c_uint]+[c.c_float]*4,material,1003.,0.,0.,1.)
    f.call('glBindBuffer',None,[c.c_uint,c.c_uint],0x8C8E,buffers[1])
    f.call('glBufferData',None,[c.c_uint,c.c_ssize_t,c.c_void_p,c.c_uint],0x8C8E,9*4,None,0x88E9)
    f.call('glBindBufferBase',None,[c.c_uint,c.c_uint,c.c_uint],0x8C8E,0,buffers[1])
    def matrix(name,values):
        loc=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,name.encode())
        f.call('glUniformMatrix4fv',None,[c.c_int,c.c_int,c.c_ubyte,c.POINTER(c.c_float)],loc,1,0,(c.c_float*16)(*values))
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    matrix('aa_ModelView',identity)
    matrix('aa_Projection',identity)
    points=((17.,64.,-4.),(18.,64.,-4.),(17.,64.,-5.))
    f.call('glEnable',None,[c.c_uint],0x8C89)
    try:
        for camera in ((15.9,65.05,0.),(16.1,66.8,0.),(15.9,65.05,0.)):
            data=(c.c_float*12)(*[v for point in points for v in (*[a-b for a,b in zip(point,camera)],1.)])
            f.call('glBindBuffer',None,[c.c_uint,c.c_uint],0x8892,buffers[0])
            f.call('glBufferData',None,[c.c_uint,c.c_ssize_t,c.c_void_p,c.c_uint],0x8892,c.sizeof(data),data,0x88E0)
            loc=f.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'cameraPosition')
            f.call('glUniform3f',None,[c.c_int]+[c.c_float]*3,loc,*camera)
            for bob in (0.,0.04,-0.04):
                cs,sn=math.cos(bob),math.sin(bob)
                captured_inverse=[cs,sn,0,0,-sn,cs,0,0,0,0,1,0,0.02,bob,0,1]
                matrix('gbufferModelViewInverse',captured_inverse)
                f.call('glBeginTransformFeedback',None,[c.c_uint],0x0004)
                f.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0004,0,3)
                f.call('glEndTransformFeedback',None,[])
                output=(c.c_float*9)()
                f.call('glGetBufferSubData',None,[c.c_uint,c.c_ssize_t,c.c_ssize_t,c.c_void_p],0x8C8E,0,c.sizeof(output),output)
                error=max(abs(a-b) for a,b in zip(output,[v for point in points for v in point]))
                assert error<1e-5, f'Water vertices moved in world space with independent camera bob: {error:.6f}'
        assert f.call('glGetError',c.c_uint,[])==0
        print(f'PASS: GPU {entry} vertices remain fixed through jumps, camera bob and section crossings',flush=True)
    finally:
        f.call('glDisable',None,[c.c_uint],0x8C89)
        f.call('glDeleteBuffers',None,[c.c_int,c.POINTER(c.c_uint)],2,buffers)
        api['delete_program'](p); api['delete_shader'](vs); api['delete_shader'](fs)
        f.close()


def run(api):
    for entry in ('gbuffers_water','dh_water'):
        run_entry(api,entry)

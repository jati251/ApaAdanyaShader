"""GPU regressions for temporal rejection, scaled viewports and AMD FSR 1."""
import ctypes as c
import math


class Fixture:
    def __init__(self, api, w=97, h=55):
        self.api, self.bind, self.w, self.h = api, api['bind'], w, h
        self.textures, self.programs = [], []
        self.fbo, self.vao = c.c_uint(), c.c_uint()
        self.call('glGenFramebuffers', None, [c.c_int, c.POINTER(c.c_uint)], 1, c.byref(self.fbo))
        self.call('glBindFramebuffer', None, [c.c_uint, c.c_uint], 0x8D40, self.fbo)
        self.call('glGenVertexArrays', None, [c.c_int, c.POINTER(c.c_uint)], 1, c.byref(self.vao))
        self.call('glBindVertexArray', None, [c.c_uint], self.vao)
        self.call('glViewport', None, [c.c_int]*4, 0, 0, w, h)

    def call(self, name, result, types, *args):
        return self.bind(name, result, *types)(*args)

    def texture(self, data, unit, w=None, h=None):
        w, h = w or self.w, h or self.h
        tex = c.c_uint()
        self.call('glGenTextures', None, [c.c_int, c.POINTER(c.c_uint)], 1, c.byref(tex))
        self.textures.append(tex)
        self.call('glActiveTexture', None, [c.c_uint], 0x84C0+unit)
        self.call('glBindTexture', None, [c.c_uint]*2, 0x0DE1, tex)
        for prop, val in [(0x2801,0x2601),(0x2800,0x2601),(0x2802,0x812F),(0x2803,0x812F)]:
            self.call('glTexParameteri', None, [c.c_uint,c.c_uint,c.c_int], 0x0DE1,prop,val)
        array = (c.c_float*len(data))(*data) if data is not None else None
        self.call('glTexImage2D', None, [c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
                  0x0DE1,0,0x8814,w,h,0,0x1908,0x1406,array)
        return tex

    def shader(self, kind, code):
        a = self.api
        obj = a['create_shader'](kind)
        ptr = c.c_char_p(code.encode())
        a['shader_source'](obj,1,c.byref(ptr),None)
        a['compile_shader'](obj)
        ok = c.c_int()
        a['shader_status'](obj,0x8B81,c.byref(ok))
        if not ok.value:
            log = c.create_string_buffer(16384)
            a['shader_log'](obj,len(log),None,log)
            raise AssertionError(log.value.decode())
        return obj

    def program(self, entry, values, scaled=False, fragment=None):
        a = self.api
        vertex = a['source'](a['ROOT']/entry.replace('.fsh','.vsh'),values,False)
        vertex = vertex[:vertex.index('out vec2 texcoord;')]+'''
out vec2 texcoord;
void main() {
    const vec2 corners[6]=vec2[6](vec2(0,0),vec2(1,0),vec2(1,1),vec2(0,0),vec2(1,1),vec2(0,1));
    vec2 p=corners[gl_VertexID];
    texcoord=p;
    gl_Position=vec4(p*2.0-1.0,0.0,1.0);
'''+('gl_Position=scaleSceneClip(gl_Position,vec2(1.0));' if scaled else '')+'\n}\n'
        vs = self.shader(0x8B31,vertex)
        fs = self.shader(0x8B30,fragment or a['source'](a['ROOT']/entry,values,False))
        program = a['create_program']()
        a['attach'](program,vs); a['attach'](program,fs); a['link'](program)
        status = c.c_int()
        a['program_status'](program,0x8B82,c.byref(status))
        if not status.value:
            log = c.create_string_buffer(16384)
            a['program_log'](program,len(log),None,log)
            raise AssertionError(log.value.decode())
        a['delete_shader'](vs); a['delete_shader'](fs)
        self.programs.append(program)
        return program

    def render(self, program, targets, uniforms, read=0):
        self.call('glUseProgram',None,[c.c_uint],program)
        for index, tex in enumerate(targets):
            self.call('glFramebufferTexture2D',None,[c.c_uint]*4+[c.c_int],0x8D40,0x8CE0+index,0x0DE1,tex,0)
        buffers = (c.c_uint*len(targets))(*(0x8CE0+i for i in range(len(targets))))
        self.call('glDrawBuffers',None,[c.c_int,c.POINTER(c.c_uint)],len(targets),buffers)
        assert self.call('glCheckFramebufferStatus',c.c_uint,[c.c_uint],0x8D40)==0x8CD5
        for name, value in uniforms.items():
            loc = self.call('glGetUniformLocation',c.c_int,[c.c_uint,c.c_char_p],program,name.encode())
            if isinstance(value,int): self.call('glUniform1i',None,[c.c_int,c.c_int],loc,value)
            elif isinstance(value,float): self.call('glUniform1f',None,[c.c_int,c.c_float],loc,value)
            elif len(value)==16:
                self.call('glUniformMatrix4fv',None,[c.c_int,c.c_int,c.c_ubyte,c.POINTER(c.c_float)],loc,1,0,(c.c_float*16)(*value))
            else: self.call('glUniform3f',None,[c.c_int,c.c_float,c.c_float,c.c_float],loc,*value)
        self.call('glDrawArrays',None,[c.c_uint,c.c_int,c.c_int],0x0004,0,6)
        self.call('glReadBuffer',None,[c.c_uint],0x8CE0+read)
        pixels=(c.c_float*(self.w*self.h*4))()
        self.call('glReadPixels',None,[c.c_int]*4+[c.c_uint,c.c_uint,c.c_void_p],0,0,self.w,self.h,0x1908,0x1406,pixels)
        assert self.call('glGetError',c.c_uint,[])==0
        assert all(math.isfinite(x) for x in pixels), 'Non-finite output'
        return list(pixels)

    def close(self):
        for program in self.programs: self.api['delete_program'](program)
        for tex in self.textures: self.call('glDeleteTextures',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(tex))
        self.call('glDeleteFramebuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(self.fbo))
        self.call('glDeleteVertexArrays',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(self.vao))


def run(api):
    f=Fixture(api)
    w,h=f.w,f.h
    pixels=w*h
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    near,far=0.05,256.0
    a,b=-(far+near)/(far-near),-2*far*near/(far-near)
    projection=[1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0]
    inverse=[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    depth=lambda z:(-a+b/z)*0.5+0.5
    values=dict(api['resolve']('HIGH'),DOF=False,BLOOM=False,VIGNETTE=False)
    uniforms=dict(viewWidth=float(w),viewHeight=float(h),near=near,far=far,frameTime=1/60,
                  frameCounter=20,gbufferProjection=projection,gbufferProjectionInverse=inverse,
                  gbufferModelViewInverse=identity,gbufferPreviousModelView=identity,
                  gbufferPreviousProjection=projection,cameraPosition=(0.,0.,0.),previousCameraPosition=(0.,0.,0.),
                  sunPosition=(0.,1.,0.),colortex0=0,depthtex0=1,colortex2=2,colortex13=3)
    scene=[]
    for y in range(h):
        for x in range(w):
            c0=1.0 if (x+y)%2==0 else 1.2
            scene.extend((c0,c0,c0,1))
    f.texture(scene,0)
    f.texture([depth(4),0,0,1]*pixels,1)
    f.texture([0,0,0,0]*pixels,2)
    f.texture([1.05,1.05,1.05,4]*pixels,3)
    target=f.texture(None,4); hist=f.texture(None,5)
    program=f.program('composite5.fsh',values)
    center=((h//2)*w+w//2+1)*4
    current=scene[center]
    assert current==1.0
    result=f.render(program,[target,hist],uniforms,read=1)
    assert 1.01<result[center]<1.06, 'Valid history was not accumulated'
    assert abs(result[center+3]-4)<0.002, 'History depth incorrect'
    shifted=projection.copy(); shifted[12]=0.12
    moving=f.render(program,[target,hist],dict(uniforms,gbufferPreviousProjection=shifted),read=1)
    assert 1.005<moving[center]<1.06, 'Camera motion discarded valid history'
    f.texture([1.05,1.05,1.05,8]*pixels,3)
    rejected=f.render(program,[target,hist],uniforms,read=1)
    assert abs(rejected[center]-current)<0.0001, 'Disocclusion retained old depth'
    f.texture([1.05,1.05,1.05,4]*pixels,3)
    reset=f.render(program,[target,hist],dict(uniforms,cameraPosition=(3.,0.,0.)),read=1)
    assert abs(reset[center]-current)<0.0001, 'Camera cut retained history'
    f.texture([0,0,0,1]*pixels,2); f.texture([0.5,0,0,1]*pixels,1)
    hand=f.render(program,[target,hist],uniforms,read=1)
    assert abs(hand[center]-current)<0.0001 and hand[center+3]==-2, 'Hand history leaked'
    print('PASS: GPU temporal HDR history, motion reprojection, depth rejection, camera cuts, hand rejection',flush=True)
    f.close()

    for q,scale in [(1,1/1.3),(2,1/1.5),(3,1/1.7)]:
        f=Fixture(api)
        aw,ah=int(w*scale),int(h*scale)
        data=[]
        for y in range(h):
            for x in range(w):
                data.extend((0.3,0.4,0.5,1) if x<aw and y<ah else (100,0,100,1))
        f.texture(data,0)
        easu=f.texture(None,1); rcas=f.texture(None,2)
        values=dict(api['resolve']('HIGH'),UPSCALE_QUALITY=str(q))
        eprog=f.program('composite7.fsh',values)
        rprog=f.program('final.fsh',values)
        u=dict(viewWidth=float(w),viewHeight=float(h),colortex0=0,colortex14=1)
        out=f.render(eprog,[easu],u)
        sharpened=f.render(rprog,[rcas],u)
        for output in (out,sharpened):
            assert max(abs(output[i]-[0.3,0.4,0.5,1][i%4]) for i in range(len(output)))<0.003, 'FSR border contamination / constant-color shift'
        # Exercise the actual viewport transform and logical-UV mapping on an odd allocation.
        copy_source=api['source'](api['ROOT']/'composite6.fsh',values,False)
        copy_source=copy_source[:copy_source.rfind('void main(){')]+'void main(){color=textureScreen(colortex0,texcoord);}'
        copy_program=f.program('composite6.fsh',values,scaled=True,fragment=copy_source)
        scaled_target=f.texture([-10,-10,-10,-10]*pixels,6)
        copied=f.render(copy_program,[scaled_target],u)
        for y in range(h):
            for x in range(w):
                i=(y*w+x)*4
                expected=0.3 if x<aw and y<ah else -10.0
                assert abs(copied[i]-expected)<0.0001, ('Scaled viewport mismatch',q,x,y,copied[i])
        # Spatial ramp checks orientation, viewport mapping and useful subpixel interpolation.
        ramp=[]
        for y in range(h):
            for x in range(w):
                ramp.extend(((x+0.5)/aw,(y+0.5)/ah,0.25,1) if x<aw and y<ah else (100,0,100,1))
        f.texture(ramp,0)
        ramp_out=f.render(eprog,[easu],u)
        for y in range(4,h-4):
            for x in range(4,w-4):
                i=(y*w+x)*4
                assert abs(ramp_out[i]-(x+0.5)/w)<0.015
                assert abs(ramp_out[i+1]-(y+0.5)/h)<0.015
        # Check high-contrast reconstruction and true-black RCAS (including image borders).
        edge=[]
        for y in range(h):
            for x in range(w):
                v=float(x>=aw//2)
                edge.extend((v,v,v,1) if x<aw and y<ah else (100,0,100,1))
        f.texture(edge,0)
        out=f.render(eprog,[easu],u)
        sharp=f.render(rprog,[rcas],u)
        assert max(out)<=1.0001 and min(out)>=-0.0001
        assert max(sharp)<=1.0001 and min(sharp)>=-0.0001
        assert sharp[(h//2*w+8)*4]<0.001 and sharp[(h//2*w+w-9)*4]>0.998, (q,sharp[(h//2*w+8)*4],sharp[(h//2*w+w-9)*4],out[(h//2*w+w-9)*4])
        print(f'PASS: GPU FSR 1 mode {q}, odd viewport {w}x{h}, EASU/RCAS constants, black/white edges, unused-region isolation',flush=True)
        f.close()

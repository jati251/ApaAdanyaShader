"""Render actual DH water vertices/fragments over independently allocated vanilla depth."""
import ctypes as c
import math
from quality_checks import Fixture


def run(api):
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    for upscale in ('0','1'):
        f=Fixture(api,160,90)
        values=dict(api['resolve']('REALISM_FAST'),UPSCALE_QUALITY=upscale,
                    SHADOWS=False,CLOUD_SHADOWS=False)
        vertex=api['source'](api['ROOT']/'dh_water.vsh',values,True)
        fragment=api['source'](api['ROOT']/'dh_water.fsh',values,True)
        p=f.program('composite7.fsh',values,fragment=fragment,vertex_source=vertex)
        f.texture([.12,.16,.10,1]*(f.w*f.h),0)
        # Opaque-only depth stays clear: also check the current vanilla depth
        # owns a translucent surface that isn't present in depthtex1.
        f.texture([1,0,0,1]*(f.w*f.h),2)
        f.texture([.30,.42,.65,1]*(128*64),3,128,64)
        f.texture([1,0,0,1]*(f.w*f.h),6)
        color=f.texture(None,4); normal=f.texture(None,5); material=f.texture(None,7)
        targets=[color,normal,material]
        buffer=c.c_uint()
        f.call('glGenBuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(buffer))
        f.call('glBindBuffer',None,[c.c_uint,c.c_uint],0x8892,buffer)
        location=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],p,b'aa_Vertex')
        assert location>=0
        f.call('glEnableVertexAttribArray',None,[c.c_uint],location)
        f.call('glVertexAttribPointer',None,[c.c_uint,c.c_int,c.c_uint,c.c_ubyte,c.c_int,c.c_void_p],
               location,4,0x1406,0,0,None)
        for name,attr in [('aa_Normal',(0.,1.,0.,0.)),('aa_Color',(1.,1.,1.,1.)),
                          ('aa_MultiTexCoord0',(0.,0.,0.,1.)),('aa_MultiTexCoord1',(0.,1.,0.,1.))]:
            loc=f.call('glGetAttribLocation',c.c_int,[c.c_uint,c.c_char_p],p,name.encode())
            if loc>=0: f.call('glVertexAttrib4f',None,[c.c_uint]+[c.c_float]*4,loc,*attr)
        pitch=math.radians(60); cs,sn=math.cos(pitch),math.sin(pitch)
        model=[1,0,0,0,0,cs,sn,0,0,-sn,cs,0,0,0,0,1]
        model_inverse=[1,0,0,0,0,cs,-sn,0,0,sn,cs,0,0,0,0,1]
        def projection(near,far):
            fy=1/math.tan(math.radians(65)/2); fx=fy*f.h/f.w
            a=-(far+near)/(far-near); b=-2*far*near/(far-near)
            return ([fx,0,0,0,0,fy,0,0,0,0,a,-1,0,0,b,0],
                    [1/fx,0,0,0,0,1/fy,0,0,0,0,0,1/b,0,0,-1,a/b])
        proj,inv=projection(.05,256.)
        dh_proj,dh_inv=projection(.05,4096.)
        base=dict(viewWidth=float(f.w),viewHeight=float(f.h),
            aa_ModelView=model,aa_Projection=dh_proj,
            **{'aa_TextureMatrix[0]':identity,'aa_TextureMatrix[1]':identity},
            gbufferModelView=model,gbufferModelViewInverse=model_inverse,
            gbufferProjection=proj,gbufferProjectionInverse=inv,dhProjectionInverse=dh_inv,
            colortex6=0,depthtex0=1,depthtex1=2,colortex7=3,dhDepthTex1=6,
            frameTimeCounter=12.,rainStrength=0.,sunPosition=(0.,1.,0.),
            shadowLightPosition=(0.,-1.,0.),near=.05,far=256.,isEyeInWater=0)
        # The same fixed world plane, two alternative triangle diagonals.
        points=[(-256.,0.,-512.),(256.,0.,-512.),(256.,0.,100.),(-256.,0.,100.)]
        def mesh(camera,diagonal):
            indices=(0,1,2,0,2,3) if diagonal==0 else (0,1,3,1,2,3)
            data=(c.c_float*24)(*[v for i in indices for v in
                 (*[a-b for a,b in zip(points[i],camera)],1.)])
            f.call('glBufferData',None,[c.c_uint,c.c_ssize_t,c.c_void_p,c.c_uint],
                   0x8892,c.sizeof(data),data,0x88E0)
        sentinel=(-.125,-.25,-.375,-.5)
        def draw(camera,diagonal=0):
            mesh(camera,diagonal)
            # Discard must preserve all attachments, not merely final RGB.
            f.call('glBindFramebuffer',None,[c.c_uint,c.c_uint],0x8D40,f.fbo)
            for i,t in enumerate(targets):
                f.call('glFramebufferTexture2D',None,[c.c_uint]*4+[c.c_int],
                       0x8D40,0x8CE0+i,0x0DE1,t,0)
            buffers=(c.c_uint*3)(0x8CE0,0x8CE1,0x8CE2)
            f.call('glDrawBuffers',None,[c.c_int,c.POINTER(c.c_uint)],3,buffers)
            for i in range(3):
                f.call('glClearBufferfv',None,[c.c_uint,c.c_int,c.POINTER(c.c_float)],
                       0x1800,i,(c.c_float*4)(*sentinel))
            return f.render(p,targets,dict(base,cameraPosition=camera))
        # Both approaching/jumping and crossing the old 24-block radial cutoff.
        cameras=[(15.9,1.62,0.),(16.1,2.87,-.4),(16.1,23.999,0.),(16.1,24.001,0.),(16.1,45.,0.)]
        for depth in (.5,.9999):
            f.texture([depth,0,0,1]*(f.w*f.h),1)
            f.texture([depth if depth>.99 else 1.,0,0,1]*(f.w*f.h),2)
            for camera in cameras:
                for diagonal in (0,1):
                    output=draw(camera,diagonal)
                    assert max(abs(v-sentinel[i%4]) for i,v in enumerate(output))<1e-6, \
                        'DH water overwrites a vanilla-covered riverbed/translucent surface on camera motion'
                    for attachment in (1,2):
                        f.call('glReadBuffer',None,[c.c_uint],0x8CE0+attachment)
                        data=(c.c_float*(f.w*f.h*4))()
                        f.call('glReadPixels',None,[c.c_int]*4+[c.c_uint,c.c_uint,c.c_void_p],
                               0,0,f.w,f.h,0x1908,0x1406,data)
                        assert max(abs(v-sentinel[i%4]) for i,v in enumerate(data))<1e-6, \
                            'Occluded LOD water still writes its normal/material mask'
        # Missing vanilla coverage must retain distant water, and must not have
        # the old moving spherical hole. Compare actual vertex triangulations.
        f.texture([1,0,0,1]*(f.w*f.h),1)
        active_w=int(f.w*(1/1.3 if upscale=='1' else 1))
        active_h=int(f.h*(1/1.3 if upscale=='1' else 1))
        sample=((active_h//2)*f.w+active_w//2)*4
        for camera in cameras:
            first=draw(camera)
            assert first[sample+3]==1, 'LOD water vanishes without vanilla coverage near the camera'
            second=draw(camera,1)
            error=max(abs(first[(y*f.w+x)*4+k]-second[(y*f.w+x)*4+k])
                      for y in range(3,active_h-3) for x in range(3,active_w-3) for k in range(3))
            assert error<.003, f'LOD water changes across alternative mesh diagonals: {error}'
        # Sharp coverage edges must not be depth-filtered into a moving halo;
        # one side remains vanilla and the other still renders LOD water.
        coverage=[]
        for y in range(f.h):
            for x in range(f.w): coverage.extend((.5 if x<active_w//2 else 1.,0,0,1))
        f.texture(coverage,1)
        for camera in cameras:
            output=draw(camera)
            for y in range(3,active_h-3):
                for x in range(3,active_w-3):
                    i=(y*f.w+x)*4
                    expected=sentinel[3] if x<active_w//2 else 1.
                    assert output[i+3]==expected, 'Vanilla/LOD water boundary changes with camera height or render scale'
        f.call('glDeleteBuffers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(buffer))
        f.close()
    print('PASS: GPU actual DH water mesh preserves vanilla RGB/normal/material coverage during jumps/approach, native/FSR',flush=True)
    print('PASS: GPU DH-only water retained, two mesh diagonals agree, no moving 24-block hole',flush=True)

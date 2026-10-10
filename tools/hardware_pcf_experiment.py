"""Validate shipped four-tap hardware PCF against the unchanged eight-tap PCSS filter."""
import ctypes as c
import json
import pathlib
import statistics
import sys
from round2_checks import setup, source, fullscreen, gpu_batch_draw
from performance_checks import compare_times, save_png
from advanced_checks import AdvancedFixture, IDENTITY


def main():
    api=setup();f=AdvancedFixture(api,1280,720);out=api['ROOT'].parent/'artifacts/performance-round2'
    try:
        values=dict(api['resolve']('REALISM_RT'),UPSCALE_QUALITY='0')
        reference=api['ROOT'].parents[2]/'.codex-backups/performance-round2-20261008/shaders'
        base=source(api,reference,'gbuffers_terrain.fsh',values).split('in vec2 texcoord,')[0]
        hardware=source(api,api['ROOT'],'gbuffers_terrain.fsh',values).split('in vec2 texcoord,')[0]
        hardware=hardware.replace('#version 430 core','#version 430 core\n#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS',1)
        hardware=hardware.replace('#version 410 core','#version 410 core\n#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS',1)
        hardware=hardware.replace('#version 330 core','#version 330 core\n#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS',1)
        tail='''in vec2 texcoord;uniform float testHeight;layout(location=0) out vec4 color;
void main(){float v=shadowVisibility(vec3((texcoord-.5)*90.0,testHeight),vec3(0),1.0,true);color=vec4(v,v,v,1);}
'''
        fallback=source(api,api['ROOT'],'gbuffers_terrain.fsh',values).split('in vec2 texcoord,')[0]
        disabled=source(api,api['ROOT'],'gbuffers_terrain.fsh',dict(values,HARDWARE_PCF=False)).split('in vec2 texcoord,')[0]
        disabled=disabled.replace('#version 430 core','#version 430 core\n#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS',1)
        disabled=disabled.replace('#version 410 core','#version 410 core\n#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS',1)
        disabled=disabled.replace('#version 330 core','#version 330 core\n#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS',1)
        programs=[fullscreen(f,code+tail,values) for code in (base,hardware,fallback,disabled)]
        size=2048;data=[]
        for y in range(size):
            for x in range(size):
                edge=900+int(90*((y//21)%5-2))
                data.append(.5 if x<edge or (x//31+y//47)%7==0 else 1.0)
        texture=f.texture(None,0,1,1)
        f.call('glTexImage2D',None,[c.c_uint,c.c_int,c.c_int,c.c_int,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_void_p],
               0x0DE1,0,0x8CAC,size,size,0,0x1902,0x1406,(c.c_float*len(data))(*data))
        f.call('glActiveTexture',None,[c.c_uint],0x84C1);f.call('glBindTexture',None,[c.c_uint,c.c_uint],0x0DE1,texture)
        sampler=c.c_uint();f.call('glGenSamplers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(sampler))
        for key,value in [(0x884C,0x884E),(0x884D,0x0203),(0x2800,0x2601),(0x2801,0x2601),(0x2802,0x812F),(0x2803,0x812F)]:
            f.call('glSamplerParameteri',None,[c.c_uint,c.c_uint,c.c_int],sampler,key,value)
        f.call('glBindSampler',None,[c.c_uint,c.c_uint],1,sampler)
        target=f.texture_format(None,2)
        u=dict(viewWidth=1280.,viewHeight=720.,shadowtex0=0,shadowtex0HW=1,
               shadowModelView=IDENTITY,shadowProjection=[1/64,0,0,0,0,1/64,0,0,0,0,-1/128,0,0,0,0,1])
        results=[]
        for height in (-.2,-1.,-8.,-32.):
            captures=[f.render(p,[target],dict(u,testHeight=height)) for p in programs]
            assert captures[0]==captures[2]==captures[3], 'Unsupported separate hardware samplers changed fallback filter'
            errors=[abs(a-b) for a,b in zip(captures[0][::4],captures[1][::4])]
            assert statistics.mean(errors)<.008 and sum(v>.05 for v in errors)/len(errors)<.06
            results.append(dict(height=height,mean_shadow_error=statistics.mean(errors),max_shadow_error=max(errors),
                                changed_fraction=sum(v>.05 for v in errors)/len(errors)))
            if height==-8.:
                save_png(out/'pcf-original.png',captures[0],f.w,f.h);save_png(out/'pcf-after.png',captures[1],f.w,f.h)
        draw=gpu_batch_draw(f,64);use=f.bind('glUseProgram',None,c.c_uint)
        def action(p):use(p);draw()
        compare_times(f,'PCSS + shipped four-tap hardware filter',lambda:action(programs[0]),lambda:action(programs[1]),results,1)
        for key in ('before_ms','after_ms'):results[-1][key]/=64
        for key in ('before_range_ms','after_range_ms'):results[-1][key]=[x/64 for x in results[-1][key]]
        (out/'pcf-experiment.json').write_text(json.dumps(results,indent=2));print(results,flush=True)
        f.call('glBindSampler',None,[c.c_uint,c.c_uint],1,0)
        f.call('glDeleteSamplers',None,[c.c_int,c.POINTER(c.c_uint)],1,c.byref(sampler))
    finally:f.close();api['driver'].close()


if __name__=='__main__':main()

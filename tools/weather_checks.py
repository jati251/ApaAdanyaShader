"""GPU regressions for water optics, wave filtering, cloud volume and reflection cache."""
import math
from pathlib import Path
from quality_checks import Fixture


def run(api):
    f=Fixture(api,192,96)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    values=api['resolve']('REALISM')
    prefix=api['source'](api['ROOT']/'prepare.fsh',values,False).split('in vec2 texcoord;')[0]
    water=api['expand'](api['ROOT']/'lib/water.glsl')
    target=f.texture(None,0)
    uniforms={'gbufferModelViewInverse':identity,'sunPosition':[0.4,0.7,0.3],
              'cameraPosition':[0.,80.,0.],'frameTimeCounter':3.0,'rainStrength':0.0}
    def render(body,extra='',inputs=None,octaves=None):
        bands='' if octaves is None else f'\n#undef WATER_OCTAVES\n#define WATER_OCTAVES {octaves}\n'
        fragment=prefix+bands+water+'\nin vec2 texcoord;\nlayout(location=0) out vec4 color;\n'+extra+'\nvoid main(){'+body+'}\n'
        program=f.program('prepare.fsh',values,fragment=fragment)
        return f.render(program,[target],dict(uniforms,**(inputs or {})))
    pixels=render('''float nv=texcoord.x;
        color=vec4(waterFresnel(nv,false),waterFresnel(nv,true),0.0,1.0);''')
    def at(p,x,y=48): return p[(y*f.w+x)*4:(y*f.w+x)*4+4]
    normal=at(pixels,f.w-1)
    assert abs(normal[0]-.0204)<.0001, 'Water normal-incidence Fresnel changed'
    assert at(pixels,0)[0]>.97, 'Grazing water must reflect'
    assert abs(at(pixels,100)[1]-1)<1e-5, 'Underwater critical angle must totally reflect'
    assert at(pixels,170)[1]<.06, 'Subcritical underwater rays must transmit'
    body='''float crest;
        vec2 slope=waterSlope(texcoord*30.0,vec2(footprint,0.0),vec2(0.0,footprint),crest);
        color=vec4(slope,crest,1.0);'''
    near=render(body,'uniform float footprint;',{'footprint':.01})
    # The longest swell is ~35 blocks: an 80-block footprint is unresolved.
    distant=render(body,'uniform float footprint;',{'footprint':80.0})
    mid=render(body,'uniform float footprint;',{'footprint':4.0})
    energy=lambda p:sum(p[i]**2+p[i+1]**2 for i in range(0,len(p),4))
    assert energy(distant)<energy(near)*.01, 'Unresolved waves must be suppressed'
    assert energy(distant)<energy(mid)<energy(near), 'Distant water lost its resolvable swell'
    # The approved audit truncates unresolved upper octaves, including crests.
    # Far water must retain both swell crests; loss is bounded by upper amplitudes.
    swell=render(body,'uniform float footprint;',{'footprint':80.0},octaves=2)
    assert max(abs(a-b) for a,b in zip(swell[2::4],distant[2::4]))<1e-5, 'Octave culling removed the base swell crests'
    assert all(-1e-5<=a-b<=0.1722+1e-5 for a,b in zip(near[2::4],distant[2::4])), 'Culled crest contribution exceeded upper-band amplitude'
    rainy_near=render(body,'uniform float footprint;',{'footprint':.001,'rainStrength':1.0})
    dry_near=render(body,'uniform float footprint;',{'footprint':.001})
    rainy_far=render(body,'uniform float footprint;',{'footprint':80.0,'rainStrength':1.0})
    assert energy(rainy_near)>energy(dry_near), 'Resolved rain ripples disappeared'
    assert energy(rainy_far)<energy(rainy_near)*.001, 'Subpixel rain ripples remain unfiltered during camera motion'
    # Once both ring layers are unresolved, rain may scale the swell but must
    # not leave a camera-sampled cellular pattern over it.
    rainy_mid=render(body,'uniform float footprint;',{'footprint':.1,'rainStrength':1.0})
    dry_mid=render(body,'uniform float footprint;',{'footprint':.1})
    error=max(abs(rainy_mid[i]-dry_mid[i]*1.65) for i in range(len(dry_mid)) if i%4<2)
    assert error<1e-5, f'Unresolved rain normal contamination: {error:.6f}'
    rain_clock=6283.1853/4.2
    rain_before=render(body,'uniform float footprint;',{'footprint':.001,'rainStrength':1.0,'frameTimeCounter':rain_clock-.0002})
    rain_after=render(body,'uniform float footprint;',{'footprint':.001,'rainStrength':1.0,'frameTimeCounter':rain_clock+.0002})
    assert max(abs(a-b) for a,b in zip(rain_before,rain_after))<.01, 'Rain ripple clock reset changes the normal field'
    print('PASS: GPU rain ripple filtering at near/grazing camera footprints',flush=True)
    moved=render(body,'uniform float footprint;',{'footprint':.01,'frameTimeCounter':3.5})
    assert max(abs(a-b) for a,b in zip(moved,near))>.03, 'Water spectrum is not animated'
    before=render(body,'uniform float footprint;',{'footprint':.01,'frameTimeCounter':6283.183})
    after=render(body,'uniform float footprint;',{'footprint':.01,'frameTimeCounter':6283.187})
    assert max(abs(a-b) for a,b in zip(before,after))<.015, 'Water wave clock has a phase discontinuity'
    gradients=render('''vec2 p=texcoord*30.0; float h,hx0,hx1,hy0,hy1;
        vec2 s=waterSlope(p,vec2(0.01,0),vec2(0,0.01),h);
        waterSlope(p-vec2(0.002,0),vec2(0.01,0),vec2(0,0.01),hx0);
        waterSlope(p+vec2(0.002,0),vec2(0.01,0),vec2(0,0.01),hx1);
        waterSlope(p-vec2(0,0.002),vec2(0.01,0),vec2(0,0.01),hy0);
        waterSlope(p+vec2(0,0.002),vec2(0.01,0),vec2(0,0.01),hy1);
        vec2 numerical=vec2(hx1-hx0,hy1-hy0)/0.004*WATER_WAVES;
        color=vec4(abs(s-numerical),length(s),1);''')
    assert max(gradients[0::4]+gradients[1::4])<.002, 'Wave normals disagree with the crest height field'
    assert max(gradients[2::4])>.12, 'Enhanced waves lost their stronger crest slopes'
    print('PASS: GPU water continuous wave phase and analytic crest gradients',flush=True)
    # Density must be zero outside the slab used for ray intersection.
    density=render('''vec3 p=vec3(texcoord.x*2500.0,CLOUD_ALTITUDE-1.0,texcoord.y*2500.0);
        float below=sampleCloudDensity(p,true);
        p.y=CLOUD_ALTITUDE+CLOUD_ALT_THICK+1.0;
        float above=sampleCloudDensity(p,true);
        p.y=CLOUD_ALTITUDE+40.0;
        color=vec4(below,above,sampleCloudDensity(p,true),1.0);''')
    assert max(density[0::4])==0 and max(density[1::4])==0, 'Cloud bounds and density disagree'
    assert max(density[2::4])>.2 and min(density[2::4])<.01, 'Cloud field lost its weather gaps'
    cloudbody='''float azimuth=(texcoord.x-.5)*2.0*PI,elevation=(texcoord.y-.5)*PI;
        vec3 rd=vec3(cos(azimuth)*cos(elevation),sin(elevation),sin(azimuth)*cos(elevation));
        color=cloudLayer(rd,gl_FragCoord.xy);'''
    below=render(cloudbody)
    above=render(cloudbody,inputs={'cameraPosition':[0.,600.,0.]})
    assert max(below[3::4])>.5 and max(above[3::4])>.5, 'Cloud layer missing from below/above'
    assert all(-.001<=x<=1.001 for x in below[3::4]+above[3::4]), 'Cloud opacity out of bounds'
    # Actual cache entry must contain the same cloud layer rather than sky alone.
    cache=f.program('prepare.fsh',values)
    cached=f.render(cache,[target],uniforms)
    clear=render('''float a=(texcoord.x-.5)*2.0*PI,e=(texcoord.y-.5)*PI;
        color=vec4(min(skyRadiance(vec3(cos(a)*cos(e),sin(e),sin(a)*cos(e))),vec3(6.0)),1.0);''')
    assert sum(abs(a-b) for a,b in zip(cached,clear))/len(clear)>.005, 'Reflection cache has no clouds'
    # Coarse strides must refine a crossed surface rather than step through it.
    near_plane,far_plane=.05,256.0
    a=-(far_plane+near_plane)/(far_plane-near_plane)
    b=-2*far_plane*near_plane/(far_plane-near_plane)
    projection=[1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0]
    inverse=[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    z=5.0
    depth=(-a+b/z)*.5+.5
    f.texture([depth,0,0,1]*(f.w*f.h),1)
    f.texture([1,0,0,1]*(f.w*f.h),2)
    trace=api['expand'](api['ROOT']/'lib/trace.glsl')
    body='vec2 hit;bool found=traceScreen(testDepth,vec3(0,0,-2),normalize(vec3((texcoord-.5)*.3,-1)),.8,8,hit);color=vec4(float(found),0,0,1);'
    params={'testDepth':1,'gbufferProjection':projection,'gbufferProjectionInverse':inverse,'near':near_plane}
    hit=render(body,trace+'\nuniform sampler2D testDepth;',params)
    params['testDepth']=2
    sky=render(body,trace+'\nuniform sampler2D testDepth;',params)
    assert min(hit[0::4])>.99, 'Coarse screen rays missed the plane crossing'
    assert max(sky[0::4])<.01, 'Sky must never become a traced hit'
    print('PASS: GPU screen-space tracing, coarse-step surface refinement and sky rejection',flush=True)
    print('PASS: GPU water Fresnel/TIR, wave animation/filtering, cloud slab/both sides, reflected clouds',flush=True)
    if '--write-previews' in api['sys'].argv:
        # Render a diagnostic panorama of the actual cache; this is not an in-game screenshot.
        try:
            import numpy as np
            from PIL import Image
            out=api['ROOT'].parent/'artifacts'
            out.mkdir(exist_ok=True)
            image=np.array(cached).reshape(f.h,f.w,4)[::-1,:,:3]
            image=np.maximum(image,0)/(1+np.maximum(image,0))
            Image.fromarray(np.uint8(np.clip(image**(1/2.2),0,1)*255)).resize((768,384)).save(out/'sky-cache-preview.png')
        except ImportError:
            pass
    f.close()

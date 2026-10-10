#ifndef AA_SMOKE_LIB
#define AA_SMOKE_LIB
#ifdef AA_SMOKE
#include "/lib/smoke_sources.glsl"
#include "/lib/cloud_noise.glsl"
#include "/lib/smoke_flow.glsl"
uniform usampler2D aaSmokeSources,aaSmokePresence;
#ifndef AA_VOXELS
uniform usampler3D aaSmokeObstacles;
#endif
uniform sampler2D aaSmokePaths;
uvec4 smokePresenceMasks() {
    return uvec4(texelFetch(aaSmokePresence,ivec2(0,0),0).r,
        texelFetch(aaSmokePresence,ivec2(1,0),0).r,
        texelFetch(aaSmokePresence,ivec2(2,0),0).r,
        texelFetch(aaSmokePresence,ivec2(3,0),0).r);
}
bool smokePresent() { return any(notEqual(smokePresenceMasks(),uvec4(0))); }

vec3 smokeFlowShape(float height,int slot,vec4 roof) {
    float node=clamp(height*2.0,0.0,14.9999);
    int index=int(floor(node));
    float fraction=fract(node);
    vec4 path=mix(texelFetch(aaSmokePaths,ivec2(index,slot),0),
                  texelFetch(aaSmokePaths,ivec2(index+1,slot),0),fraction);
    vec2 center=smokePathCenter(path)+smokeGridOrigin().xz;
    float spread=abs(path.z-path.x)*.5;
    // Preserve the temporal response stored in the nodes, but use the continuous
    // obstacle profile between them. No additional cache or noise fetches.
    float linearProfile=mix(smokeRoofSpread(roof,float(index)*.5),
                            smokeRoofSpread(roof,float(index+1)*.5),fraction);
    if(linearProfile>.0001)
        spread=min(1.25,spread*smokeRoofSpread(roof,height)/linearProfile);
    return vec3(center,spread);
}

float smokeDensityFlow(vec3 p,vec3 source,int slot,float ceiling,vec2 clock,vec4 roof) {
    float height=p.y-source.y;
    if(height<=0.0 || height>=ceiling) return 0.0;
    ivec3 cell=ivec3(floor(p-smokeGridOrigin()));
    #ifdef AA_VOXELS
    if(smokeGridInside(cell) && any(notEqual(ivec3(floor(p)),ivec3(floor(source))))
        && texelFetch(aaVoxelData,cell+ivec3(16),0).r!=0u) {
        int other=int(smokeSourceSlot(ivec3(floor(p))));
        if(!smokeSourceAtCell(texelFetch(aaSmokeSources,ivec2(other,0),0).r,cell)) {
            other=int(smokeOverflowSlot(ivec3(floor(p))));
            if(!smokeSourceAtCell(texelFetch(aaSmokeSources,ivec2(other,0),0).r,cell)) return 0.0;
        }
    }
    #else
    if(smokeGridInside(cell) && texelFetch(aaSmokeObstacles,cell,0).r!=0u) return 0.0;
    #endif
    vec3 shape=smokeFlowShape(height,slot,roof);
    float spread=shape.z;
    vec2 offset=p.xz-shape.xy;
    float distanceToFlow=length(offset);
    float seed=hash12(source.xz);
    // Large rising lobes give the column rolling billows, without more noise taps.
    // 30 cycles per 80-second noise period keeps the wrap continuous.
    float pulse=.86+.14*sin(height*2.95-clock.y*2.35619449+seed*6.2831853);
    float baseRadius=(.32+height*.16)*pulse;
    // Expand a soft local billow, not a hollow torus or a flat opaque disc.
    // Dilute widened layers so an obstacle does not multiply emitted smoke.
    float radius=baseRadius+spread;
    float radial=distanceToFlow*distanceToFlow/(radius*radius);
    if(radial>=1.0) return 0.0;
    // Sample world-relative billows, rather than remapping noise when a side
    // opens. Removing or placing a block cannot switch the noise field's phase.
    vec3 field=vec3(offset.x*2.0,height*.9-clock.y*.8,offset.y*2.0)+vec3(seed*19.0);
    float billow=cloudNoise3D(field)*.72+cloudNoise3D(field*2.0+vec3(7.1))*.28;
    float shell=1.0-smoothstep(.10,1.0,radial);
    float rise=smoothstep(0.0,.28,height)*(1.0-smoothstep(ceiling*.65,ceiling,height));
    return shell*rise*smoothstep(.12,.60,billow)*SMOKE_DENSITY*1.8*(baseRadius/radius);
}
float smokeDensity(vec3 p,vec3 source,int slot,float ceiling,vec2 clock) {
    return smokeDensityFlow(p,source,slot,ceiling,clock,texelFetch(aaSmokePaths,ivec2(20,slot),0));
}

bool smokeInterval(int slot,vec3 ray,float sceneDistance,out vec2 interval) {
    vec4 bounds=texelFetch(aaSmokePaths,ivec2(16,slot),0);
    vec3 lo=bounds.xyz+smokeGridOrigin();
    vec3 hi=texelFetch(aaSmokePaths,ivec2(17,slot),0).xyz+smokeGridOrigin();
    hi.y=min(hi.y,lo.y+.05+bounds.w);
    vec3 safeRay=mix(ray,vec3(1e-7),lessThan(abs(ray),vec3(1e-7)));
    vec3 a=(lo-cameraPosition)/safeRay,b=(hi-cameraPosition)/safeRay;
    vec3 lower=min(a,b),upper=max(a,b);
    interval=vec2(max(max(max(lower.x,lower.y),lower.z),0.0),
        min(min(upper.x,upper.y),upper.z));
    // Keep the unoccluded sampling domain. Foreground depth clips integration
    // bins without rescaling every sample in front of that object.
    return min(interval.y,sceneDistance)>interval.x;
}

float smokeSampleDistance(float q,vec2 range,vec2 cap) {
    float left=cap.x-range.x,middle=cap.y-cap.x;
    if(q<left) return range.x+q;
    if(q<left+middle*4.0) return cap.x+(q-left)*.25;
    return cap.y+q-left-middle*4.0;
}

vec3 smokeIllumination(float height,float density,vec3 ambient,vec3 sun,vec3 fire) {
    // Extinction darkens all incoming light together so widened/thinner layers
    // cannot switch from warm sunlight to blue ambient light.
    vec3 glow=fire*exp(-max(height,0.0)*1.4)*0.22*TORCH_BRIGHTNESS;
    return (ambient+sun+glow)*exp(-density*.7);
}

vec4 renderSmoke(vec3 ray,float sceneDistance) {
    uvec4 masks=smokePresenceMasks();
    if(all(equal(masks,uvec4(0)))) return vec4(0.0);
    // Select eight nearby ray contributors plus a ninth for a smooth cutoff.
    // Rank by distance to the plume body, not a rectangular box entry plane.
    int slots[9];vec2 ranges[9];float priorities[9];
    for(int i=0;i<9;i++) {slots[i]=0;ranges[i]=vec2(0);priorities[i]=1e20;}
    int count=0;
    for(int bank=0;bank<4;bank++) {
      if(masks[bank]==0u) continue;
      for(int bit=0;bit<32;bit++) {
        if((masks[bank]&(1u<<uint(bit)))==0u) continue;
        int i=bank*32+bit;
        uint emitterData=texelFetch(aaSmokeSources,ivec2(i,0),0).r;
        if(emitterData==0u) continue;
        vec3 source=smokeSourcePosition(emitterData);
        if(smokeSourceFade(source)<=0.0) continue;
        vec2 range;
        // Selection must also be independent of foreground depth; otherwise a
        // block face changes which overlapping plumes contribute in front of it.
        if(!smokeInterval(i,ray,1e20,range)) continue;
        vec3 body=source+vec3(0,AA_SMOKE_HEIGHT*.5,0)-cameraPosition;
        vec3 lateral=body-ray*max(dot(body,ray),0.0);
        float priority=dot(lateral,lateral)+float(i)*.00001;
        if(priority>=priorities[8]) continue;
        int rank=8;
        for(int j=0;j<9;j++) if(priority<priorities[j]) {rank=j;break;}
        for(int j=8;j>0;j--) if(j>rank) {
            priorities[j]=priorities[j-1];slots[j]=slots[j-1];ranges[j]=ranges[j-1];
        }
        priorities[rank]=priority;slots[rank]=i;ranges[rank]=range;
        count=min(count+1,9);
      }
    }
    vec3 radiance=vec3(0.0);float opticalDepth=0.0;
    // Bend closes after 550 sine cycles; rising noise closes at 64/128 LUT cells.
    // Wrapping clocks must preserve the field during long gameplay sessions.
    vec2 clock=vec2(mod(frameTimeCounter,6283.1853),mod(frameTimeCounter,80.0));
    vec3 lightDirection=worldDirection(shadowLightPosition);
    float phase=0.65+0.65*pow(sat(dot(ray,lightDirection)*0.5+0.5),4.0);
    float sky=smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y));
    vec3 ambient=mix(vec3(0.008,0.011,0.018)*NIGHT_BRIGHTNESS,vec3(0.18,0.18,0.185),daylight())*sky;
    // Use broad sky/sun illumination. A single probe inside an overhead block
    // must not turn the entire plume dark blue when that block is placed.
    vec3 sun=lightColor()*sky*phase*.45;
    for(int k=0;k<AA_SMOKE_RAY_PLUMES;k++) {
        if(k>=count) break;
        int slot=slots[k];uint type=texelFetch(aaSmokeSources,ivec2(slot,0),0).r;
        vec3 source=smokeSourcePosition(type);vec2 range=ranges[k];
        if(range.x>=sceneDistance) continue;
        float fade=smokeSourceFade(source);
        float age=texelFetch(aaSmokePaths,ivec2(21,slot),0).r;
        fade*=smoothstep(0.0,1.5,age);
        // New sources are transparent: skip all density/noise integration.
        if(fade<=.00001) continue;
        float ceiling=texelFetch(aaSmokePaths,ivec2(16,slot),0).w;
        vec4 roof=texelFetch(aaSmokePaths,ivec2(20,slot),0);
        vec2 cap=vec2(range.x);
        if(roof.x>=0.0) {
            vec2 band=source.y+vec2(max(roof.x-1.6,0.0),roof.y+.65);
            if(abs(ray.y)<1e-5) {
                if(cameraPosition.y>=band.x && cameraPosition.y<=band.y) cap=range;
            } else {
                vec2 crossing=(band-cameraPosition.y)/ray.y;
                cap=vec2(max(range.x,min(crossing.x,crossing.y)),
                    min(range.y,max(crossing.x,crossing.y)));
                if(cap.y<=cap.x) cap=vec2(range.x);
            }
        }
        // Continuously warp the bins toward contact layers. Integer left/cap/
        // right sample allocations caused planar jumps as the camera moved.
        float weightedLength=range.y-range.x+(cap.y-cap.x)*3.0;
        vec3 fire=smokeSoulSource(type)?vec3(0.08,0.55,0.85):vec3(1.0,0.24,0.035);
        vec3 scattering=vec3(0.0);float transmission=1.0;
        for(int j=0;j<SMOKE_STEPS;j++) {
            float begin=smokeSampleDistance(float(j)*weightedLength/float(SMOKE_STEPS),range,cap);
            if(begin>=sceneDistance) break;
            float end=min(sceneDistance,smokeSampleDistance(float(j+1)*weightedLength/float(SMOKE_STEPS),range,cap));
            float stepSize=end-begin,t=(begin+end)*.5;
            vec3 p=cameraPosition+ray*t;
            float density=smokeDensityFlow(p,source,slot,ceiling,clock,roof)*fade;
            if(density<=0.0001) continue;
            float alpha=1.0-exp(-density*stepSize);
            vec3 illumination=smokeIllumination(p.y-source.y,density,ambient,sun,fire);
            scattering+=transmission*alpha*illumination;
            transmission*=1.0-alpha;
            if(transmission<0.03) break;
        }
        float alpha=1.0-transmission;
        if(alpha>.00001) {
            float weight=1.0;
            if(count>AA_SMOKE_RAY_PLUMES) {
                float cut=priorities[8];float width=max((cut-priorities[0])*.2,.000001);
                weight=1.0-smoothstep(cut-width,cut,priorities[k]);
            }
            // Merge optical depths without ordering independent whole plumes
            // by their AABBs. Entry-order swaps otherwise leave rectangular seams.
            float tau=-log(max(transmission,.00001))*weight;
            radiance+=scattering/alpha*tau;opticalDepth+=tau;
        }
    }
    float alpha=1.0-exp(-opticalDepth);
    return vec4(radiance/max(opticalDepth,.00001)*alpha,alpha);
}

#ifdef AA_SMOKE_RECONSTRUCT
uniform sampler2D colortex21;
#if !defined(VOLUMETRIC_LIGHT) || !defined(HALF_RES_LIGHTING)
uniform sampler2D colortex12;
#endif
vec4 reconstructSmoke(vec2 uv,vec3 ray,float dist,vec3 vp,float depth,bool isDH) {
    ivec2 size=screenTextureSize(colortex21);
    vec2 p=uv*vec2(size)-0.5,f=fract(p);ivec2 base=ivec2(floor(p));
    float category=isDH?2.0:(depth>=0.999999?0.0:1.0);
    vec4 sum=vec4(0);float total=0.0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 q=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 metadata=texelFetch(colortex12,q,0);
        if(metadata.b!=category) continue;
        float weight=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y);
        weight*=1.0-smoothstep(0.005,0.02,abs(metadata.a+vp.z)/max(-vp.z,1.0));
        sum+=texelFetch(colortex21,q,0)*weight;total+=weight;
    }
    // Preserve near geometry silhouettes rather than blurring smoke across them.
    if(total>=.98) return sum/total;
    vec4 local=renderSmoke(ray,dist);
    return mix(local,sum/max(total,.00001),smoothstep(.25,.95,total));
}
#endif
#endif
#endif

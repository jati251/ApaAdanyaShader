#ifndef AA_RESERVOIR_GI
#define AA_RESERVOIR_GI
#ifdef RESTIR_GI
#if defined(AA_VOXELS) && defined(AA_RESERVOIR_PASS) && defined(HALF_RES_LIGHTING) && defined(TEMPORAL_INDIRECT) && defined(SSGI)
#define AA_RESTIR
layout(rgba32f) uniform image2D aaReservoirPos0,aaReservoirPos1;
layout(rgba32f) uniform image2D aaReservoirMeta0,aaReservoirMeta1;
layout(rgba32f) uniform image2D aaReservoirLight0,aaReservoirLight1;
uniform sampler2D colortex18;
#ifndef AA_PREVIOUS_INDIRECT_UNIFORMS
#define AA_PREVIOUS_INDIRECT_UNIFORMS
uniform mat4 gbufferPreviousModelView,gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
#endif
void clearReservoirGI(vec2 uv) {
    ivec2 size=screenTextureSize(colortex18),q=clamp(ivec2(uv*vec2(size)),ivec2(0),size-1);
    if((frameCounter&1)==0) {
        imageStore(aaReservoirPos0,q,vec4(0));imageStore(aaReservoirMeta0,q,vec4(0));imageStore(aaReservoirLight0,q,vec4(0));
    } else {
        imageStore(aaReservoirPos1,q,vec4(0));imageStore(aaReservoirMeta1,q,vec4(0));imageStore(aaReservoirLight1,q,vec4(0));
    }
}
struct GIReservoir {vec3 point;vec3 normal;vec3 radiance;float target;float weight;float count;};
float reservoirRandom(vec2 pixel,float salt) {
    return hash12(pixel+vec2(float(frameCounter%4096)*0.75487766,salt*17.117));
}
float reservoirTarget(vec3 receiver,vec3 receiverNormal,vec3 point,vec3 normal,vec3 radiance) {
    vec3 delta=point-receiver;float d2=dot(delta,delta);
    if(d2<0.01) return 0.0;
    vec3 direction=delta*inversesqrt(d2);
    return dot(radiance,vec3(0.2126,0.7152,0.0722))*max(dot(receiverNormal,direction),0.0)
        *max(dot(normal,-direction),0.0)/max(d2,0.04);
}
void reservoirOffer(inout GIReservoir r,vec3 point,vec3 normal,vec3 radiance,
                    float target,float weight,float count,float randomValue) {
    r.count+=count;
    if(target<=1e-8 || weight<=0.0 || isnan(weight) || isinf(weight)) return;
    r.weight+=weight;
    if(randomValue*r.weight<=weight) {
        r.point=point;r.normal=normal;r.radiance=radiance;r.target=target;
    }
}
void reuseReservoir(inout GIReservoir r,ivec2 q,vec3 receiver,vec3 N,float randomValue) {
    bool previousZero=(frameCounter&1)!=0;
    vec4 p=previousZero?imageLoad(aaReservoirPos0,q):imageLoad(aaReservoirPos1,q);
    vec4 m=previousZero?imageLoad(aaReservoirMeta0,q):imageLoad(aaReservoirMeta1,q);
    vec4 old=previousZero?imageLoad(aaReservoirLight0,q):imageLoad(aaReservoirLight1,q);
    if(old.a<1.0 || old.a>32.0 || m.a<=1e-8 || p.a<=0.0
       || any(isnan(p)) || any(isinf(p))) return;
    ivec3 cell=ivec3(floor(p.xyz-m.xyz*0.01-voxelGridOrigin()));
    if(!voxelInside(cell)) return;
    uint material=texelFetch(aaVoxelData,cell,0).r;
    if(material==0u) return;
    vec3 radiance=voxelRadiance(p.xyz,m.xyz,material);
    float target=reservoirTarget(receiver,N,p.xyz,m.xyz,radiance);
    if(target<=1e-8) return;
    vec3 delta=p.xyz-receiver;float distance=length(delta);
    vec3 point,normal;uint hitMaterial;
    // Revalidate shifted paths against current occupancy before reusing energy.
    if(!traceVoxelWorldRange(receiver+N*0.08,delta/distance,VOXEL_STEPS,distance+1.34,point,normal,hitMaterial)
       || length(point-p.xyz)>1.25) return;
    float count=min(old.a,8.0);
    float weight=p.a*(count/old.a)*clamp(target/m.a,0.0,8.0);
    reservoirOffer(r,p.xyz,m.xyz,radiance,target,weight,count,randomValue);
}
vec3 sampleReservoirGI(vec2 uv,vec3 vp,vec3 normalV,float rotation,vec2 pixel) {
    vec3 receiver=(gbufferModelViewInverse*vec4(vp,1)).xyz+cameraPosition;
    vec3 N=worldDirection(normalV);
    vec3 tangent=normalize(cross(N,abs(N.y)<0.9?vec3(0,1,0):vec3(1,0,0))),bitangent=cross(N,tangent);
    GIReservoir r=GIReservoir(vec3(0),vec3(0,1,0),vec3(0),0.0,0.0,0.0);
    for(int i=0;i<GI_SAMPLES;i++) {
        float angle=rotation+float(i)*2.39996323;
        float z=sqrt((float(i)+0.5)/float(GI_SAMPLES)),radial=sqrt(1.0-z*z);
        vec3 dir=tangent*cos(angle)*radial+bitangent*sin(angle)*radial+N*z;
        vec3 point,normal,radiance=vec3(0);uint material;
        float target=0.0;
        if(traceVoxelWorld(receiver+N*0.08,dir,VOXEL_STEPS,point,normal,material)) {
            radiance=voxelRadiance(point,normal,material);
            // A back-facing hit has zero target regardless of any second bounce.
            // Keep visibility checks and both bounces for contributing paths.
            float geometryTarget=reservoirTarget(receiver,N,point,normal,vec3(1.0));
            #if GI_BOUNCES > 1
            if(geometryTarget>0.0) {
            vec3 t=normalize(cross(normal,abs(normal.y)<0.9?vec3(0,1,0):vec3(1,0,0))),b=cross(normal,t);
            float u=reservoirRandom(pixel,float(i)+0.31),v=reservoirRandom(pixel,float(i)+7.7);
            vec3 secondDir=t*(sqrt(u)*cos(v*2.0*PI))+b*(sqrt(u)*sin(v*2.0*PI))+normal*sqrt(1.0-u);
            vec3 secondPoint,secondNormal;uint secondMaterial;
            if(traceVoxelWorld(point+normal*0.08,secondDir,min(VOXEL_STEPS,48),secondPoint,secondNormal,secondMaterial))
                radiance+=min(voxelAlbedo(material),vec3(0.95))*voxelRadiance(secondPoint,secondNormal,secondMaterial);
            }
            #endif
            float luma=dot(radiance,vec3(0.2126,0.7152,0.0722));
            radiance*=min(1.0,6.0/max(luma,1e-4));
            target=reservoirTarget(receiver,N,point,normal,radiance);
        }
        // Convert the cosine-direction proposal to area at the hit. Geometry
        // cancels in target/pdf, leaving PI*luminance for fresh candidates.
        float weight=target>0.0?PI*dot(radiance,vec3(0.2126,0.7152,0.0722)):0.0;
        reservoirOffer(r,point,normal,radiance,target,weight,1.0,reservoirRandom(pixel,float(i)+1.0));
    }
    ivec2 size=screenTextureSize(colortex18),q=clamp(ivec2(uv*vec2(size)),ivec2(0),size-1);
    vec3 travel=cameraPosition-previousCameraPosition;
    if(frameCounter>=2 && frameTime>0.0 && frameTime<0.2 && dot(travel,travel)<4.0
       && abs(gbufferProjection[1][1]-gbufferPreviousProjection[1][1])<0.01) {
        vec4 oldView=gbufferPreviousModelView*vec4(receiver-previousCameraPosition,1);
        vec4 clip=gbufferPreviousProjection*oldView;
        vec2 previousUV=clip.xy/max(clip.w,1e-6)*0.5+0.5;
        ivec2 previous=ivec2(previousUV*vec2(size));
        if(clip.w>0.0 && all(greaterThanEqual(previous,ivec2(1))) && all(lessThan(previous,size-1))) {
            const ivec2 offsets[5]=ivec2[5](ivec2(0),ivec2(1,0),ivec2(-1,0),ivec2(0,1),ivec2(0,-1));
            for(int tap=0;tap<3;tap++) {
                int index=tap==0?0:1+((frameCounter+tap-1)&3);
                ivec2 source=previous+offsets[index];
                vec4 geometry=texelFetch(colortex18,source,0);
                if(geometry.a>0.0 && abs(geometry.a+oldView.z)<max(0.08,-oldView.z*0.02) && dot(geometry.xyz,N)>0.95)
                    reuseReservoir(r,source,receiver,N,reservoirRandom(pixel,float(tap)+20.0));
            }
        }
    }
    float count=min(r.count,32.0),weight=r.weight*count/max(r.count,1.0);
    vec4 p=vec4(r.point,weight),m=vec4(r.normal,r.target),light=vec4(r.radiance,count);
    if((frameCounter&1)==0) {
        imageStore(aaReservoirPos0,q,p);imageStore(aaReservoirMeta0,q,m);imageStore(aaReservoirLight0,q,light);
    } else {
        imageStore(aaReservoirPos1,q,p);imageStore(aaReservoirMeta1,q,m);imageStore(aaReservoirLight1,q,light);
    }
    float selectedLuma=dot(r.radiance,vec3(0.2126,0.7152,0.0722));
    vec3 result=r.target>0.0?r.radiance/max(selectedLuma,1e-6)*weight/max(count,1.0)/PI:vec3(0);
    float luma=dot(result,vec3(0.2126,0.7152,0.0722));
    return result*min(1.0,6.0/max(luma,1e-4));
}
#endif
#endif
#endif


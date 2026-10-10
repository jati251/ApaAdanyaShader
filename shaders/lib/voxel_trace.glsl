#ifndef AA_VOXEL_TRACE
#define AA_VOXEL_TRACE
#include "/lib/voxel_data.glsl"
#ifdef AA_VOXELS
uniform usampler3D aaVoxelData;
uniform sampler3D aaVoxelLight;
// World grid is snapped every frame. Integer DDA visits each crossed cell once.
// A slab intersection also allows receivers outside the local volume to enter it.
bool traceVoxelWorldRange(vec3 origin,vec3 direction,int budget,float maxDistance,out vec3 point,out vec3 normal,out uint material) {
    point=origin; normal=vec3(0); material=0u;
    if(any(notEqual(textureSize(aaVoxelData,0),ivec3(64)))) return false;
    vec3 local=origin-voxelGridOrigin();
    vec3 safeDir=mix(direction,vec3(1e-7),lessThan(abs(direction),vec3(1e-7)));
    vec3 inv=1.0/safeDir;
    vec3 first=(vec3(0)-local)*inv,last=(vec3(64)-local)*inv;
    vec3 lower=min(first,last),upper=max(first,last);
    float entry=max(max(lower.x,lower.y),lower.z),exit=min(min(min(upper.x,upper.y),upper.z),maxDistance);
    float t=max(entry,0.0)+0.001;
    if(exit<=t) return false;
    ivec3 cell=ivec3(floor(local+direction*t));
    ivec3 stepDir=ivec3(sign(safeDir));
    vec3 nextBoundary=vec3(cell)+step(vec3(0),safeDir);
    vec3 nextT=(nextBoundary-local)*inv;
    vec3 deltaT=abs(inv);
    // Skip the originating voxel: raster surfaces can lie inside their solid block.
    ivec3 originCell=ivec3(floor(local));
    for(int i=0;i<128;i++) {
        if(i>=budget || t>exit || !voxelInside(cell)) break;
        uint v=texelFetch(aaVoxelData,cell,0).r;
        if(v!=0u && any(notEqual(cell,originCell))) {
            point=origin+direction*t;
            if(dot(normal,normal)<0.5) normal=voxelNormal(v);
            material=v;return true;
        }
        int axis=nextT.x<=nextT.y && nextT.x<=nextT.z?0:(nextT.y<=nextT.z?1:2);
        t=nextT[axis];
        // Advance tied axes together; a corner-touching cell has zero ray length.
        bvec3 crossed=lessThanEqual(nextT,vec3(t+1e-5));
        ivec3 advance=ivec3(crossed);
        nextT+=deltaT*vec3(advance);
        cell+=stepDir*advance;
        normal=vec3(0);normal[axis]=-float(stepDir[axis]);
    }
    return false;
}
bool traceVoxelWorld(vec3 origin,vec3 direction,int budget,out vec3 point,out vec3 normal,out uint material) {
    return traceVoxelWorldRange(origin,direction,budget,1e20,point,normal,material);
}
vec3 voxelRadiance(vec3 point,vec3 normal,uint material) {
    ivec3 cell=clamp(ivec3(floor(point-normal*0.01-voxelGridOrigin())),ivec3(0),ivec3(63));
    vec4 light=texelFetch(aaVoxelLight,cell,0);
    return light.rgb+voxelAlbedo(material)*lightColor()*light.a
        *max(0.0,dot(normal,worldDirection(shadowLightPosition)))/PI;
}
bool traceVoxelView(vec3 origin,vec3 direction,out vec3 radiance,out float confidence) {
    vec3 world=(gbufferModelViewInverse*vec4(origin,1)).xyz+cameraPosition;
    vec3 point,normal;uint material;
    if(!traceVoxelWorld(world,worldDirection(direction),VOXEL_STEPS,point,normal,material)) {
        radiance=vec3(0);confidence=0.0;return false;
    }
    radiance=voxelRadiance(point,normal,material);
    // Fade the scene boundary rather than making a hard 32-block cutoff.
    vec3 edge=min(point-voxelGridOrigin(),voxelGridOrigin()+vec3(64)-point);
    confidence=smoothstep(0.0,3.0,min(edge.x,min(edge.y,edge.z)));
    return confidence>0.001;
}
#endif
#endif

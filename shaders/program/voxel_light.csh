#include "/lib/common.glsl"
#include "/lib/voxel_data.glsl"
// Each group spans four complete vertical columns. Sky access for an occupied
// cell is exactly equivalent to being the highest occupied cell in its column.
layout(local_size_x=4,local_size_y=64,local_size_z=1) in;
const ivec3 workGroups=ivec3(16,1,64);
#ifdef AA_VOXELS
uniform usampler3D aaVoxelData;
uniform sampler2D shadowtex0;
layout(rgba16f) uniform writeonly image3D aaVoxelLightImage;
shared int columnTop[4];
#endif
void main() {
    #ifdef AA_VOXELS
    ivec3 cell=ivec3(gl_GlobalInvocationID);
    uint material=texelFetch(aaVoxelData,cell,0).r;
    int column=int(gl_LocalInvocationID.x);
    if(gl_LocalInvocationID.y==0u) columnTop[column]=-1;
    barrier();
    if(material!=0u) atomicMax(columnTop[column],cell.y);
    barrier();
    if(material==0u) {imageStore(aaVoxelLightImage,cell,vec4(0));return;}
    vec3 albedo=voxelAlbedo(material);
    vec3 lightDirection=worldDirection(shadowLightPosition);
    vec3 rel=voxelGridOrigin()+vec3(cell)+0.5-cameraPosition;
    // A compact diffuse radiance cache, rebuilt after the scene each frame.
    vec4 clip=shadowProjection*shadowModelView*vec4(rel+lightDirection*0.65,1);
    vec3 sc=distortShadow(clip.xyz/clip.w)*0.5+0.5;
    float vis=0.0;
    if(all(greaterThan(sc,vec3(0.002))) && all(lessThan(sc,vec3(0.998))))
        vis=step(sc.z-0.00015,texture(shadowtex0,sc.xy).r);
    // Vertical occupancy measures sky access without reflecting open sky through
    // a closed voxel ceiling. Exiting the local scene remains an approximation.
    float sky=float(cell.y==columnTop[column]);
    vec3 ambient=mix(vec3(0.004,0.006,0.01)*NIGHT_BRIGHTNESS,vec3(0.07,0.09,0.12),daylight())*sky;
    vec3 radiance=albedo*(ambient+voxelEmission(material)*4.0);
    // Retain direct visibility separately. The ray's actual DDA face normal
    // determines its cosine; an atomic winner's face must not shade every face.
    imageStore(aaVoxelLightImage,cell,vec4(radiance,vis));
    #endif
}

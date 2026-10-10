#ifndef AA_VOXEL_DATA
#define AA_VOXEL_DATA
const int AA_VOXEL_SIZE=64;
vec3 voxelGridOrigin() { return floor(cameraPosition)-vec3(32.0); }
bool voxelInside(ivec3 cell) { return all(greaterThanEqual(cell,ivec3(0))) && all(lessThan(cell,ivec3(64))); }
uint packVoxel(vec3 albedo,float emission,vec3 normal) {
    uvec3 rgb=uvec3(clamp(albedo,0.0,1.0)*255.0+0.5);
    vec3 a=abs(normal);
    int axis=a.x>a.y && a.x>a.z?0:(a.y>a.z?1:2);
    uint face=uint(axis*2+(normal[axis]<0.0?1:0));
    return rgb.x|(rgb.y<<8u)|(rgb.z<<16u)|(face<<24u)|(uint(clamp(emission,0.0,15.0))<<27u)|0x80000000u;
}
vec3 voxelAlbedo(uint v) { return vec3(v&255u,(v>>8u)&255u,(v>>16u)&255u)/255.0; }
float voxelEmission(uint v) { return float((v>>27u)&15u)/15.0; }
vec3 voxelNormal(uint v) { uint f=(v>>24u)&7u;vec3 n=vec3(0);n[int(min(f/2u,2u))]=(f&1u)==0u?1.0:-1.0;return n; }
#endif

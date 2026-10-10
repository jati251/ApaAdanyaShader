#include "/lib/common.glsl"
// One 16x16 group contains complete 2/4/8/16-pixel hierarchy cells.
// Shared-memory reduction builds all four atlas levels with one depth read
// per pixel and one dispatch, without sampling intermediate levels.
layout(local_size_x=16,local_size_y=16) in;
const vec2 workGroupsRender=vec2(1.0,1.0);
#ifdef AA_HIZ
layout(rg32f) uniform writeonly image2D aaHiZImage;
uniform sampler2D depthtex0;
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif
#include "/lib/hiz_layout.glsl"
shared vec2 depthTile[256];
#endif
void main() {
    #ifdef AA_HIZ
    ivec2 size=ivec2(viewWidth,viewHeight);
    ivec2 base=ivec2(gl_WorkGroupID.xy)*16;
    // This return is uniform for the entire group, including FSR rendering.
    if(any(greaterThanEqual(base,size))) return;
    ivec2 local=ivec2(gl_LocalInvocationID.xy),p=base+local;
    int index=local.y*16+local.x;
    float z=1e20;
    if(all(lessThan(p,size))) {
        vec2 uv=(vec2(p)+0.5)/vec2(size);
        float d=texelFetch(depthtex0,p,0).r;
        z=d<0.999999?-viewDepth(uv,d):1e20;
        #ifdef DISTANT_HORIZONS
        if(d>=0.999999) {
            float dh=depthScreen(dhDepthTex0,uv);
            if(dh<0.999999) z=-projectedViewDepth(dhProjectionInverse,uv,dh);
        }
        #endif
    }
    depthTile[index]=vec2(z);
    barrier();
    for(int level=0;level<4;level++) {
        int scale=2<<level,child=scale/2;
        // Footprints are disjoint within a level, so a footprint's writer
        // cannot race with another footprint's readers. All lanes synchronize.
        if((local.x&(scale-1))==0 && (local.y&(scale-1))==0) {
            vec2 a=depthTile[index],b=depthTile[index+child];
            vec2 c=depthTile[index+child*16],d=depthTile[index+child*17];
            vec2 bounds=vec2(min(min(a.x,b.x),min(c.x,d.x)),max(max(a.y,b.y),max(c.y,d.y)));
            depthTile[index]=bounds;
            ivec2 q=p/scale;
            if(all(lessThan(q,size/scale)))
                imageStore(aaHiZImage,q+hizTileOffset(level,size),vec4(bounds,0,0));
        }
        barrier();
    }
    #endif
}
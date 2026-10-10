#ifndef AA_HIZ_TRACE
#define AA_HIZ_TRACE
#ifdef AA_HIZ
uniform sampler2D aaHiZ;
uniform bool aaHiZReady;
#include "/lib/hiz_layout.glsl"
vec2 hizBounds(int level,ivec2 q,ivec2 size) {
    return texelFetch(aaHiZ,q+hizTileOffset(level,size),0).rg;
}
float hizAdvance(vec4 origin,vec4 direction,vec3 viewOrigin,vec3 viewDirection,
                 vec2 uv,float t,float ordinaryNext,ivec2 depthSize) {
    if(!aaHiZReady) return ordinaryNext;
    vec2 projectedDirection=direction.xy*origin.w-origin.xy*direction.w;
    for(int level=3;level>=0;level--) {
        float tile=float(2<<level);
        ivec2 cell=ivec2(floor(uv*vec2(depthSize)/tile));
        ivec2 grid=depthSize/int(tile);
        if(any(lessThan(cell,ivec2(0))) || any(greaterThanEqual(cell,grid))) continue;
        vec2 boundary=(vec2(cell)+step(vec2(0),projectedDirection))*tile/vec2(depthSize)*2.0-1.0;
        vec2 denominator=direction.xy-boundary*direction.w;
        vec2 exitT=vec2(1e20);
        if(abs(denominator.x)>1e-8) exitT.x=(boundary.x*origin.w-origin.x)/denominator.x;
        if(abs(denominator.y)>1e-8) exitT.y=(boundary.y*origin.w-origin.y)/denominator.y;
        float leave=min(exitT.x>t+1e-5?exitT.x:1e20,exitT.y>t+1e-5?exitT.y:1e20);
        if(leave<=ordinaryNext || leave>=1e19) continue;
        float rayFar=max(-viewOrigin.z-viewDirection.z*t,-viewOrigin.z-viewDirection.z*leave);
        float nearest=hizBounds(level,cell,depthSize).x;
        // Only skip a tile if the entire ray segment is in front of its nearest
        // surface. Min depth is conservative; average mipmaps are not used.
        if(rayFar+0.20<nearest && viewOrigin.z+viewDirection.z*leave<-near)
            return leave+0.0001;
    }
    return ordinaryNext;
}
#endif
#endif

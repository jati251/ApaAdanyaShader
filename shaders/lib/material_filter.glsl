#ifndef AA_MATERIAL_FILTER
#define AA_MATERIAL_FILTER
#if defined(TERRAIN) && MATERIAL_FILTER > 0
flat in vec4 atlasBounds;

// Minecraft's atlas may use nearest filtering. Explicit interpolation avoids
// a diagonal tap lattice and mip-level popping, independent of that sampler.
vec4 materialAtlasLinear(sampler2D atlas,vec2 uv,int level) {
    ivec2 mipSize=textureSize(atlas,level);
    if(any(lessThanEqual(mipSize,ivec2(0)))) {
        level=0; mipSize=textureSize(atlas,0);
    }
    vec2 size=vec2(mipSize);
    ivec2 lo=ivec2(ceil(atlasBounds.xy*size-0.001));
    ivec2 hi=max(lo,ivec2(floor(atlasBounds.zw*size+0.001))-1);
    vec2 p=clamp(uv*size-0.5,vec2(lo),vec2(hi));
    ivec2 q=ivec2(floor(p)); vec2 f=fract(p);
    vec4 a=texelFetch(atlas,clamp(q,lo,hi),level);
    vec4 b=texelFetch(atlas,clamp(q+ivec2(1,0),lo,hi),level);
    vec4 c=texelFetch(atlas,clamp(q+ivec2(0,1),lo,hi),level);
    vec4 d=texelFetch(atlas,clamp(q+ivec2(1,1),lo,hi),level);
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
vec4 materialAtlasLod(sampler2D atlas,vec2 uv,float lod) {
    int level=int(floor(lod)); float blend=fract(lod);
    vec4 a=materialAtlasLinear(atlas,uv,level);
    if(blend<0.001) return a;
    return mix(a,materialAtlasLinear(atlas,uv,level+1),blend);
}
vec4 sampleMaterialFiltered(sampler2D atlas,vec2 uv,vec2 dx,vec2 dy,bool sharp) {
    vec2 size=vec2(textureSize(atlas,0));
    vec2 tile=(atlasBounds.zw-atlasBounds.xy)*size;
    // Degenerate/custom mesh UVs retain the engine sampler.
    if(any(lessThan(tile,vec2(2.0)))) return textureGrad(atlas,uv,dx,dy);
    vec2 x=dx*size,y=dy*size;
    // Principal axes of the pixel footprint, robust at head-on angles.
    float a=dot(x,x),b=dot(x,y),c=dot(y,y);
    // Conservative cheap resolved-footprint test: no eigenvectors or mip mixing.
    if(a+c<=1.0) {
        if(!sharp) return materialAtlasLinear(atlas,uv,0);
        ivec2 lo=ivec2(ceil(atlasBounds.xy*size-0.001));
        ivec2 hi=max(lo,ivec2(floor(atlasBounds.zw*size+0.001))-1);
        return texelFetch(atlas,clamp(ivec2(floor(uv*size)),lo,hi),0);
    }
    float disc=sqrt(max((a-c)*(a-c)+4.0*b*b,0.0));
    float major=sqrt(max(0.5*(a+c+disc),0.000001));
    float minor=sqrt(max(0.5*(a+c-disc),0.000001));
    if(major<=1.0) {
        if(!sharp) return materialAtlasLinear(atlas,uv,0);
        ivec2 lo=ivec2(ceil(atlasBounds.xy*size-0.001));
        ivec2 hi=max(lo,ivec2(floor(atlasBounds.zw*size+0.001))-1);
        return texelFetch(atlas,clamp(ivec2(floor(uv*size)),lo,hi),0);
    }
    vec2 axis=abs(b)>0.00001?normalize(vec2(b,0.5*(c-a+disc))):(a>=c?vec2(1.0,0.0):vec2(0.0,1.0));
    vec2 span=dx*axis.x+dy*axis.y;
    // PBR channels use at most two wider taps; reserve the full anisotropic
    // budget for color, keeping the stability fix affordable on distant terrain.
    int budget=sharp?MATERIAL_FILTER:min(MATERIAL_FILTER,2);
    float width=max(1.0,max(minor,major/float(budget)));
    int taps=int(clamp(ceil(major/width),1.0,float(budget)));
    // This instance has four engine mip levels; never reach atlas-wide mips.
    float maxLod=max(0.0,min(4.0,floor(log2(max(min(tile.x,tile.y),1.0)))-1.0));
    float lod=clamp(log2(width),0.0,maxLod);
    vec4 result=vec4(0.0);
    for(int i=0;i<MATERIAL_FILTER;i++) {
        if(i>=taps) break;
        vec2 tap=uv+span*((float(i)+0.5)/float(taps)-0.5);
        result+=materialAtlasLod(atlas,tap,lod);
    }
    result/=float(taps);
    // Retain resolved Minecraft pixels, but cross into filtering continuously.
    if(sharp && major<1.5) {
        ivec2 lo=ivec2(ceil(atlasBounds.xy*size-0.001));
        ivec2 hi=max(lo,ivec2(floor(atlasBounds.zw*size+0.001))-1);
        vec4 nearest=texelFetch(atlas,clamp(ivec2(floor(uv*size)),lo,hi),0);
        result=mix(nearest,result,smoothstep(1.0,1.5,major));
    }
    return result;
}
vec4 sampleMaterial(sampler2D atlas,vec2 uv,vec2 dx,vec2 dy) {
    return sampleMaterialFiltered(atlas,uv,dx,dy,true);
}
vec4 sampleMaterialData(sampler2D atlas,vec2 uv,vec2 dx,vec2 dy) {
    return sampleMaterialFiltered(atlas,uv,dx,dy,false);
}
#else
vec4 sampleMaterial(sampler2D atlas,vec2 uv,vec2 dx,vec2 dy) {
    return textureGrad(atlas,uv,dx,dy);
}
vec4 sampleMaterialData(sampler2D atlas,vec2 uv,vec2 dx,vec2 dy) {
    return textureGrad(atlas,uv,dx,dy);
}
#endif
#endif

#ifdef POM
#if defined(TERRAIN) && defined(RESOURCE_NORMALS)
#define AA_POM
flat in vec4 atlasBounds;

vec2 parallaxTileUV(vec2 localUV,vec2 lo,vec2 size,vec2 margin) {
    // Repeat inside this sprite only, never into another block's atlas tile.
    return lo+clamp(fract(localUV)*size,margin,size-margin);
}

vec2 parallaxUV(sampler2D heightMap,vec2 uv,vec2 dx,vec2 dy,
                vec4 bounds,vec3 viewTS,float distanceToCamera) {
    vec2 size=bounds.zw-bounds.xy;
    vec2 texel=1.0/vec2(textureSize(heightMap,0));
    if(any(lessThanEqual(size,texel*2.0)) || POM_DEPTH<=0.0) return uv;
    float fade=1.0-smoothstep(POM_DISTANCE*0.65,POM_DISTANCE,distanceToCamera);
    fade*=smoothstep(0.04,0.16,viewTS.z);
    // Large pixel footprints cannot resolve relief; skip the height march.
    float footprint=max(length(dx/size),length(dy/size));
    fade*=1.0-smoothstep(0.06,0.18,footprint);
    if(fade<0.001) return uv;
    if(dot(viewTS.xy,viewTS.xy)<0.000001) return uv;
    float initialDepth=1.0-textureGrad(heightMap,uv,dx,dy).a;
    if(initialDepth<0.001) return uv;
    vec2 localUV=(uv-bounds.xy)/size;
    // Keep the bilinear/mip footprint inside the sprite at the chosen LOD.
    vec2 margin=min(size*0.49,max(texel*0.5,max(abs(dx),abs(dy))));
    vec2 ray=viewTS.xy/max(viewTS.z,0.16)*(POM_DEPTH*fade);
    int steps=int(mix(float(POM_STEPS)*0.5,float(POM_STEPS),1.0-clamp(viewTS.z,0.0,1.0)));
    steps=max(steps,4);
    float layer=0.0,previous=0.0;
    float surface=initialDepth;
    for(int i=0;i<POM_STEPS;i++) {
        if(i>=steps || layer>=surface) break;
        previous=layer;
        layer+=1.0/float(steps);
        vec2 tap=parallaxTileUV(localUV-ray*layer,bounds.xy,size,margin);
        surface=1.0-textureGrad(heightMap,tap,dx,dy).a;
    }
    // Refine the first crossing without increasing the full ray budget.
    for(int i=0;i<3;i++) {
        float mid=(previous+layer)*0.5;
        vec2 tap=parallaxTileUV(localUV-ray*mid,bounds.xy,size,margin);
        float depth=1.0-textureGrad(heightMap,tap,dx,dy).a;
        if(mid>=depth) layer=mid; else previous=mid;
    }
    return parallaxTileUV(localUV-ray*((previous+layer)*0.5),bounds.xy,size,margin);
}
#endif
#endif

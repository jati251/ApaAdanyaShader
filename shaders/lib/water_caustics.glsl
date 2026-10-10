#ifndef AA_WATER_CAUSTICS
#define AA_WATER_CAUSTICS

#if defined(WATER_CAUSTICS) && defined(IS_IRIS) && !defined(NETHER) && !defined(END)
uniform sampler2D aaWaterCaustics;

float waterCausticTexel(vec2 uv) {
    // Mirrored continuation is continuous even if generated opposite edges
    // differ slightly. The asset sampler clamps and uses hardware bilinear filtering.
    vec2 mirrored=1.0-abs(fract(uv*0.5)*2.0-1.0);
    return texture(aaWaterCaustics,mirrored).r;
}

float waterCausticLayer(vec2 uv,float radius) {
    // Custom PNGs have no guaranteed mip chain. Integrate a footprint here;
    // unresolved filaments fade out before they become isolated pixel sparks.
    float value=waterCausticTexel(uv+vec2(-radius,-radius));
    value+=waterCausticTexel(uv+vec2(radius,-radius));
    value+=waterCausticTexel(uv+vec2(-radius,radius));
    value+=waterCausticTexel(uv+vec2(radius,radius));
    return value*0.25;
}
#endif

float waterCaustic(vec2 p,float time,float footprint) {
    #if defined(WATER_CAUSTICS) && defined(IS_IRIS) && !defined(NETHER) && !defined(END)
    float resolved=1.0-smoothstep(0.10,0.75,footprint);
    if(resolved<=0.0) return 0.0;
    // The source covers 24 world blocks, rather than repeating a loop per block.
    vec2 uv=p/24.0;
    float radius=max(footprint/(3.6*24.0)*0.35,0.5/float(textureSize(aaWaterCaustics,0).x));
    const mat2 turn=mat2(0.80,-0.60,0.60,0.80);
    float a=waterCausticLayer(uv+time*vec2(0.009,-0.006),radius);
    float b=waterCausticLayer(turn*uv*1.31+vec2(0.37,0.61)
        +time*vec2(-0.006,0.008),radius*1.31);
    // Two independently moving focus fields merge/dissolve without creating
    // hard contour thresholds or constant-width ribbons.
    float intensity=(a*a+b*b)*0.5;
    return intensity*2.6*resolved;
    #else
    return 0.0;
    #endif
}

float waterCaustic(vec2 p,float time) { return waterCaustic(p,time,0.0); }
#endif

#ifndef AA_WATER_REFLECTION
#define AA_WATER_REFLECTION

float waterReflectionSpread(vec3 ray,float roughness) {
    float pixelAngle=max(length(dFdx(ray)),length(dFdy(ray)));
    return clamp(max(roughness*roughness,0.75*pixelAngle),0.008,0.18);
}

vec3 waterReflectionRay(vec3 ray,float spread,int tap) {
    // Project fixed world axes into the ray's tangent plane. No basis rotation,
    // pole or reference-axis switch can reset the sample pattern as the eye moves.
    const vec3 offsets[7]=vec3[7](vec3(0),vec3(-1,0,0),vec3(1,0,0),
        vec3(0,-1,0),vec3(0,1,0),vec3(0,0,-1),vec3(0,0,1));
    vec3 offset=offsets[tap]-ray*dot(ray,offsets[tap]);
    return normalize(ray+offset*spread);
}

float waterReflectionTapWeight(int tap) { return tap==0?0.4:0.1; }

vec3 waterEnvironmentReflection(vec3 ray,float spread) {
    vec3 result=vec3(0);
    for(int tap=0;tap<7;tap++) {
        vec3 direction=waterReflectionRay(ray,spread,tap);
        result+=environmentRadiance(direction)*waterReflectionTapWeight(tap);
    }
    return result;
}

// Four fixed world-space tetrahedral taps preserve zero mean and the seven-tap
// cone's second moment. No camera-dependent tangent-axis switch or sharp one-tap mirror.
vec3 waterLODEnvironmentReflection(vec3 ray,float spread) {
    const vec3 offsets[4]=vec3[4](vec3(1,1,1),vec3(1,-1,-1),vec3(-1,1,-1),vec3(-1,-1,1));
    vec3 result=vec3(0);
    for(int tap=0;tap<4;tap++) {
        vec3 offset=offsets[tap]*0.4472136;
        offset-=ray*dot(ray,offset);
        result+=environmentRadiance(normalize(ray+offset*spread));
    }
    return result*0.25;
}

float waterFacetVisibility(float normalView,float roughness,bool underwater) {
    if(underwater) return 1.0;
    // A wave facet turned away from the eye must not become a second mirror
    // when N.V crosses zero. The rough lobe makes this transition continuous.
    float width=max(0.025,roughness*roughness*2.0);
    return smoothstep(0.0,width,normalView);
}
#endif

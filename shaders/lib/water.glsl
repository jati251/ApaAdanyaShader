#ifndef AA_WATER
#define AA_WATER

// Analytic height gradients; wavelengths above the pixel footprint are integrated out.
vec2 waterSlope(vec2 p, vec2 dx, vec2 dy, out float crest) {
    const vec2 dirs[7] = vec2[7](vec2(0.92,0.39),vec2(0.70,-0.71),
        vec2(-0.38,0.92),vec2(0.97,0.24),vec2(-0.77,-0.64),
        vec2(0.17,0.98),vec2(0.82,-0.57));
    const float freq[7] = float[7](0.19,0.36,0.78,1.65,3.5,7.2,14.0);
    const float amp[7] = float[7](0.36,0.18,0.075,0.032,0.012,0.0045,0.0015);
    vec2 slope=vec2(0.0);
    crest=0.0;
    float storm=1.0+rainStrength*0.65;
    for(int i=0;i<WATER_OCTAVES;i++) {
        float k=freq[i];
        float footprint=k*max(abs(dot(dx,dirs[i])),abs(dot(dy,dirs[i])));
        float band=1.0-smoothstep(0.7,2.8,footprint);
        float phase=dot(p,dirs[i])*k-sqrt(9.81*k)*frameTimeCounter;
        float peak=exp(sin(phase)-1.0);
        slope+=dirs[i]*(cos(phase)*peak*k*amp[i]*band);
        if(i<2) crest+=peak*0.5;
    }
    return slope*(WATER_WAVES*storm);
}

float waterFresnel(float nv, bool underwater) {
    float cosine=clamp(abs(nv),0.0,1.0);
    // Snell's law gives a critical angle of ~48.6 degrees when exiting water.
    if(underwater) {
        float transmittedSin2=1.333*1.333*(1.0-cosine*cosine);
        if(transmittedSin2>=1.0) return 1.0;
        cosine=sqrt(1.0-transmittedSin2);
    }
    return 0.0204+0.9796*pow(1.0-cosine,5.0);
}

float waterWhitecap(float crest,float thickness) {
    return smoothstep(0.78,0.96,crest)*WATER_WAVES*
        smoothstep(1.0,3.0,thickness)*mix(0.12,0.5,rainStrength);
}
#endif

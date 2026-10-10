#ifndef AA_CLOUD_NOISE
#define AA_CLOUD_NOISE
#if defined(IS_IRIS) && !defined(AA_PROCEDURAL_CLOUDS)
uniform sampler3D aaCloudNoise;
#endif
float cloudNoise3D(vec3 p) {
    #if defined(IS_IRIS) && !defined(AA_PROCEDURAL_CLOUDS)
    // Store lattice values, not already-smoothed noise. Hardware trilinear
    // filtering then reproduces the original cubic interpolation in one lookup.
    vec3 f=fract(p);
    vec3 coordinate=(floor(p)+f*f*(3.0-2.0*f)+0.5)*(1.0/64.0);
    return textureLod(aaCloudNoise,coordinate,0.0).r;
    #else
    return noise3D(p);
    #endif
}
#endif

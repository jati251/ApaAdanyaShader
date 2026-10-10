#ifndef AA_FIRE
#define AA_FIRE
// Linear HDR radiance: retain the animated texture's contrast before tonemapping.
vec3 lavaRadiance(vec3 tex) {
    float heat=sat(dot(tex,vec3(0.45,0.50,0.05)));
    vec3 crust=vec3(0.85,0.025,0.002);
    vec3 molten=vec3(2.7,0.38,0.012);
    vec3 hot=vec3(4.0,1.25,0.065);
    vec3 radiance=mix(crust,molten,smoothstep(0.20,0.65,heat));
    return mix(radiance,hot,smoothstep(0.65,0.95,heat));
}
vec3 flameRadiance(vec3 tex,vec3 world,bool soul) {
    float heat=sat(dot(tex,soul?vec3(0.10,0.45,0.45):vec3(0.35,0.60,0.05)));
    float turbulence=noise3D(world*vec3(5.0,3.0,5.0)-vec3(0.0,frameTimeCounter*3.5,0.0));
    heat=sat(heat*0.92+turbulence*0.08);
    vec3 edge=soul?vec3(0.02,0.22,0.50):vec3(0.75,0.035,0.002);
    vec3 middle=soul?vec3(0.08,1.25,2.2):vec3(2.5,0.48,0.018);
    vec3 core=soul?vec3(0.55,2.4,3.0):vec3(4.2,1.9,0.22);
    vec3 radiance=mix(edge,middle,smoothstep(0.15,0.65,heat));
    return mix(radiance,core,smoothstep(0.7,1.0,heat));
}
#endif

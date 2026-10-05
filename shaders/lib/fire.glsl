#ifndef AA_FIRE
#define AA_FIRE
vec3 flameRadiance(vec3 tex,vec3 world,bool soul) {
    float heat=sat(max(tex.r,max(tex.g,tex.b)));
    float turbulence=noise3D(world*vec3(5.0,3.0,5.0)-vec3(0.0,frameTimeCounter*3.5,0.0));
    heat=sat(heat*0.8+turbulence*0.2);
    vec3 edge=soul?vec3(0.03,0.45,0.9):vec3(0.9,0.055,0.004);
    vec3 middle=soul?vec3(0.12,2.6,4.5):vec3(3.8,0.9,0.055);
    vec3 core=soul?vec3(2.0,5.5,6.5):vec3(6.5,4.0,1.4);
    vec3 radiance=mix(edge,middle,smoothstep(0.15,0.65,heat));
    return mix(radiance,core,smoothstep(0.7,1.0,heat));
}
#endif

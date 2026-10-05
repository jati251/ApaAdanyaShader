#ifndef AA_MATERIAL
#define AA_MATERIAL
// LabPBR 1.3: F0 is linear, 230..237 select conductors, 255 uses albedo.
// Optical constants: https://shaderlabs.org/wiki/LabPBR_Material_Standard
vec3 conductorF0(int id,vec3 tint) {
    const vec3 eta[8]=vec3[8](
        vec3(2.9114,2.9497,2.5845),vec3(0.18299,0.42108,1.3734),
        vec3(1.3456,0.96521,0.61722),vec3(3.1071,3.1812,2.3230),
        vec3(0.27105,0.67693,1.3164),vec3(1.9100,1.8300,1.4400),
        vec3(2.3757,2.0847,1.8453),vec3(0.15943,0.14512,0.13547));
    const vec3 k[8]=vec3[8](
        vec3(3.0893,2.9318,2.7670),vec3(3.4242,2.3459,1.7704),
        vec3(7.4746,6.3995,5.3031),vec3(3.3314,3.3291,3.1350),
        vec3(3.6092,2.6248,2.2921),vec3(3.5100,3.4000,3.1800),
        vec3(4.2655,3.7153,3.1365),vec3(3.9291,3.1900,2.3808));
    if(id<230 || id>237) return tint;
    vec3 n=eta[id-230],kk=k[id-230]*k[id-230];
    return ((n-1.0)*(n-1.0)+kk)/((n+1.0)*(n+1.0)+kk)*tint;
}
void decodeLabPBR(vec4 spec,vec3 albedo,inout float roughness,inout vec3 f0,
                  inout float metal,inout float emission,inout float foliage,inout float porosity) {
    // Iris' empty specular texture is black with opaque alpha; retain vanilla defaults.
    if(!any(greaterThan(spec.rgb,vec3(0.0))) && !(spec.a>0.0 && spec.a<0.999)) return;
    roughness=max(1.0-spec.r,0.045); // perceptual; GGX squares exactly once
    int id=int(floor(spec.g*255.0+0.5));
    metal=id>=230?1.0:0.0;
    f0=metal>0.5?conductorF0(id,albedo):vec3(spec.g);
    emission=max(emission,spec.a<0.999?spec.a*(255.0/254.0):0.0);
    foliage=max(foliage,sat((spec.b*255.0-65.0)/190.0));
    porosity=spec.b<=64.5/255.0?sat(spec.b*255.0/64.0):0.0;
}
vec3 diffuseResponse(vec3 albedo,vec3 f0,float metal) {
    return albedo*(1.0-metal)*(1.0-f0);
}
#endif

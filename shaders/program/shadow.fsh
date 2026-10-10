#include "/lib/common.glsl"
// Bound caster submission to the selected shadow distance.
const float shadowDistanceRenderMul = 1.0;
#include "/lib/fire.glsl"
uniform sampler2D gtexture;
in vec2 texcoord;
in vec4 glcolor;
flat in float materialId;
#ifdef AA_LIGHT_SPACE
in vec3 bounceNormal;
/* RENDERTARGETS: 0,1 */
layout(location=1) out vec4 geometry;
/*
const int shadowcolor0Format=RGBA16F;
const int shadowcolor1Format=RGBA8;
*/
const vec4 shadowcolor0ClearColor=vec4(0.0,0.0,0.0,0.0);
const vec4 shadowcolor1ClearColor=vec4(0.5,0.5,1.0,0.0);
#else
/* RENDERTARGETS: 0 */
#endif
layout(location=0) out vec4 color;
void main(){
    #ifdef SHADOWS
    if(materialId>1002.5 && materialId<1003.5) discard;
    #ifdef SHADOW_ALPHA_TEST
    if((materialId>1000.5 && materialId<1002.5) || abs(materialId-1011.0)<0.5){
        if(texture(gtexture,texcoord).a*glcolor.a < 0.1) discard;
    }
    #endif
    color=vec4(1.0);
    #ifdef AA_LIGHT_SPACE
    vec3 n=normalize(bounceNormal);
    vec3 albedo=srgbToLinear(texture(gtexture,texcoord).rgb*glcolor.rgb);
    float nl=sat(dot(n,worldDirection(shadowLightPosition)));
    // Outgoing diffuse radiance from the first surface visible to the sun.
    // Block-ID emission is a fallback; the shadow atlas has no LabPBR lightmap.
    float emission=(materialId>1003.5 && materialId<1004.5)?2.0:0.0;
    vec3 directRadiance=albedo*lightColor()*nl/PI;
    vec3 emittedRadiance=albedo*emission;
    const vec3 luma=vec3(0.2126,0.7152,0.0722);
    float directFraction=dot(directRadiance,luma)/max(dot(directRadiance+emittedRadiance,luma),1e-6);
    directFraction=clamp(directFraction,0.0,1.0);
    color=vec4(directRadiance+emittedRadiance,1.0);
    if(abs(materialId-1008.0)<0.5) {
        color.rgb=lavaRadiance(texture(gtexture,texcoord).rgb);
        directFraction=0.0;
    }
    if(abs(materialId-1006.0)<0.5 || abs(materialId-1007.0)<0.5
        || abs(materialId-1009.0)<0.5 || abs(materialId-1010.0)<0.5
        || abs(materialId-1012.0)<0.5 || abs(materialId-1013.0)<0.5) {
        color.rgb=flameRadiance(texture(gtexture,texcoord).rgb,vec3(0.0),
            abs(materialId-1007.0)<0.5 || abs(materialId-1010.0)<0.5 || abs(materialId-1013.0)<0.5);
        directFraction=0.0;
    }
    // Preserve opaque color alpha/depth ownership. Geometry alpha remains above
    // its validity threshold and packs the directly lit share into [0.6,1].
    geometry=vec4(n*0.5+0.5,0.60+0.40*directFraction);
    #endif
#else
    discard;
    #endif
}

#include "/lib/common.glsl"
#ifdef RESOURCE_NORMALS
#define AA_RESOURCE_NORMALS
#endif
#include "/lib/lighting.glsl"
uniform sampler2D gtexture;
uniform sampler2D normals;
uniform float alphaTestRef;
in vec2 texcoord,lmcoord;
in vec4 glcolor;
in vec3 viewNormal,viewPos,worldPos;
in vec4 tangent;
flat in float materialId;
/* RENDERTARGETS: 0,1,2 */
layout(location=0) out vec4 color;
layout(location=1) out vec4 normalData;
layout(location=2) out vec4 materialData;
void main() {
    vec4 tex=texture(gtexture,texcoord)*glcolor;
    #ifdef BASIC
    tex=glcolor;
    #endif
    if(tex.a<max(alphaTestRef,0.001)) discard;
    vec3 albedo=pow(max(tex.rgb,vec3(0.0)),vec3(2.2));
    vec3 N=normalize(viewNormal);
    #if defined(RESOURCE_NORMALS) && defined(TERRAIN)
    vec3 tn=texture(normals,texcoord).xyz*2.0-1.0;
    tn.z=sqrt(max(1.0-dot(tn.xy,tn.xy),0.001));
    vec3 T=normalize(tangent.xyz-N*dot(tangent.xyz,N));
    N=normalize(mat3(T,cross(N,T)*tangent.w,N)*tn);
    #endif
    float foliage=step(1000.5,materialId)*(1.0-step(1002.5,materialId));
    float emission=step(1003.5,materialId)*(1.0-step(1004.5,materialId));
    #ifdef EMISSIVE
    emission=1.0;
    #endif
    float roughness=0.78;
    if(materialId>1004.5 && materialId<1005.5) roughness=0.18;
    #ifdef RAIN_PUDDLES
    vec3 nw=worldDirection(N);
    float wet=wetness*smoothstep(0.90,0.98,lmcoord.y)*max(nw.y,0.0);
    if(wet>0.001){
        float puddle=smoothstep(0.40,0.65,noise3D(vec3(worldPos.xz*0.23,0.0)))*wet;
        roughness=mix(roughness,0.09,puddle*0.9);
        albedo*=1.0-wet*0.25;
    }
    #endif
    color=vec4(shadeSurface(albedo,N,viewPos,lmcoord,roughness,emission,foliage,vec3(0.04)),tex.a);
    normalData=vec4(N*0.5+0.5,1.0);
    float hand=0.0;
    #ifdef HAND
    hand=1.0;
    #endif
    materialData=vec4(roughness,lmcoord.y,emission,hand);
}


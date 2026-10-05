#include "/lib/common.glsl"
#ifdef RESOURCE_NORMALS
#define AA_RESOURCE_NORMALS
#endif
#include "/lib/lighting.glsl"
#include "/lib/parallax.glsl"
uniform sampler2D gtexture;
uniform sampler2D normals;
#ifdef RESOURCE_SPECULAR
uniform sampler2D specular;
#endif
uniform float alphaTestRef;
#ifdef ENTITY
uniform vec4 entityColor;
#endif
in vec2 texcoord,lmcoord;
in vec4 glcolor;
in vec3 viewNormal,viewPos,worldPos;
in vec4 tangent;
flat in float materialId;
#ifdef RESOURCE_SPECULAR
/* RENDERTARGETS: 0,1,2,3 */
layout(location=3) out vec4 reflectanceData;
#else
/* RENDERTARGETS: 0,1,2 */
#endif
layout(location=0) out vec4 color;
layout(location=1) out vec4 normalData;
layout(location=2) out vec4 materialData;
void main() {
    vec2 materialUV=texcoord;
    vec2 uvDx=dFdx(texcoord),uvDy=dFdy(texcoord);
    vec3 N=normalize(viewNormal);
    #if defined(RESOURCE_NORMALS) && defined(TERRAIN)
    vec3 tangentVector=tangent.xyz-N*dot(tangent.xyz,N);
    bool validTangent=dot(tangentVector,tangentVector)>0.0001 && abs(tangent.w)>0.5;
    vec3 fallbackT=normalize(cross(abs(N.y)<0.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0),N));
    vec3 T=validTangent?normalize(tangentVector):fallbackT;
    mat3 tbn=mat3(T,cross(N,T)*(tangent.w<0.0?-1.0:1.0),N);
    #ifdef AA_POM
    bool plant=materialId>1000.5 && materialId<1002.5;
    if(validTangent && !plant && gl_FrontFacing) {
        vec3 viewTS=transpose(tbn)*normalize(-viewPos);
        materialUV=parallaxUV(normals,texcoord,uvDx,uvDy,atlasBounds,viewTS,length(viewPos));
    }
    #endif
    #endif
    vec4 tex=textureGrad(gtexture,materialUV,uvDx,uvDy);
    float materialAO=1.0;
    #ifdef TERRAIN
    tex.rgb*=glcolor.rgb;
    materialAO=glcolor.a;
    #else
    tex*=glcolor;
    #endif
    #ifdef BASIC
    tex=glcolor;
    #endif
    if(tex.a<max(alphaTestRef,0.001)) discard;
    vec3 albedo=pow(max(tex.rgb,vec3(0.0)),vec3(2.2));
    #ifdef ENTITY
    albedo=mix(albedo,pow(max(entityColor.rgb,vec3(0.0)),vec3(2.2)),entityColor.a);
    #endif
    #if defined(RESOURCE_NORMALS) && defined(TERRAIN)
    vec4 normalMap=textureGrad(normals,materialUV,uvDx,uvDy);
    vec3 tn=normalMap.xyz*2.0-1.0;
    tn.z=sqrt(max(1.0-dot(tn.xy,tn.xy),0.001));
    materialAO*=normalMap.b;
    N=normalize(tbn*tn);
    #endif
    float foliage=step(1000.5,materialId)*(1.0-step(1002.5,materialId));
    float emission=step(1003.5,materialId)*(1.0-step(1004.5,materialId));
    #ifdef EMISSIVE
    emission=1.0;
    #endif
    float roughness=0.78;
    vec3 f0=vec3(0.04);
    float metal=0.0;
    if(materialId>1004.5 && materialId<1005.5) roughness=0.18;
    #if defined(RESOURCE_SPECULAR) && defined(TERRAIN)
    vec4 spec=textureGrad(specular,materialUV,uvDx,uvDy);
    if(any(greaterThan(spec.rgb,vec3(0.0))) || (spec.a>0.0 && spec.a<0.999)) {
        // BRDF squares perceptual roughness internally.
        roughness=max(1.0-spec.r,0.045);
        metal=step(229.5/255.0,spec.g);
        f0=mix(vec3(spec.g),albedo,metal);
        emission=max(emission,spec.a<0.999?spec.a*(255.0/254.0):0.0);
        foliage=max(foliage,sat((spec.b*255.0-65.0)/190.0));
    }
    #endif
    #ifdef RAIN_PUDDLES
    vec3 nw=worldDirection(N);
    float wet=wetness*smoothstep(0.90,0.98,lmcoord.y)*max(nw.y,0.0);
    if(wet>0.001){
        float puddle=smoothstep(0.40,0.65,noise3D(vec3(worldPos.xz*0.23,0.0)))*wet;
        roughness=mix(roughness,0.09,puddle*0.9);
        albedo*=1.0-wet*0.25;
    }
    #endif
    vec3 shaded=shadeMaterial(albedo,N,viewPos,lmcoord,roughness,emission,foliage,f0,metal,materialAO);
    color=vec4(shaded,tex.a);
    #ifdef RESOURCE_SPECULAR
    reflectanceData=vec4(f0,metal);
    #endif
    normalData=vec4(N*0.5+0.5,1.0);
    float hand=0.0;
    #ifdef HAND
    hand=1.0;
    #endif
    materialData=vec4(roughness,lmcoord.y,emission,hand);
}

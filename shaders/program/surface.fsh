#include "/lib/common.glsl"
#ifdef RESOURCE_NORMALS
#define AA_RESOURCE_NORMALS
#endif
#include "/lib/lighting.glsl"
#include "/lib/parallax.glsl"
#include "/lib/fire.glsl"
uniform sampler2D gtexture;
uniform sampler2D normals;
#ifdef RESOURCE_SPECULAR
uniform sampler2D specular;
#endif
uniform float alphaTestRef;
#ifdef ENTITY
uniform vec4 entityColor;
uniform int entityId;
#endif
in vec2 texcoord,lmcoord;
in vec4 glcolor;
in vec3 viewNormal,viewPos,worldPos;
in vec4 tangent;
flat in float materialId;
#if defined(SSAO) || defined(SSGI) || defined(SSR) || defined(RESOURCE_SPECULAR)
#ifdef RESOURCE_SPECULAR
/* RENDERTARGETS: 0,1,2,3,15 */
layout(location=3) out vec4 reflectanceData;
layout(location=4) out vec4 responseData;
#else
/* RENDERTARGETS: 0,1,2,15 */
layout(location=3) out vec4 responseData;
#endif
layout(location=1) out vec4 normalData;
layout(location=2) out vec4 materialData;
#else
/* RENDERTARGETS: 0,2 */
layout(location=1) out vec4 materialData;
#endif
layout(location=0) out vec4 color;
void main(){
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    vec2 materialUV=texcoord;
    vec2 uvDx=dFdx(texcoord),uvDy=dFdy(texcoord);
    vec3 N=normalize(viewNormal);
    #if defined(RESOURCE_NORMALS) && defined(TERRAIN)
    vec3 tangentVector=tangent.xyz-N*dot(tangent.xyz,N);
    bool validTangent=dot(tangentVector,tangentVector)>0.0001 && abs(tangent.w)>0.5;
    vec3 T=validTangent?normalize(tangentVector):normalize(cross(abs(N.y)<0.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0),N));
    mat3 tbn=mat3(T,cross(N,T)*(tangent.w<0.0?-1.0:1.0),N);
    #ifdef AA_POM
    bool plant=(materialId>1000.5 && materialId<1002.5) || abs(materialId-1011.0)<0.5;
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
    vec3 albedo=srgbToLinear(tex.rgb);
    #ifdef ENTITY
    albedo=mix(albedo,srgbToLinear(entityColor.rgb),entityColor.a);
    #endif
    #if defined(RESOURCE_NORMALS) && defined(TERRAIN)
    vec4 normalMap=textureGrad(normals,materialUV,uvDx,uvDy);
    vec3 tn=normalMap.xyz*2.0-1.0;
    tn.z=sqrt(max(1.0-dot(tn.xy,tn.xy),0.001));
    materialAO*=normalMap.b;
    N=normalize(tbn*tn);
    #endif
    float foliage=float(materialId>1000.5 && materialId<1002.5);
    float emission=0.0;
    #ifdef EMISSIVE
    emission=1.0;
    #endif
    float roughness=0.78;
    vec3 f0=vec3(0.04);
    float metal=0.0;
    float porosity=0.5;
    if(materialId>1004.5 && materialId<1005.5) roughness=0.18;
    #if defined(RESOURCE_SPECULAR) && defined(TERRAIN)
    vec4 spec=textureGrad(specular,materialUV,uvDx,uvDy);
    if(any(greaterThan(spec.rgb,vec3(0.0))) || (spec.a>0.0 && spec.a<0.999)) {
        decodeLabPBR(spec,albedo,roughness,f0,metal,emission,foliage,porosity);
    }
    #endif
    #ifdef RAIN_PUDDLES
    vec3 nw=worldDirection(N);
    float skyExposure=smoothstep(0.85,0.98,lmcoord.y);
    float wetTop=wetness*skyExposure*max(nw.y,0.0);
    float wetWall=wetness*skyExposure*(1.0-abs(nw.y))*0.65;
    float wet=max(wetTop,wetWall);
    if(wet>0.001){
        // Porous absorption darkening: porous surfaces (stone, dirt, brick) absorb water and darken
        albedo*=1.0-wet*(0.14+porosity*0.32);
        // Vertical surfaces develop a thin glossy water film
        roughness=mix(roughness,0.22,wetWall*0.70*(1.0-porosity*0.5));
        float puddle=smoothstep(0.38,0.62,noise2D(worldPos.xz*0.23))*wetTop;
        if(puddle>0.0001){
            roughness=mix(roughness,0.08,puddle*(1.0-porosity*0.65));
            #if !defined(NETHER) && !defined(END)
            if(rainStrength > 0.04 && puddle > 0.01) {
                vec2 ripPos = worldPos.xz * 2.4;
                float rt = frameTimeCounter * 4.2;
                vec2 ripGrad = vec2(0.0);
                for(int r = 0; r < 2; r++) {
                    vec2 cell = floor(ripPos);
                    vec2 f = fract(ripPos) - 0.5;
                    float h = hash12(cell + float(r) * 19.31);
                    float age = fract(rt * 0.75 + h);
                    float dist = length(f);
                    float ring = sin(clamp(dist - age * 0.44, -0.2, 0.2) * 31.4159);
                    float fade = (1.0 - age) * smoothstep(0.0, 0.06, dist) * (1.0-smoothstep(age * 0.44, age * 0.44 + 0.08, dist));
                    ripGrad += normalize(f + 1e-4) * ring * fade;
                    ripPos = ripPos * 1.48 + vec2(7.13, 11.41);
                }
                vec3 ripNormalW = normalize(vec3(-ripGrad.x * 0.16, 1.0, -ripGrad.y * 0.16));
                N = normalize(mix(N, mat3(gbufferModelView) * ripNormalW, puddle * min(rainStrength * 1.4, 0.85)));
            }
            #endif
        }
    }
    #endif
    roughness=filteredRoughness(N,roughness);
    bool lava=abs(materialId-1008.0)<0.5;
    bool flame=materialId>1005.5 && materialId<1007.5;
    #ifdef ENTITY
    flame=flame || entityId==1101;
    #endif
    bool warmFixture=abs(materialId-1009.0)<0.5 || abs(materialId-1012.0)<0.5;
    bool soulFixture=abs(materialId-1010.0)<0.5 || abs(materialId-1013.0)<0.5;
    bool isLuminousBlock=(materialId>1003.5 && materialId<1004.5) || warmFixture || soulFixture;
    #ifdef HAND
    isLuminousBlock=isLuminousBlock || (heldBlockLightValue>0 || heldBlockLightValue2>0);
    warmFixture=warmFixture || heldItemId==1009 || heldItemId2==1009;
    soulFixture=soulFixture || heldItemId==1007 || heldItemId2==1007;
    #endif
    // Match the existing soul-over-warm priority, including mixed held items.
    bool fixtureRadiance=soulFixture?(tex.g>0.50 && tex.b>0.55)
                         :(warmFixture && tex.r>0.70 && tex.g>0.45 && tex.r>tex.b*1.3);
    float ambientFraction=0.0;
    vec3 shaded=vec3(0.0);
    // Pure radiance overrides do not need PCSS, contact traces or a BRDF.
    if(!lava && !flame && !fixtureRadiance)
        shaded=shadeMaterial(albedo,N,viewPos,lmcoord,roughness,emission,foliage,f0,metal,materialAO,ambientFraction);
    if(lava){
        shaded=lavaRadiance(tex.rgb);
        emission=1.0;
        roughness=0.85;
        ambientFraction=0.0;
    }
    if(flame){
        shaded=flameRadiance(tex.rgb,worldPos,materialId>1006.5);
        emission=1.0;
        ambientFraction=0.0;
    }
    if(isLuminousBlock && !flame && !lava){
        float maxVal=max(albedo.r,max(albedo.g,albedo.b));
        float minVal=min(albedo.r,min(albedo.g,albedo.b));
        bool isSoul=soulFixture;
        bool isRedstone=(albedo.r>0.45 && albedo.r>albedo.g*2.2);
        bool isFlamePixel=(albedo.r>0.38 && albedo.g>0.18 && albedo.r>albedo.b*1.3)
                         || (isSoul && albedo.b>0.30 && albedo.g>0.25)
                         || isRedstone
                         || (maxVal>0.70);
        if(warmFixture) isFlamePixel=tex.r>0.70 && tex.g>0.45 && tex.r>tex.b*1.3;
        if(soulFixture) isFlamePixel=tex.g>0.50 && tex.b>0.55;
        if(isFlamePixel){
            // Saturated chromatic glow: rich golden amber fire, cyan soul fire, ruby redstone (never pale white!)
            vec3 chroma=albedo/max(maxVal,0.001);
            chroma=pow(chroma,vec3(1.7));
            vec3 flameColor=isSoul?vec3(0.06,1.35,2.2):(isRedstone?vec3(2.4,0.06,0.02):vec3(2.5,0.90,0.05));
            shaded=mix(shaded,chroma*flameColor*1.65,0.95);
            if(warmFixture || soulFixture) shaded=flameRadiance(tex.rgb,worldPos,isSoul);
            emission=0.80;
            ambientFraction=0.0;
        }else{
            #ifdef HAND
            // The wooden handle and player hand: illuminated with warm firelight spill from the flame
            vec3 spillColor=isSoul?vec3(0.16,0.85,1.4):vec3(1.65,0.62,0.13);
            shaded+=diffuseResponse(albedo,f0,metal)*spillColor*0.35;
            #endif
            emission=0.0;
        }
    }
    color=vec4(shaded,tex.a);
    #if defined(SSAO) || defined(SSGI) || defined(SSR) || defined(RESOURCE_SPECULAR)
    responseData=vec4(diffuseResponse(albedo,f0,metal)*materialAO,ambientFraction);
    #ifdef RESOURCE_SPECULAR
    reflectanceData=vec4(f0,metal);
    #endif
    normalData=vec4(N*0.5+0.5,1.0);
    #endif
    float hand=0.0;
    #ifdef ENTITY
    hand=0.25;
    #endif
    #ifdef HAND
    hand=1.0;
    #endif
    materialData=vec4(roughness,lmcoord.y,emission,hand);
}

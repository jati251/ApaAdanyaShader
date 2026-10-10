#ifndef AA_LIGHTING
#define AA_LIGHTING
#include "/lib/material.glsl"
#include "/lib/cloud_shadow.glsl"
uniform sampler2D shadowtex0;
#ifdef HARDWARE_PCF
#if (defined(IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS) && SHADOW_SAMPLES >= 8)
#define AA_HARDWARE_PCF
uniform sampler2DShadow shadowtex0HW;
const bool shadowHardwareFiltering=true;
#endif
#endif
const vec2 poissonDisk8[8] = vec2[8](
    vec2(-0.7071,  0.7071),
    vec2( 0.7071, -0.7071),
    vec2(-0.7071, -0.7071),
    vec2( 0.7071,  0.7071),
    vec2( 0.0000,  1.0000),
    vec2( 0.0000, -1.0000),
    vec2( 1.0000,  0.0000),
    vec2(-1.0000,  0.0000)
);
float shadowVisibility(vec3 relativeWorld, vec3 normalWorld, float ndl, bool filtered) {
#if ((!(defined(SHADOWS)) || defined(NETHER)) || defined(END))
    return 1.0;
    #endif
    if(shadowDistance <= 0.0 || dot(relativeWorld.xz, relativeWorld.xz) > shadowDistance * shadowDistance) return 1.0;

    float texelSize = 1.0 / float(shadowMapResolution);
    float normalBias = (0.05 + 0.12 * (1.0 - clamp(ndl, 0.0, 1.0))) * (1024.0 * texelSize);
    vec3 biased = relativeWorld + normalWorld * normalBias;

    vec4 clip = shadowProjection * (shadowModelView * vec4(biased, 1.0));
    vec3 sc = distortShadow(clip.xyz / clip.w) * 0.5 + 0.5;
    if(any(lessThan(sc, vec3(0.002))) || any(greaterThan(sc, vec3(0.998)))) return 1.0;

    float bias = max(0.00035 * (1.0 - clamp(ndl, 0.0, 1.0)), 0.00010);
    float fade = smoothstep(shadowDistance * 0.8, shadowDistance, length(relativeWorld.xz));
    if(fade>=1.0) return 1.0;

    if(!filtered || SHADOW_SAMPLES <= 1) {
        return mix(step(sc.z - bias, texture(shadowtex0, sc.xy).r), 1.0, fade);
    }
#if SHADOW_SAMPLES == 2
    float r = 1.25 * texelSize;
    float s0 = step(sc.z - bias, texture(shadowtex0, sc.xy + vec2(r, r)).r);
    float s1 = step(sc.z - bias, texture(shadowtex0, sc.xy - vec2(r, r)).r);
    return mix((s0 + s1) * 0.5, 1.0, fade);
#elif SHADOW_SAMPLES <= 4
    // Bilinear comparisons: four adjacent texels give continuous, crisp edges.
    // Filtering the depth itself would invent blockers at a silhouette.
    ivec2 size=textureSize(shadowtex0,0);
    vec2 grid=sc.xy*vec2(size)-0.5;
    ivec2 base=clamp(ivec2(floor(grid)),ivec2(0),size-2);
    vec2 f=fract(grid);
    float s0=step(sc.z-bias,texelFetch(shadowtex0,base,0).r);
    float s1=step(sc.z-bias,texelFetch(shadowtex0,base+ivec2(1,0),0).r);
    float s2=step(sc.z-bias,texelFetch(shadowtex0,base+ivec2(0,1),0).r);
    float s3=step(sc.z-bias,texelFetch(shadowtex0,base+ivec2(1,1),0).r);
    return mix(mix(mix(s0,s1,f.x),mix(s2,s3,f.x),f.y),1.0,fade);
#else
    vec2 radius=vec2(1.65*texelSize);
    #ifdef CONTACT_HARDENING_SHADOWS
    // Directional sun: penumbra = blocker/receiver separation * solar half angle.
    // The orthographic z projection is compressed by 0.2 in distortShadow.
    float searchRadius=5.0*texelSize,blockers=0.0,blockerDepth=0.0;
    // Include the receiver center: thin blockers between search taps stay dark.
    float centerDepth=texture(shadowtex0,sc.xy).r;
    if(centerDepth<sc.z-bias) {blockerDepth=centerDepth;blockers=1.0;}
    for(int i=0;i<4;i++) {
        float d=texture(shadowtex0,clamp(sc.xy+poissonDisk8[i+4]*searchRadius,vec2(0.002),vec2(0.998))).r;
        if(d<sc.z-bias) {blockerDepth+=d;blockers+=1.0;}
    }
    if(blockers==0.0) return 1.0;
    float separation=max(sc.z-bias-blockerDepth/blockers,0.0)/max(abs(shadowProjection[2][2])*0.1,1e-6);
    float penumbra=separation*0.00465;
    vec3 p=clip.xyz/clip.w;
    vec3 dp=sc*2.0-1.0;
    vec2 sx=(distortShadow(p+vec3(shadowProjection[0][0]*penumbra,0.0,0.0))-dp).xy*0.5;
    vec2 sy=(distortShadow(p+vec3(0.0,shadowProjection[1][1]*penumbra,0.0))-dp).xy*0.5;
    radius=clamp(vec2(length(sx),length(sy)),vec2(0.75*texelSize),vec2(searchRadius));
    #endif
    #ifdef AA_HARDWARE_PCF
    // Hardware bilinear comparisons replace pairs of manual filter taps.
    // Correct for their added footprint; keep the PCSS blocker search intact.
    radius=sqrt(max(radius*radius-vec2(texelSize*texelSize/3.0),vec2(0.5*texelSize)*vec2(0.5*texelSize)));
    float sum=0.0;
    for(int i=0;i<4;i++)
        sum+=texture(shadowtex0HW,vec3(clamp(sc.xy+poissonDisk8[i]*radius,vec2(0.002),vec2(0.998)),sc.z-bias));
    return mix(sum*0.25,1.0,fade);
#else
    float sum = 0.0;
    int samples = min(SHADOW_SAMPLES, 8);
    for(int i = 0; i < samples; i++) {
        sum += step(sc.z - bias, texture(shadowtex0, clamp(sc.xy + poissonDisk8[i] * radius,vec2(0.002),vec2(0.998))).r);
    }
    return mix(sum / float(samples), 1.0, fade);
    #endif
    #endif
}
vec3 fresnelSchlick(float cosine,vec3 f0) {
    float f = 1.0 - sat(cosine);
    float f2 = f * f;
    return f0 + (1.0 - f0) * (f2 * f2 * f);
}
float filteredRoughness(vec3 N,float roughness) {
    #ifdef SPECULAR_AA
    vec3 dx=dFdx(N),dy=dFdy(N);
    float variance=min(0.18,0.5*(dot(dx,dx)+dot(dy,dy)));
    return sqrt(clamp(roughness*roughness+variance,0.002,1.0));
#else
    return roughness;
    #endif
}
vec3 specularBRDF(vec3 N,vec3 V,vec3 L,float roughness,vec3 f0) {
    vec3 halfVector=V+L;
    vec3 H=halfVector*inversesqrt(max(dot(halfVector,halfVector),0.000001));
    float nl=sat(dot(N,L)),nv=max(dot(N,V),0.001);
    float nh=sat(dot(N,H)),vh=sat(dot(V,H));
    float a=max(roughness*roughness,0.003),a2=a*a;
    float denom=nh*nh*(a2-1.0)+1.0;
    float D=a2/max(PI*denom*denom,0.000001);
    // Height-correlated Smith visibility, with alpha = perceptual roughness squared.
    float gv=nl*sqrt(nv*nv*(1.0-a2)+a2);
    float gl=nv*sqrt(nl*nl*(1.0-a2)+a2);
    float visibility=0.5/max(gv+gl,0.00001);
    return min(vec3(24.0),D*visibility*fresnelSchlick(vh,f0))*nl;
}
float burleyDiffuse(vec3 N,vec3 V,vec3 L,float roughness) {
    float nl=sat(dot(N,L)),nv=sat(dot(N,V));
    vec3 H=normalize(V+L+vec3(1e-6));
    float lh=sat(dot(L,H));
    float f90=0.5+2.0*roughness*lh*lh;
    float fnl=1.0-nl; float fnl2=fnl*fnl; float pnl=fnl2*fnl2*fnl;
    float fnv=1.0-nv; float fnv2=fnv*fnv; float pnv=fnv2*fnv2*fnv;
    return (1.0+(f90-1.0)*pnl)*(1.0+(f90-1.0)*pnv);
}
vec3 shadeMaterial(vec3 albedo,vec3 N,vec3 vp,vec2 lm,float roughness,float emission,float foliage,vec3 f0,float metal,float materialAO,out float ambientFraction) {
    vec3 nw=worldDirection(N), rel=(gbufferModelViewInverse*vec4(vp,1.0)).xyz;
    vec3 L=normalize(shadowLightPosition), V=normalize(-vp);
    float nl=max(dot(N,L),0.0);
    float vis=0.0;
#if (!(defined(NETHER)) && !(defined(END)))
    if((nl>0.0001 || foliage>0.5) && lm.y>0.05) {
        vis=shadowVisibility(rel,nw,nl,true)*smoothstep(0.05,0.8,lm.y);
    }
    #endif
    // Hemispherical irradiance: blue skylight above, subdued ground bounce below.
    // This preserves face orientation without tinting downward surfaces sky blue.
    vec3 skyAmbient=mix(vec3(0.012,0.018,0.030)*NIGHT_BRIGHTNESS,vec3(0.16,0.22,0.31),daylight());
    vec3 groundAmbient=mix(vec3(0.004,0.006,0.009)*NIGHT_BRIGHTNESS,vec3(0.065,0.068,0.073),daylight());
    float cloudVis=1.0;
#if (!(defined(NETHER)) && !(defined(END)))
    #ifdef ATMOSPHERIC_LIGHTING
    // Warm low sunlight with cool sky fill; rain removes the chromatic split.
    float twilight=exp(-abs(sunDirection().y)*7.0)*daylight()*(1.0-rainStrength);
    skyAmbient=mix(skyAmbient,vec3(0.105,0.125,0.205),twilight*0.55);
    groundAmbient=mix(groundAmbient,vec3(0.095,0.063,0.040),twilight*0.45);
    skyAmbient=mix(skyAmbient,vec3(dot(skyAmbient,vec3(0.2126,0.7152,0.0722)))*0.85,rainStrength*0.65);
    #if CLOUDS == 1 && !defined(SSGI)
    // Fast-cloud profiles have no sampled bounce light; lift only their daylight fill.
    // Keep directional shadows, night lighting and the expensive GI path unchanged.
    float daylightFill=daylight();
    skyAmbient*=mix(1.0,1.12,daylightFill);
    groundAmbient*=mix(1.0,1.25,daylightFill);
    #endif
    #endif
    #ifdef ATMOSPHERIC_LIGHTING
    if(lm.y>0.08) cloudVis=cloudShadow(rel+cameraPosition);
    // Diffuse skylight remains under a cloud; direct sun is attenuated separately.
    // Apply sky occlusion to shaded/back-facing outdoor surfaces as well.
    skyAmbient*=mix(0.72,1.0,cloudVis);
    groundAmbient*=mix(0.86,1.0,cloudVis);
#else
    if(vis>0.0001) cloudVis=cloudShadow(rel+cameraPosition);
    #endif
    #endif
    vec3 ambient=mix(groundAmbient,skyAmbient,sat(nw.y*0.5+0.5))*pow(lm.y,1.6);
    #ifdef NETHER
    ambient=pow(fogColor,vec3(2.2))*0.45+vec3(0.045,0.013,0.008);
#elif defined(END)
    ambient=vec3(0.06,0.035,0.09);
    #endif
    ambient+=stormFlash()*(lm.y*lm.y*lm.y)*(0.35+0.65*max(nw.y,0.0));
    vec3 torch=vec3(1.65,0.62,0.13)*(lm.x*lm.x*lm.x)*TORCH_BRIGHTNESS;
#if (!(defined(HAND)) && !(defined(AA_DH_TERRAIN)))
    int maxHeldLight=max(heldBlockLightValue,heldBlockLightValue2);
    if(maxHeldLight>0){
        float heldStrength=float(maxHeldLight)/15.0;
        vec3 lightOffset=vp-vec3(0.25,-0.35,0.40);
        float distToHand=length(lightOffset);
        if(distToHand<15.0){
            float atten=sat(1.0-distToHand/15.0);
            float atten2=atten*atten;
            float handNdl=sat(dot(N,-normalize(lightOffset)));
            bool isSoul=(heldItemId==1007 || heldItemId2==1007);
            vec3 handColor=isSoul?vec3(0.16,0.85,1.4):vec3(1.65,0.62,0.13);
            torch+=handColor*(atten2*(handNdl*0.70+0.30)*(heldStrength*heldStrength)*1.5*TORCH_BRIGHTNESS);
        }
    }
    #endif
    vec3 direct=vec3(0.0);
#if (!(defined(NETHER)) && !(defined(END)))
    if(vis>0.0001) direct=lightColor()*vis*cloudVis;
    #endif
    float s=sat(dot(-V,L)); float s2=s*s;
    // Organic leaf forward scattering: wrapped light through thin leaves + forward transmission lobe
    float leafTransmission=sat(dot(-N,L)*0.45+0.55)*(s2*s2*s);
    float subsurface=foliage*(leafTransmission*0.70+sat(dot(-N,L))*0.30)*0.65;
    vec3 specular=vec3(0.0);
    #ifdef AA_DH_TERRAIN
    float lodDistance2=dot(vp,vp);
    float specularWeight=1.0-smoothstep(4096.0,16384.0,lodDistance2);
    if(vis>0.001 && nl>0.0001 && specularWeight>0.0)
        specular=specularBRDF(N,V,L,roughness,f0)*direct*specularWeight;
    float diffuseFactor=1.0;
    if(lodDistance2<16384.0)
        diffuseFactor=mix(burleyDiffuse(N,V,L,roughness),1.0,smoothstep(9216.0,16384.0,lodDistance2));
#else
    if(vis>0.001 && nl>0.0001) specular=specularBRDF(N,V,L,roughness,f0)*direct;
    float diffuseFactor=burleyDiffuse(N,V,L,roughness);
    #endif
    vec3 diffuse=diffuseResponse(albedo,f0,metal);
    vec3 ambientTerm=diffuse*(ambient+torch+vec3(0.008)*CAVE_BRIGHTNESS)*materialAO;
#ifndef SSR
    ambientTerm+=f0*metal*(ambient+torch)*materialAO*0.35;
    #endif
    vec3 emitChroma=albedo/max(max(albedo.r,max(albedo.g,albedo.b)),0.001);
    vec3 saturatedEmit=mix(albedo,emitChroma*albedo,0.35);
    vec3 result=ambientTerm+diffuse*(nl*diffuseFactor+subsurface)*direct*0.60+specular+saturatedEmit*emission*5.0;
    // Screen AO may attenuate ambient light only, never direct sun or emission.
    const vec3 luminance=vec3(0.2126,0.7152,0.0722);
    ambientFraction=sat(dot(ambientTerm,luminance)/max(dot(result,luminance),1e-5));
    return result;
}
vec3 shadeMaterial(vec3 albedo,vec3 N,vec3 vp,vec2 lm,float roughness,float emission,float foliage,vec3 f0,float metal,float materialAO) {
    float ambientFraction;
    return shadeMaterial(albedo,N,vp,lm,roughness,emission,foliage,f0,metal,materialAO,ambientFraction);
}
vec3 shadeSurface(vec3 albedo,vec3 N,vec3 vp,vec2 lm,float roughness,float emission,float foliage,vec3 f0) {
    return shadeMaterial(albedo,N,vp,lm,filteredRoughness(N,roughness),emission,foliage,f0,0.0,1.0);
}
#endif

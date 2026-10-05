#ifndef AA_LIGHTING
#define AA_LIGHTING
uniform sampler2D shadowtex0,colortex8;
float cloudShadow(vec3 world){
    #ifdef CLOUD_SHADOWS
    #if CLOUDS == 2
    #if !defined(NETHER) && !defined(END)
    vec3 ld=worldDirection(shadowLightPosition);
    vec2 ground=world.xz-ld.xz*(world.y-64.0)/max(ld.y,0.04);
    vec2 origin=floor(cameraPosition.xz/128.0)*128.0;
    vec2 uv=(ground-origin)/2048.0+0.5;
    float fade=smoothstep(0.44,0.50,max(abs(uv.x-0.5),abs(uv.y-0.5)));
    float value=texture(colortex8,clamp(uv,vec2(0.002),vec2(0.998))).r;
    return mix(value,1.0,fade);
    #endif
    #endif
    #endif
    return 1.0;
}
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
    #if !defined(SHADOWS) || defined(NETHER) || defined(END)
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

    if(!filtered || SHADOW_SAMPLES <= 1) {
        return mix(step(sc.z - bias, texture(shadowtex0, sc.xy).r), 1.0, fade);
    }
    #if SHADOW_SAMPLES == 2
    float r = 1.25 * texelSize;
    float s0 = step(sc.z - bias, texture(shadowtex0, sc.xy + vec2(r, r)).r);
    float s1 = step(sc.z - bias, texture(shadowtex0, sc.xy - vec2(r, r)).r);
    return mix((s0 + s1) * 0.5, 1.0, fade);
    #elif SHADOW_SAMPLES <= 4
    float r = 1.35 * texelSize;
    float s0 = step(sc.z - bias, texture(shadowtex0, sc.xy + vec2(-r, -r)).r);
    float s1 = step(sc.z - bias, texture(shadowtex0, sc.xy + vec2( r, -r)).r);
    float s2 = step(sc.z - bias, texture(shadowtex0, sc.xy + vec2(-r,  r)).r);
    float s3 = step(sc.z - bias, texture(shadowtex0, sc.xy + vec2( r,  r)).r);
    return mix((s0 + s1 + s2 + s3) * 0.25, 1.0, fade);
    #else
    float r = 1.65 * texelSize;
    float sum = 0.0;
    int samples = min(SHADOW_SAMPLES, 8);
    for(int i = 0; i < samples; i++) {
        sum += step(sc.z - bias, texture(shadowtex0, sc.xy + poissonDisk8[i] * r).r);
    }
    return mix(sum / float(samples), 1.0, fade);
    #endif
}
vec3 fresnelSchlick(float cosine,vec3 f0) { return f0+(1.0-f0)*pow(1.0-sat(cosine),5.0); }
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
vec3 shadeMaterial(vec3 albedo,vec3 N,vec3 vp,vec2 lm,float roughness,float emission,float foliage,vec3 f0,float metal,float materialAO) {
    vec3 nw=worldDirection(N), rel=(gbufferModelViewInverse*vec4(vp,1.0)).xyz;
    vec3 L=normalize(shadowLightPosition), V=normalize(-vp);
    float nl=max(dot(N,L),0.0);
    float vis=0.0;
    #if !defined(NETHER) && !defined(END)
    if((nl>0.0001 || foliage>0.5) && lm.y>0.05) {
        vis=shadowVisibility(rel,nw,nl,true)*smoothstep(0.05,0.8,lm.y);
    }
    #endif
    vec3 ambient=mix(vec3(0.018,0.028,0.055)*NIGHT_BRIGHTNESS,vec3(0.22,0.35,0.55),daylight());
    ambient*=pow(lm.y,1.6)*(0.40+0.60*max(nw.y*0.5+0.5,0.0));
    #ifdef NETHER
    ambient=pow(fogColor,vec3(2.2))*0.45+vec3(0.045,0.013,0.008);
    #elif defined(END)
    ambient=vec3(0.06,0.035,0.09);
    #endif
    ambient+=stormFlash()*pow(lm.y,3.0)*(0.35+0.65*max(nw.y,0.0));
    vec3 torch=vec3(1.8,0.72,0.23)*pow(lm.x,3.0)*TORCH_BRIGHTNESS;
    vec3 direct=vec3(0.0);
    #if !defined(NETHER) && !defined(END)
    if(vis>0.0001) direct=lightColor()*vis*cloudShadow(rel+cameraPosition);
    #endif
    float subsurface=foliage*pow(sat(dot(-V,L)),5.0)*0.5;
    vec3 specular=vec3(0.0);
    if(vis>0.001 && nl>0.0001) specular=specularBRDF(N,V,L,roughness,f0)*direct;
    vec3 diffuse=albedo*(1.0-metal)*(vec3(1.0)-f0);
    return diffuse*((ambient+torch+vec3(0.008)*CAVE_BRIGHTNESS)*materialAO+(nl+subsurface)*direct*0.60)+f0*metal*(ambient+torch)*materialAO*0.35+specular+albedo*emission*5.0;
}
vec3 shadeSurface(vec3 albedo,vec3 N,vec3 vp,vec2 lm,float roughness,float emission,float foliage,vec3 f0) {
    return shadeMaterial(albedo,N,vp,lm,filteredRoughness(N,roughness),emission,foliage,f0,0.0,1.0);
}
#endif

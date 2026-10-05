#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/environment.glsl"
#include "/lib/trace.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif
uniform sampler2D gtexture,colortex6,depthtex1;
uniform float alphaTestRef;
in vec2 texcoord,lmcoord;
in vec4 glcolor;
in vec3 viewNormal,viewPos,worldPos;
in vec4 tangent;
flat in float materialId;
/* RENDERTARGETS: 0,2 */
layout(location=0) out vec4 color;
layout(location=1) out vec4 materialData;
const vec2 waterWaveDirections[7] = vec2[7](
    vec2( 0.7960838,  0.6051864),
    vec2(-0.9958319,  0.0912079),
    vec2( 0.6698661, -0.7424823),
    vec2(-0.0401878,  0.9991921),
    vec2(-0.6970798, -0.7169919),
    vec2( 0.9912018, -0.1323565),
    vec2(-0.6416183,  0.7670258)
);
vec3 waterNormal(){
    vec2 p=worldPos.xz; float time=frameTimeCounter;
    float dist=length(viewPos);
    // Smooth distance fade to keep distant water calm and free of shimmering aliasing
    float distFade=clamp(1.0-dist*0.0030,0.12,1.0);
    vec2 slope=vec2(0.0); float frequency=0.60, amplitude=0.038*distFade*WATER_WAVES;
    // Water wave octaves: scalable from 2 (potato) to 7 (ultra)
    for(int i=0;i<WATER_OCTAVES;i++) {
        vec2 direction=waterWaveDirections[i];
        float phase=dot(p,direction)*frequency-time*(1.1+float(i)*0.32);
        float wave=sin(phase);
        slope+=direction*(cos(phase)*amplitude*frequency);
        p+=direction*wave*0.08;
        frequency*=1.65; amplitude*=0.52;
    }
    vec3 nw=worldDirection(viewNormal);
    nw=normalize(nw+vec3(-slope.x,0.0,-slope.y));
    return normalize(mat3(gbufferModelView)*nw)*(gl_FrontFacing?1.0:-1.0);
}
void main(){
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    materialData=vec4(WATER_ROUGHNESS,lmcoord.y,0.0,0.25);
    vec4 tex=texture(gtexture,texcoord)*glcolor;
    if(tex.a<0.001) discard;
    if(abs(materialId-1003.0)>0.5){
        vec3 albedo=pow(max(tex.rgb,vec3(0.0)),vec3(2.2));
        color=vec4(shadeSurface(albedo,normalize(viewNormal),viewPos,lmcoord,0.24,0.0,0.0,vec3(0.04)),tex.a); return;
    }
    vec2 screenUV=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    vec3 N=waterNormal(),V=normalize(-viewPos),R=reflect(-V,N);
    float opaqueDepth=textureScreen(depthtex1,screenUV).r;
    vec3 behind=viewPosition(screenUV,opaqueDepth);
    #ifdef DISTANT_HORIZONS
    if(opaqueDepth>=0.999999){
        float dhD=textureScreen(dhDepthTex0,screenUV).r;
        if(dhD<1.0){
            vec4 clipDH=vec4(screenUV*2.0-1.0,dhD*2.0-1.0,1.0);
            vec4 vpDH=dhProjectionInverse*clipDH;
            behind=vpDH.xyz/vpDH.w;
        }
    }
    #endif
    float thickness=min(length(behind-viewPos),80.0);
    #ifdef WATER_REFRACTION
    vec2 refractUV=clamp(screenUV+N.xy*min(thickness,2.5)*0.003,vec2(0.001),vec2(0.999));
    float refractDepth=textureScreen(depthtex1,refractUV).r;
    vec3 refractPos=viewPosition(refractUV,refractDepth);
    if(refractPos.z>viewPos.z+0.05) refractUV=screenUV;
    else thickness=min(length(refractPos-viewPos),80.0);
    #else
    vec2 refractUV=screenUV;
    #endif
    vec3 transmitted=textureScreen(colortex6,refractUV).rgb;
    vec3 absorption=vec3(0.27,0.075,0.035)/WATER_CLARITY;
    vec3 transmittance=exp(-absorption*thickness);
    vec3 waterColor=vec3(0.02,0.14,0.24)*mix(0.12,1.0,daylight())*(0.2+lmcoord.y*0.8);
    transmitted=transmitted*transmittance+waterColor*(1.0-transmittance);
    #ifdef WATER_CAUSTICS
    // Smooth natural underwater caustics
    float caustic1=sin(worldPos.x*2.0+frameTimeCounter)*0.5+0.5;
    float caustic2=cos(worldPos.z*2.2-frameTimeCounter*0.8)*0.5+0.5;
    float caustic=pow(caustic1*caustic2,4.0);
    transmitted+=vec3(0.04,0.075,0.065)*caustic*exp(-thickness*0.35)*daylight();
    #endif
    vec3 reflected=environmentRadiance(worldDirection(R))*pow(lmcoord.y,2.0);
    #ifdef SSR
    vec2 hit;
    if(traceScreen(depthtex1,viewPos+N*0.08,R,0.22,SSR_STEPS,hit)) {
        vec3 ssrColor=textureScreen(colortex6,hit).rgb;
        if(WATER_ROUGHNESS>0.08) {
            float rOffset=WATER_ROUGHNESS*0.004;
            ssrColor=ssrColor*0.60+0.20*(textureScreen(colortex6,hit+vec2(rOffset,0.0)).rgb+textureScreen(colortex6,hit-vec2(rOffset,0.0)).rgb);
        }
        reflected=mix(reflected,ssrColor,edgeFade(hit));
    }
    #endif
    float fresnel=0.0204+0.9796*pow(1.0-sat(dot(N,V)),5.0);
    if(isEyeInWater==1) fresnel=mix(fresnel,1.0,smoothstep(0.70,0.76,1.0-dot(N,V)*dot(N,V)));
    vec3 glint=vec3(0.0);
    #if !defined(NETHER) && !defined(END)
    vec3 L=normalize(shadowLightPosition);
    float nl=dot(N,L);
    if(nl>0.001 && lmcoord.y>0.05){
        float vis=shadowVisibility(worldPos-cameraPosition,worldDirection(N),nl,true);
        if(vis>0.001){
            glint=specularBRDF(N,V,L,filteredRoughness(N,WATER_ROUGHNESS),vec3(0.0204))*lightColor()*vis*lmcoord.y*cloudShadow(worldPos);
        }
    }
    #endif
    vec3 result=mix(transmitted,reflected,fresnel)+glint;
    #ifdef WATER_FOAM
    // Smooth shoreline blending with 3D noise foam
    if(thickness > 0.01 && thickness < 0.32) {
        float shoreDepth=smoothstep(0.01,0.50,thickness);
        float foamNoise=noise3D(worldPos*3.5+frameTimeCounter*0.5)*0.5+0.5;
        float foam=(1.0-smoothstep(0.04,0.32,thickness))*foamNoise*0.16*shoreDepth;
        result=mix(result,vec3(0.65)*mix(0.15,1.0,daylight()),foam);
    }
    #endif
    color=vec4(max(result,vec3(0.0)),1.0);
}



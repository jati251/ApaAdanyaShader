#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/environment.glsl"
#include "/lib/trace.glsl"
uniform sampler2D gtexture,colortex6,depthtex1;
uniform float alphaTestRef;
in vec2 texcoord,lmcoord;
in vec4 glcolor;
in vec3 viewNormal,viewPos,worldPos;
in vec4 tangent;
flat in float materialId;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
vec3 waterNormal(){
    vec2 p=worldPos.xz; float time=frameTimeCounter;
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    vec2 slope=vec2(0.0); float frequency=0.85, amplitude=0.042;
    for(int i=0;i<8;i++) {
        float angle=0.7+float(i)*2.39996;
        vec2 direction=vec2(cos(angle),sin(angle));
        float phase=dot(p,direction)*frequency-time*sqrt(9.81*frequency)*0.6;
        float shape=exp(sin(phase)-1.0);
        float filterWeight=exp(-frequency*footprint*0.6);
        slope+=direction*(cos(phase)*shape*amplitude*frequency*filterWeight);
        p+=direction*shape*0.13;
        frequency*=1.78; amplitude*=0.53;
    }
    vec3 nw=worldDirection(viewNormal);
    nw=normalize(nw+vec3(-slope.x,0,-slope.y)*WATER_WAVES);
    return normalize(mat3(gbufferModelView)*nw)*(gl_FrontFacing?1.0:-1.0);
}
void main(){
    vec4 tex=texture(gtexture,texcoord)*glcolor;
    if(tex.a<0.001) discard;
    if(abs(materialId-1003.0)>0.5){
        vec3 albedo=pow(max(tex.rgb,vec3(0)),vec3(2.2));
        color=vec4(shadeSurface(albedo,normalize(viewNormal),viewPos,lmcoord,0.24,0.0,0.0,vec3(0.04)),tex.a); return;
    }
    vec2 screenUV=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    vec3 N=waterNormal(),V=normalize(-viewPos),R=reflect(-V,N);
    float opaqueDepth=texture(depthtex1,screenUV).r;
    vec3 behind=viewPosition(screenUV,opaqueDepth);
    float thickness=min(length(behind-viewPos),80.0);
    vec2 refractUV=clamp(screenUV+N.xy*min(thickness,3.0)*0.004,vec2(0.001),vec2(0.999));
    float refractDepth=texture(depthtex1,refractUV).r;
    vec3 refractPos=viewPosition(refractUV,refractDepth);
    if(refractPos.z>viewPos.z+0.05) refractUV=screenUV;
    else thickness=min(length(refractPos-viewPos),80.0);
    vec3 transmitted=texture(colortex6,refractUV).rgb;
    vec3 absorption=vec3(0.27,0.075,0.035)/WATER_CLARITY;
    vec3 transmittance=exp(-absorption*thickness);
    vec3 waterColor=vec3(0.008,0.070,0.090)*mix(0.12,1.0,daylight())*(0.2+lmcoord.y*0.8);
    transmitted=transmitted*transmittance+waterColor*(1.0-transmittance);
    float caustic=pow(sat(sin(worldPos.x*2.8+frameTimeCounter)*sin(worldPos.z*3.1-frameTimeCounter*1.1)),10.0);
    transmitted+=vec3(0.04,0.075,0.065)*caustic*exp(-thickness*0.4)*daylight();
    vec3 reflected=environmentRadiance(worldDirection(R))*pow(lmcoord.y,2.0);
    #ifdef SSR
    vec2 hit;
    if(traceScreen(depthtex1,viewPos+N*0.10,R,0.22,SSR_STEPS,hit)) reflected=mix(reflected,(texture(colortex6,hit).rgb*0.5+0.125*(texture(colortex6,hit+vec2(WATER_ROUGHNESS*0.006,0)).rgb+texture(colortex6,hit-vec2(WATER_ROUGHNESS*0.006,0)).rgb+texture(colortex6,hit+vec2(0,WATER_ROUGHNESS*0.006)).rgb+texture(colortex6,hit-vec2(0,WATER_ROUGHNESS*0.006)).rgb)),edgeFade(hit));
    #endif
    float fresnel=0.0204+0.9796*pow(1.0-sat(dot(N,V)),5.0);
    if(isEyeInWater==1) fresnel=mix(fresnel,1.0,smoothstep(0.70,0.76,1.0-dot(N,V)*dot(N,V)));
    vec3 L=normalize(shadowLightPosition);
    float vis=shadowVisibility(worldPos-cameraPosition,worldDirection(N),sat(dot(N,L)),true);
    vec3 glint=specularBRDF(N,V,L,WATER_ROUGHNESS,vec3(0.0204))*lightColor()*vis*lmcoord.y*cloudShadow(worldPos);
    vec3 result=mix(transmitted,reflected,fresnel)+glint;
    float foam=(1.0-smoothstep(0.04,0.24,thickness))*noise3(worldPos*5.0+frameTimeCounter*0.6)*0.22;
    result=mix(result,vec3(0.6)*mix(0.1,1.0,daylight()),foam);
    color=vec4(max(result,vec3(0)),1.0);
}




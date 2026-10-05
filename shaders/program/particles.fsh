#include "/lib/common.glsl"
#ifdef SOFT_PARTICLES
#define AA_SOFT_PARTICLES
#endif
#ifdef PARTICLE_LIGHTING
#define AA_PARTICLE_LIGHTING
#endif
#include "/lib/lighting.glsl"
uniform sampler2D gtexture;
uniform float alphaTestRef;
#if defined(TRANSLUCENT) && defined(AA_SOFT_PARTICLES)
uniform sampler2D depthtex1;
#endif
in vec2 texcoord,lmcoord;
in vec4 glcolor;
in vec3 viewPos;
#ifdef TRANSLUCENT
/* RENDERTARGETS: 0 */
#else
/* RENDERTARGETS: 0,1,2 */
layout(location=1) out vec4 normalData;
layout(location=2) out vec4 materialData;
#endif
layout(location=0) out vec4 color;
void main() {
    vec4 tex=texture(gtexture,texcoord)*glcolor;
    #ifdef TRANSLUCENT
    if(tex.a<0.004) discard;
    #else
    if(tex.a<max(alphaTestRef,0.01)) discard;
    #endif
    vec3 albedo=pow(max(tex.rgb,vec3(0.0)),vec3(2.2));
    vec3 ambient=mix(vec3(0.025,0.04,0.075)*NIGHT_BRIGHTNESS,vec3(0.28,0.36,0.48),daylight());
    ambient*=pow(lmcoord.y,1.6);
    #ifdef NETHER
    ambient=pow(fogColor,vec3(2.2))*0.45+vec3(0.045,0.013,0.008);
    #elif defined(END)
    ambient=vec3(0.06,0.035,0.09);
    #endif
    vec3 illumination=ambient+vec3(0.008)*CAVE_BRIGHTNESS;
    illumination+=vec3(1.8,0.72,0.23)*pow(lmcoord.x,3.0)*TORCH_BRIGHTNESS;
    #if !defined(NETHER) && !defined(END)
    #ifdef AA_PARTICLE_LIGHTING
    vec3 rel=(gbufferModelViewInverse*vec4(viewPos,1.0)).xyz;
    float visibility=shadowVisibility(rel,vec3(0.0),1.0,false);
    illumination+=lightColor()*visibility*cloudShadow(rel+cameraPosition)*lmcoord.y*0.45;
    #else
    illumination+=lightColor()*lmcoord.y*0.3;
    #endif
    #endif
    #ifdef UNLIT
    illumination=vec3(1.0);
    #endif
    #if defined(TRANSLUCENT) && defined(AA_SOFT_PARTICLES)
    vec2 uv=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    float opaque=texture(depthtex1,uv).r;
    if(opaque<0.999999) {
        float separation=viewPos.z-viewPosition(uv,opaque).z;
        tex.a*=smoothstep(0.0,PARTICLE_SOFTNESS,separation);
    }
    #endif
    #ifdef WEATHER
    tex.a*=WEATHER_OPACITY;
    #endif
    color=vec4(albedo*illumination,tex.a);
    #ifndef TRANSLUCENT
    normalData=vec4(normalize(-viewPos)*0.5+0.5,1.0);
    materialData=vec4(1.0,lmcoord.y,0.0,0.0);
    #endif
}

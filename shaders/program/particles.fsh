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
void main(){
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
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

    #ifndef WEATHER
    // AAA Incandescent Blackbody Radiator for fire, campfire, torches, and lava embers
    bool isFire = (albedo.r > 0.52 && albedo.r > albedo.b * 1.6 && (albedo.r + albedo.g) > 0.65);
    bool isSoulFire = (albedo.b > 0.52 && albedo.b > albedo.r * 1.4 && albedo.g > albedo.r * 1.1);
    bool isLightning = (albedo.r > 0.92 && albedo.g > 0.92 && albedo.b > 0.92 && dot(viewPos, viewPos) > 4.0);

    if(isFire){
        // Reconstruct physical temperature gradient from white-hot core (2800K) to crimson rim
        float heat = clamp(tex.r * 0.7 + tex.g * 0.3, 0.0, 1.0);
        vec3 coreCol = vec3(14.0, 10.5, 5.0);
        vec3 flameCol = vec3(6.5, 2.2, 0.25);
        vec3 emberCol = vec3(2.0, 0.30, 0.02);
        vec3 blackbody = mix(emberCol, mix(flameCol, coreCol, smoothstep(0.60, 0.95, heat)), smoothstep(0.15, 0.60, heat));
        float pulse = 1.0 + sin(frameTimeCounter * 18.0 + dot(viewPos, vec3(11.2, 7.3, 5.7))) * 0.08;
        illumination = blackbody * pulse;
    } else if(isSoulFire){
        // Soul fire: electric cyan-violet incandescent plasma
        float heat = clamp(tex.b * 0.6 + tex.g * 0.4, 0.0, 1.0);
        vec3 coreCol = vec3(4.0, 11.0, 16.0);
        vec3 flameCol = vec3(0.5, 4.5, 8.0);
        vec3 emberCol = vec3(0.1, 1.2, 3.5);
        vec3 blackbody = mix(emberCol, mix(flameCol, coreCol, smoothstep(0.55, 0.95, heat)), smoothstep(0.15, 0.55, heat));
        illumination = blackbody;
    } else if(isLightning){
        // Blinding ionized plasma lightning core (triggers rich HDR bloom)
        illumination = vec3(35.0, 42.0, 55.0);
    }
    #endif

    #if defined(TRANSLUCENT) && defined(AA_SOFT_PARTICLES)
    vec2 uv=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    float opaque=textureScreen(depthtex1,uv).r;
    if(opaque<0.999999) {
        float separation=viewPos.z-viewPosition(uv,opaque).z;
        tex.a*=smoothstep(0.0,PARTICLE_SOFTNESS,separation);
    }
    #endif
    #ifdef WEATHER
    // AAA Cinematic Rain: forward light scattering, torchlight glistening
    vec3 V = normalize(-viewPos);
    vec3 L = normalize(shadowLightPosition);
    float rainGlint = pow(sat(dot(V, -L)), 6.0) * daylight();
    float torchGlint = pow(lmcoord.x, 2.4) * 1.6;
    illumination = illumination * 1.15 + lightColor() * rainGlint * 1.2 + vec3(1.8, 0.85, 0.35) * torchGlint;
    tex.a*=WEATHER_OPACITY;
    #endif
    color=vec4(albedo*illumination,tex.a);
    #ifndef TRANSLUCENT
    normalData=vec4(normalize(-viewPos)*0.5+0.5,1.0);
    materialData=vec4(1.0,lmcoord.y,0.0,0.0);
    #endif
}

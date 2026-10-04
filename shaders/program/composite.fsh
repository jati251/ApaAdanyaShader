#include "/lib/common.glsl"
#ifdef VOLUMETRIC_LIGHT
#define AA_VOLUMETRIC_LIGHT
#endif
#include "/lib/atmosphere.glsl"
#include "/lib/lighting.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif
uniform sampler2D colortex0,colortex2,depthtex0;
in vec2 texcoord;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
void main(){
    vec3 c=texture(colortex0,texcoord).rgb;
    float depth=texture(depthtex0,texcoord).r;
    vec3 vp=viewPosition(texcoord,depth), rd=worldDirection(normalize(vp));
    float dist=depth>=0.999999?far:min(length(vp),far);
    bool isDH=false;
    #ifdef DISTANT_HORIZONS
    float dhDepth=texture(dhDepthTex0,texcoord).r;
    if(depth>=0.999999 && dhDepth<1.0){
        isDH=true;
        vec4 clipDH=vec4(texcoord*2.0-1.0,dhDepth*2.0-1.0,1.0);
        vec4 vpDH=dhProjectionInverse*clipDH;
        vp=vpDH.xyz/vpDH.w;
        rd=worldDirection(normalize(vp));
        dist=length(vp);
    }
    #endif
    bool hand=texture(colortex2,texcoord).a>0.5 && depth<0.56;
    if(isEyeInWater==1){
        vec3 trans=exp(-vec3(0.24,0.08,0.045)*dist/WATER_CLARITY);
        c=c*trans+vec3(0.008,0.085,0.12)*mix(0.15,1.0,daylight())*(1.0-trans);
    }else if(isEyeInWater==2){
        c=mix(c,vec3(2.0,0.22,0.012),1.0-exp(-dist*1.5));
    }else if(!hand){
        vec3 fog=skyRadiance(vec3(rd.x,0.035,rd.z)/length(vec3(rd.x,0.035,rd.z)));
        float density=(0.00022+rainStrength*0.0025)*FOG_DENSITY;
        float heightAttenuation=exp(-max(cameraPosition.y+rd.y*dist*0.5-64.0,0.0)*0.008);
        float amount=1.0-exp(-dist*density*heightAttenuation);
        #ifdef NETHER
        amount=1.0-exp(-dist*0.016*FOG_DENSITY);
        #elif defined(END)
        amount=1.0-exp(-dist*0.002*FOG_DENSITY);
        #endif
        if(depth<0.999999 || isDH) c=mix(c,fog,amount);
        #if defined(VOLUMETRIC_LIGHT) && !defined(NETHER) && !defined(END)
        float rayLength=min(dist,100.0), sum=0.0;
        float jitter=hash12(gl_FragCoord.xy);
        for(int i=0;i<8;i++){
            vec3 p=rd*rayLength*(float(i)+jitter)/8.0;
            sum+=shadowVisibility(p,vec3(0),1.0,false);
        }
        float phase=0.025+pow(sat(dot(rd,worldDirection(shadowLightPosition))),24.0)*0.28;
        float outdoor=smoothstep(8.0,150.0,float(eyeBrightnessSmooth.y));
        c+=lightColor()*(sum/8.0)*phase*(1.0-exp(-rayLength*0.0015*FOG_DENSITY))*outdoor;
        #endif
    }
    color=vec4(max(c,vec3(0)),1);
}



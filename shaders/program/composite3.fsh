#include "/lib/common.glsl"
uniform sampler2D colortex0,colortex5;
in vec2 texcoord;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
vec3 film(vec3 x){return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0);}
void main(){
    vec3 c=texture(colortex0,texcoord).rgb;
    #ifdef BLOOM
    vec2 px=4.0/vec2(viewWidth,viewHeight); vec3 bloom=vec3(0.0); float weight=0.0;
    for(int i=-6;i<=6;i++){float w=exp(-float(i*i)/12.0); bloom+=texture(colortex5,texcoord+vec2(0.0,float(i)*px.y)).rgb*w; weight+=w;}
    c+=bloom/weight*BLOOM_STRENGTH;
    #endif
    float exposure=EXPOSURE*mix(1.15,0.90,daylight());
    #if TONEMAP_OPERATOR == 0
    vec3 scaled=c*exposure;
    float lumaIn=dot(scaled,vec3(0.2126,0.7152,0.0722));
    float lumaOut=(lumaIn*(2.51*lumaIn+0.03))/(lumaIn*(2.43*lumaIn+0.59)+0.14);
    vec3 filmLuma=scaled*(clamp(lumaOut,0.0,1.0)/max(lumaIn,0.0001));
    vec3 filmRGB=film(scaled);
    c=pow(clamp(mix(filmRGB,filmLuma,0.60),0.0,1.0),vec3(1.0/2.2));
    #else
    c=pow(clamp(c*exposure,0.0,1.0),vec3(1.0/2.2));
    #endif
    float luminance=dot(c,vec3(0.2126,0.7152,0.0722));
    if(COLOR_SATURATION != 1.0){
        float maxC=max(c.r,max(c.g,c.b));
        float minC=min(c.r,min(c.g,c.b));
        float satAmt=maxC-minC;
        float boost=mix(COLOR_SATURATION,1.0+(COLOR_SATURATION-1.0)*0.5,satAmt);
        c=clamp(mix(vec3(luminance),c,boost),0.0,1.0);
    }
    if(COLOR_CONTRAST != 1.0){
        vec3 sCurve=c*c*(3.0-2.0*c);
        c=clamp(mix(c,sCurve,COLOR_CONTRAST-1.0),0.0,1.0);
    }
    #ifdef VIGNETTE
    vec2 vigCoord=texcoord*(1.0-texcoord.yx);
    float vig=vigCoord.x*vigCoord.y*15.0;
    c*=clamp(pow(vig,VIGNETTE_STRENGTH),0.0,1.0);
    #endif
    color=vec4(c,1.0);
}


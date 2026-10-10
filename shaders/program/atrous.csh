#include "/lib/common.glsl"
layout(local_size_x=8,local_size_y=8) in;
const vec2 workGroupsRender=vec2(0.5,0.5);
#ifdef AA_SVGF
uniform sampler2D colortex12,colortex18,colortex19,aaDenoiseA,aaDenoiseB;
#if AA_ATROUS_PASS == 1
layout(rgba16f) uniform writeonly image2D aaDenoiseImageB;
#define AA_DENOISE_OUTPUT aaDenoiseImageB
#define AA_DENOISE_INPUT aaDenoiseA
#else
layout(rgba16f) uniform writeonly image2D aaDenoiseImageA;
#define AA_DENOISE_OUTPUT aaDenoiseImageA
#if AA_ATROUS_PASS == 0
#define AA_DENOISE_INPUT colortex12
#else
#define AA_DENOISE_INPUT aaDenoiseB
#endif
#endif
#endif
void main() {
    #ifdef AA_SVGF
    ivec2 q=ivec2(gl_GlobalInvocationID.xy),size=screenTextureSize(colortex12);
    if(any(greaterThanEqual(q,size))) return;
    vec4 center=texelFetch(AA_DENOISE_INPUT,q,0),geometry=texelFetch(colortex18,q,0);
    if(center.a<0.0 || geometry.a<=0.0) {imageStore(AA_DENOISE_OUTPUT,q,center);return;}
    vec4 moments=texelFetch(colortex19,q,0);
    float sigma=max(sqrt(max(moments.z,0.0)),0.03);
    float centerLuma=dot(center.rgb,vec3(0.2126,0.7152,0.0722));
    const ivec2 offsets[5]=ivec2[5](ivec2(0),ivec2(-1,0),ivec2(1,0),ivec2(0,-1),ivec2(0,1));
    vec4 sum=vec4(0);float total=0.0;
    for(int tap=0;tap<5;tap++) {
        ivec2 p=q+offsets[tap]*(1<<AA_ATROUS_PASS);
        if(any(lessThan(p,ivec2(0))) || any(greaterThanEqual(p,size))) continue;
        vec4 sampleValue=texelFetch(AA_DENOISE_INPUT,p,0),other=texelFetch(colortex18,p,0);
        if(sampleValue.a<0.0 || other.a<=0.0) continue;
        float depthWeight=exp(-abs(other.a-geometry.a)/max(0.04,geometry.a*0.01*float(1<<AA_ATROUS_PASS)));
        float normalWeight=pow(max(dot(geometry.xyz,other.xyz),0.0),32.0);
        float luma=dot(sampleValue.rgb,vec3(0.2126,0.7152,0.0722));
        float signalWeight=exp(-abs(luma-centerLuma)/(sigma*4.0+0.02));
        float weight=(tap==0?2.0:1.0)*depthWeight*normalWeight*signalWeight;
        // AO has a separate edge test so a GI firefly does not wash out contact AO.
        weight*=exp(-abs(sampleValue.a-center.a)*8.0);
        sum+=sampleValue*weight;total+=weight;
    }
    imageStore(AA_DENOISE_OUTPUT,q,sum/max(total,1e-6));
    #endif
}

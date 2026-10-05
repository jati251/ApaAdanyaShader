uniform sampler2D colortex14;
#define FSR_RCAS_F 1
#define FSR_RCAS_DENOISE 1
#include "/lib/vendor/fsr1/fsr1_fp32.glsl"
vec4 FsrRcasLoadF(ivec2 p) { return texelFetch(colortex14,clamp(p,ivec2(0),textureSize(colortex14,0)-1),0); }
void FsrRcasInputF(inout float r,inout float g,inout float b) {}

#include "/lib/common.glsl"
uniform sampler2D colortex9,colortex10,colortex11;
uniform mat4 gbufferPreviousModelView,gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
uniform int frameCounter;
uniform float frameTime;
in vec2 texcoord;
/* RENDERTARGETS: 10,11 */
/*
const int colortex10Format = RGBA16F;
const int colortex11Format = RGBA16F;
const bool colortex10Clear = false;
const bool colortex11Clear = false;
*/
layout(location=0) out vec4 history;
layout(location=1) out vec4 metadata;
void main() {
    ivec2 size=textureSize(colortex9,0);
    ivec2 pixel=clamp(ivec2(gl_FragCoord.xy),ivec2(0),size-1);
    vec4 now=texelFetch(colortex9,pixel,0);
    history=now;
    float tag=float(frameCounter%1024+1);
    metadata=vec4(sunDirection().y,rainStrength,mod(frameTimeCounter,8.0),tag);
    if(now.a<0.0 || frameCounter<2 || frameTime<=0.0 || frameTime>0.2) return;
    if(length(cameraPosition-previousCameraPosition)>8.0) return;
    if(abs(gbufferProjection[1][1]-gbufferPreviousProjection[1][1])>0.02) return;
    vec3 rd=worldDirection(viewPosition(texcoord,1.0));
    if(abs(rd.y)<0.08) return;
    float anchor=(CLOUD_ALTITUDE+55.0-cameraPosition.y)/rd.y;
    // A single plane cannot reproject a cloud volume reliably from inside it.
    if(anchor<110.0 || anchor>4200.0) return;
    vec3 relative=rd*anchor+cameraPosition-previousCameraPosition;
    relative+=vec3(1.2,0.0,0.5)*frameTime;
    vec4 previous=gbufferPreviousProjection*gbufferPreviousModelView*vec4(relative,1.0);
    if(previous.w<=0.0) return;
    vec2 uv=previous.xy/previous.w*0.5+0.5;
    vec2 border=1.0/vec2(size);
    if(any(lessThan(uv,border)) || any(greaterThan(uv,1.0-border))) return;
    ivec2 q=clamp(ivec2(uv*vec2(size)),ivec2(0),size-1);
    vec4 meta=texelFetch(colortex11,q,0);
    float previousTag=float((frameCounter-1)%1024+1);
    if(abs(meta.a-previousTag)>0.1 || abs(meta.r-metadata.r)>0.005 || abs(meta.g-rainStrength)>0.02) return;
    // Includes the counter wrap, shader reloads and long gaps between renders.
    if(abs(metadata.b-meta.b-frameTime)>0.15) return;
    vec4 lo=now,hi=now;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec4 tap=texelFetch(colortex9,clamp(pixel+ivec2(x,y),ivec2(0),size-1),0);
        if(tap.a<0.0) continue;
        lo=min(lo,tap); hi=max(hi,tap);
    }
    // Validate each tap before interpolation; invalid sky/terrain history never mixes in.
    vec2 p=uv*vec2(size)-0.5,f=fract(p);
    ivec2 base=ivec2(floor(p));
    vec4 old=vec4(0.0);
    float total=0.0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 coord=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 tap=texelFetch(colortex10,coord,0);
        vec4 stamp=texelFetch(colortex11,coord,0);
        if(tap.a<0.0 || abs(stamp.a-previousTag)>0.1 || any(isnan(tap)) || any(isinf(tap))) continue;
        float w=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y);
        old+=tap*w; total+=w;
    }
    if(total<0.5) return;
    old/=total;
    float movement=length((uv-texcoord)*vec2(size));
    float confidence=0.85*exp(-movement*0.06)*(1.0-smoothstep(0.05,0.25,abs(old.a-now.a)));
    history=mix(now,clamp(old,lo,hi),confidence);
}

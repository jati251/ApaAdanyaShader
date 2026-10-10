#ifndef AA_ROUGH_REFLECTION
#define AA_ROUGH_REFLECTION
#if defined(AA_VOXELS) && defined(SSR)
#define AA_VNDF_REFLECTION
uniform sampler2D colortex20;
#ifndef AA_PREVIOUS_INDIRECT_UNIFORMS
#define AA_PREVIOUS_INDIRECT_UNIFORMS
uniform mat4 gbufferPreviousModelView,gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
#endif
// GGX visible-normal sampling in the stretched view hemisphere (Heitz 2018).
vec3 sampleVisibleGGX(vec3 N,vec3 V,float roughness,vec2 randomValue,out vec3 H) {
    vec3 t=normalize(cross(N,abs(N.y)<0.9?vec3(0,1,0):vec3(1,0,0))),b=cross(N,t);
    vec3 view=vec3(dot(V,t),dot(V,b),max(dot(V,N),0.001));
    float alpha=max(roughness*roughness,0.003);
    vec3 stretched=normalize(vec3(view.xy*alpha,view.z));
    float l2=dot(stretched.xy,stretched.xy);
    vec3 t1=l2>1e-6?vec3(-stretched.y,stretched.x,0)*inversesqrt(l2):vec3(1,0,0);
    vec3 t2=cross(stretched,t1);
    float radius=sqrt(randomValue.x),angle=2.0*PI*randomValue.y;
    float x=radius*cos(angle),y=radius*sin(angle),s=0.5*(1.0+stretched.z);
    y=mix(sqrt(max(0.0,1.0-x*x)),y,s);
    vec3 nh=t1*x+t2*y+stretched*sqrt(max(0.0,1.0-x*x-y*y));
    vec3 h=normalize(vec3(nh.xy*alpha,max(nh.z,0.0)));
    H=normalize(t*h.x+b*h.y+N*h.z);
    return reflect(-V,H);
}
vec3 visibleGGXWeight(vec3 N,vec3 V,vec3 R,vec3 H,float roughness,vec3 f0) {
    float nv=max(dot(N,V),0.001),nl=dot(N,R);
    if(nl<=0.0) return vec3(0);
    float a2=pow(max(roughness*roughness,0.003),2.0);
    float lambdaV=0.5*(sqrt(1.0+a2*(1.0-nv*nv)/(nv*nv))-1.0);
    float lambdaL=0.5*(sqrt(1.0+a2*(1.0-nl*nl)/(nl*nl))-1.0);
    float f=pow(1.0-sat(dot(V,H)),5.0);
    return (f0+(1.0-f0)*f)*(1.0+lambdaV)/(1.0+lambdaV+lambdaL);
}
vec3 stabilizeReflection(vec2 uv,vec3 vp,vec4 mat,vec3 current) {
    vec3 travel=cameraPosition-previousCameraPosition;
    if(mat.a>0.1 || frameCounter<2 || frameTime<=0.0 || frameTime>0.2 || dot(travel,travel)>4.0
       || abs(gbufferProjection[1][1]-gbufferPreviousProjection[1][1])>0.01) return current;
    vec4 oldView=gbufferPreviousModelView*vec4((gbufferModelViewInverse*vec4(vp,1)).xyz+travel,1);
    vec4 clip=gbufferPreviousProjection*oldView;
    if(clip.w<=0.0) return current;
    vec2 historyUV=clip.xy/clip.w*0.5+0.5;
    if(any(lessThan(historyUV,vec2(0.002))) || any(greaterThan(historyUV,vec2(0.998)))) return current;
    vec4 history=textureScreen(colortex20,historyUV);
    float sourceSign=dot(shadowLightPosition,sunPosition)>=0.0?1.0:-1.0;
    // The sign also rejects history across the sun/moon shadow-source switch.
    if(history.a*sourceSign<=0.0 || abs(abs(history.a)+oldView.z)>max(0.05,-oldView.z*0.01)
       || any(isnan(history)) || any(isinf(history))) return current;
    float luma=dot(current,vec3(0.2126,0.7152,0.0722));
    float oldLuma=dot(history.rgb,vec3(0.2126,0.7152,0.0722));
    history.rgb*=min(1.0,max(0.08,luma*4.0)/max(oldLuma,1e-5));
    float movement=length((uv-historyUV)*vec2(viewWidth,viewHeight));
    float blend=smoothstep(0.06,0.2,mat.r)*pow(0.90,clamp(frameTime*60.0,0.25,4.0))*exp(-movement*0.08);
    return mix(current,history.rgb,blend);
}
#endif
#endif

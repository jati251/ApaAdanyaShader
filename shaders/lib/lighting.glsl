#ifndef AA_LIGHTING
#define AA_LIGHTING
uniform sampler2D shadowtex0,colortex8;
float cloudShadow(vec3 world){
    #ifdef CLOUD_SHADOWS
    #ifdef VOLUMETRIC_CLOUDS
    #if !defined(NETHER) && !defined(END)
    vec3 ld=worldDirection(shadowLightPosition);
    vec2 ground=world.xz-ld.xz*(world.y-64.0)/max(ld.y,0.04);
    vec2 origin=floor(cameraPosition.xz/128.0)*128.0;
    vec2 uv=(ground-origin)/2048.0+0.5;
    float fade=smoothstep(0.44,0.50,max(abs(uv.x-0.5),abs(uv.y-0.5)));
    float value=texture(colortex8,clamp(uv,vec2(0.002),vec2(0.998))).r;
    return mix(value,1.0,fade);
    #endif
    #endif
    #endif
    return 1.0;
}
float shadowVisibility(vec3 relativeWorld, vec3 normalWorld, float ndl, bool filtered) {
    #if defined(NETHER) || defined(END)
    return 1.0;
    #endif
    if(dot(relativeWorld.xz, relativeWorld.xz) > shadowDistance * shadowDistance) return 1.0;
    vec3 biased=relativeWorld+normalWorld*(0.025+0.06*(1.0-ndl));
    vec4 clip=shadowProjection*shadowModelView*vec4(biased,1);
    vec3 sc=distortShadow(clip.xyz/clip.w)*0.5+0.5;
    if(any(lessThan(sc,vec3(0.002))) || any(greaterThan(sc,vec3(0.998)))) return 1.0;
    float bias=0.00008;
    if(!filtered) return step(sc.z-bias,texture(shadowtex0,sc.xy).r);
    float filterRadius=1.65/float(shadowMapResolution);
    float s0=step(sc.z-bias,texture(shadowtex0,sc.xy+vec2(-filterRadius,-filterRadius)).r);
    float s1=step(sc.z-bias,texture(shadowtex0,sc.xy+vec2(filterRadius,-filterRadius)).r);
    float s2=step(sc.z-bias,texture(shadowtex0,sc.xy+vec2(-filterRadius,filterRadius)).r);
    float s3=step(sc.z-bias,texture(shadowtex0,sc.xy+vec2(filterRadius,filterRadius)).r);
    float quickSum=s0+s1+s2+s3;
    if(quickSum==4.0) return 1.0;
    float fade=smoothstep(shadowDistance*0.8,shadowDistance,length(relativeWorld.xz));
    if(quickSum==0.0) return mix(0.0,1.0,fade);
    float total=quickSum; float rotation=hash12(floor(relativeWorld.xz*24.0))*6.283;
    for(int i=4;i<SHADOW_SAMPLES;i++) {
        float r=sqrt((float(i)+0.5)/float(SHADOW_SAMPLES));
        float angle=float(i)*2.39996+rotation;
        vec2 offset=vec2(cos(angle),sin(angle))*r*filterRadius;
        total+=step(sc.z-bias,texture(shadowtex0,sc.xy+offset).r);
    }
    return mix(total/float(SHADOW_SAMPLES),1.0,fade);
}
vec3 fresnelSchlick(float cosine,vec3 f0) { return f0+(1.0-f0)*pow(1.0-sat(cosine),5.0); }
vec3 specularBRDF(vec3 N,vec3 V,vec3 L,float roughness,vec3 f0) {
    vec3 H=normalize(V+L); float nl=max(dot(N,L),0.0), nv=max(dot(N,V),0.001);
    float nh=max(dot(N,H),0.0), vh=max(dot(V,H),0.0);
    float a=max(roughness*roughness,0.003), a2=a*a;
    float denom=nh*nh*(a2-1.0)+1.0;
    float D=a2/max(PI*denom*denom,0.000001);
    float k=(roughness+1.0)*(roughness+1.0)*0.125;
    float G=nv/(nv*(1.0-k)+k)*nl/(nl*(1.0-k)+k);
    return min(vec3(24.0),D*G*fresnelSchlick(vh,f0)/max(4.0*nv*nl,0.001))*nl;
}
vec3 shadeSurface(vec3 albedo,vec3 N,vec3 vp,vec2 lm,float roughness,float emission,float foliage,vec3 f0) {
    vec3 nw=worldDirection(N), rel=(gbufferModelViewInverse*vec4(vp,1)).xyz;
    vec3 L=normalize(shadowLightPosition), V=normalize(-vp);
    float nl=max(dot(N,L),0.0);
    float vis=0.0;
    if((nl>0.0001 || foliage>0.5) && lm.y>0.05) {
        vis=shadowVisibility(rel,nw,nl,true)*smoothstep(0.05,0.8,lm.y);
    }
    vec3 ambient=mix(vec3(0.018,0.028,0.055)*NIGHT_BRIGHTNESS,vec3(0.16,0.21,0.29),daylight());
    ambient*=pow(lm.y,2.0)*(0.55+0.45*max(nw.y,0.0));
    #ifdef NETHER
    ambient=pow(fogColor,vec3(2.2))*0.45+vec3(0.045,0.013,0.008);
    #elif defined(END)
    ambient=vec3(0.06,0.035,0.09);
    #endif
    vec3 torch=vec3(1.8,0.72,0.23)*pow(lm.x,3.0);
    vec3 direct=vec3(0.0);
    if(vis>0.0001) direct=lightColor()*vis*cloudShadow(rel+cameraPosition);
    #if defined(NETHER) || defined(END)
    direct=vec3(0);
    #endif
    float subsurface=foliage>0.5?pow(sat(dot(-V,L)),5.0)*0.5:0.0;
    vec3 specular=vec3(0.0);
    if(vis>0.001 && nl>0.0001) specular=specularBRDF(N,V,L,roughness,f0)*direct;
    return albedo*(ambient+torch+vec3(0.008)+(nl+subsurface)*direct*0.52)+specular+albedo*emission*5.0;
}
#endif




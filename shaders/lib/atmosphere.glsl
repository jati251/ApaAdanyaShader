#ifndef AA_ATMOSPHERE
#define AA_ATMOSPHERE
vec3 skyRadiance(vec3 rd) {
    #ifdef NETHER
    return pow(fogColor,vec3(2.2))*0.6+vec3(0.018,0.003,0.001);
    #elif defined(END)
    return mix(vec3(0.016,0.009,0.035),vec3(0.07,0.035,0.12),exp(-abs(rd.y)*5.0));
    #else
    vec3 sd=sunDirection(); float day=daylight();
    float horizon=pow(1.0-max(rd.y,0.0),5.0);
    vec3 sky=mix(vec3(0.025,0.125,0.34),vec3(0.30,0.43,0.56),horizon);
    float sunset=exp(-abs(sd.y)*10.0);
    float facing=pow(sat(dot(rd,sd)*0.5+0.5),8.0);
    sky=mix(sky,vec3(0.9,0.24,0.065),sunset*horizon*(0.22+facing*0.65));
    sky*=mix(0.25,1.0,smoothstep(-0.08,0.25,sd.y));
    sky=mix(vec3(0.0018,0.0035,0.009)+vec3(0.008,0.012,0.024)*horizon,sky,day);
    sky=mix(sky,vec3(dot(sky,vec3(0.2126,0.7152,0.0722)))*0.75,rainStrength*0.8);
    float sunDot=dot(rd,sd), moonDot=dot(rd,-sd);
    sky+=vec3(12.0,9.5,6.5)*smoothstep(0.99994,0.999975,sunDot)*day*(1.0-rainStrength);
    sky+=vec3(0.22,0.30,0.48)*smoothstep(0.99982,0.9999,moonDot)*(1.0-day);
    sky+=lightColor()*pow(sat(sunDot),512.0)*0.055;
    vec3 starCell=floor(rd*650.0);
    sky+=vec3(pow(hash13(starCell),950.0))*smoothstep(0.02,0.3,rd.y)*(1.0-day)*(1.0-rainStrength)*0.5;
    return sky;
    #endif
}
float sampleCloudDensity(vec3 p,bool detail) {
    float h=(p.y-190.0)/115.0;
    if(h<=0.0 || h>=1.0) return 0.0;
    vec3 wind=vec3(frameTimeCounter*0.9,0,frameTimeCounter*0.32);
    vec3 q=(p+wind)*0.007;
    float weather=noise3(vec3(q.x*0.32,0.3,q.z*0.32));
    float coverage=CLOUD_COVERAGE+rainStrength*0.14;
    float base=noise3(q)*0.62+noise3(q*2.03+vec3(11.2))*0.26+noise3(q*4.13)*0.12;
    float threshold=0.70-coverage*0.46+(h*h)*0.25-weather*0.09;
    // Smooth hermite density profile eliminates stair-stepping and hard boundaries
    float shape=smoothstep(threshold-0.12,threshold+0.16,base);
    // Soft organic billow erosion without high-frequency noisy sparkle
    float erosion=detail?(noise3(q*3.2)*0.70+noise3(q*6.4)*0.30):0.5;
    shape=clamp(shape-(1.0-erosion)*0.22,0.0,1.0);
    return shape*smoothstep(0.0,0.12,h)*(1.0-smoothstep(0.70,1.0,h));
}
float cloudDensity(vec3 p){return sampleCloudDensity(p,true);}
vec3 renderClouds(vec3 rd,vec3 background,vec2 pixel) {
    #ifdef VOLUMETRIC_CLOUDS
    #if !defined(NETHER) && !defined(END)
    if(abs(rd.y)<0.008) return background;
    float a=(190.0-cameraPosition.y)/rd.y, b=(305.0-cameraPosition.y)/rd.y;
    float entry=max(min(a,b),0.0), leave=min(max(a,b),7000.0);
    if(leave<=entry) return background;
    float stepLen=(leave-entry)/float(CLOUD_STEPS);
    // Interleaved spatial dither for uniform smooth ray progression
    float dither=fract(sin(dot(floor(pixel),vec2(12.9898,78.233)))*43758.5453);
    float t=entry+dither*stepLen;
    float trans=1.0; vec3 sum=vec3(0);
    vec3 ld=worldDirection(shadowLightPosition);
    float silver=pow(sat(dot(rd,ld)),16.0);
    for(int i=0;i<CLOUD_STEPS;i++) {
        vec3 p=cameraPosition+rd*t;
        float density=cloudDensity(p);
        if(density>0.001) {
            // Highly optimized 2-sample shadow raymarch (2x faster than 4-sample loop)
            float optical=sampleCloudDensity(p+ld*16.0,false)*32.0
                         +sampleCloudDensity(p+ld*54.0,false)*58.0;
            float shade=exp(-optical*0.11);
            float heightLight=sat((p.y-190.0)/115.0);
            vec3 ambient=mix(vec3(0.006,0.01,0.024),vec3(0.055,0.08,0.13),daylight())*(0.60+heightLight);
            vec3 lighting=ambient+lightColor()*(shade*(0.50+silver*0.65)+0.045*exp(-optical*0.018));
            float opacity=1.0-exp(-density*stepLen*0.052);
            sum+=trans*lighting*opacity; trans*=1.0-opacity;
        }
        t+=stepLen; if(trans<0.01) break;
    }
    float aerial=1.0-exp(-entry*0.00008);
    sum=mix(sum,background*(1.0-trans),aerial);
    return background*trans+sum;
    #endif
    #endif
    return background;
}
#endif




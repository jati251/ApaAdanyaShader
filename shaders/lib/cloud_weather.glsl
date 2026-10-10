#ifndef AA_CLOUD_WEATHER
#define AA_CLOUD_WEATHER
// Shared world-space layers for the sky, reflection cache and shadow atlas.
const float CLOUD_ALT_BASE = CLOUD_ALTITUDE;
const float CLOUD_ALT_THICK = 240.0;
const float CLOUD_EXTINCTION = 0.055;
const float CLOUD_MID_ALT = CLOUD_ALTITUDE + 310.0;
const float CLOUD_HIGH_ALT = CLOUD_ALTITUDE + 720.0;
const float CLOUD_SHADOW_SPAN = 4096.0;
const mat2 rotCloud = mat2(0.80, -0.60, 0.60, 0.80);

// Fast clouds share coverage, scale and wind with their small shadow atlas.
const float FAST_CLOUD_SCALE = 0.0036;
vec2 fastCloudCoordinates(vec2 world) {
    return (world+vec2(1.15,0.48)*frameTimeCounter)*FAST_CLOUD_SCALE;
}
float cloudFractal(vec2 p,float footprint) {
    float n=mix(noise2D(p),0.5,smoothstep(0.35,0.85,footprint));
    p=rotCloud*p*2.02; footprint*=2.02;
    n+=mix(noise2D(p),0.5,smoothstep(0.35,0.85,footprint))*0.50;
    p=rotCloud*p*2.03; footprint*=2.03;
    n+=mix(noise2D(p),0.5,smoothstep(0.35,0.85,footprint))*0.25;
    p=rotCloud*p*2.01; footprint*=2.01;
    n+=mix(noise2D(p),0.5,smoothstep(0.35,0.85,footprint))*0.125;
    return n/1.875;
}
float fastCloudDensity(vec2 world,float footprint) {
    float coverage=clamp(CLOUD_COVERAGE+rainStrength*0.18,0.10,0.95);
    // A higher threshold separates smaller formations instead of joining sheets.
    float threshold=mix(0.64,0.44,coverage);
    return smoothstep(threshold,threshold+0.14,cloudFractal(fastCloudCoordinates(world),footprint));
}

float sheetCloudDensity(vec2 world, bool high) {
    vec2 wind=vec2(1.15,0.48)*frameTimeCounter;
    // Common advection permits stable history; altitude changes the morphology.
    vec2 p=rotCloud*(world+wind)*(high?0.00075:0.0011);
    if(high) {
        p=vec2(p.x*0.42,p.y*3.8);
        p.y+=(noise2D(p*0.24+7.3)-0.5)*1.4;
    }
    float n=noise2D(p)*0.57+noise2D(rotCloud*p*2.03+13.7)*0.29;
    n+=noise2D(rotCloud*p*4.11+3.2)*0.14;
    float weather=noise2D((world+wind)*0.00023+vec2(8.1,2.3));
    float coverage=CLOUD_COVERAGE+(high?0.0:rainStrength*0.22);
    float threshold=(high?0.57:0.60)-coverage*0.16;
    float body=smoothstep(threshold,threshold+0.22,n);
    body*=smoothstep(0.28,0.72,weather);
    // Upper sheets stay translucent so they do not cover the cumulus silhouettes.
    return body*(high?0.24:mix(0.52,0.90,rainStrength));
}
vec2 cloudShadowUV(vec3 world,vec3 ld) {
    vec2 ground=world.xz-ld.xz*((world.y-64.0)/max(ld.y,0.04));
    vec2 origin=floor(cameraPosition.xz/128.0)*128.0;
    return (ground-origin)/CLOUD_SHADOW_SPAN+0.5;
}
#endif

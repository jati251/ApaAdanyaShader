#ifndef AA_WATER
#define AA_WATER

// Small wave budgets without screen reflections use a cheaper optical path.
// Derived from existing quality controls; no additional preset switch is needed.
#if WATER_OCTAVES <= 4 && !defined(SSR)
#define AA_WATER_FAST
#endif

// World-anchored swells with analytic, pixel-filtered normals.
vec2 waterSlope(vec2 p, vec2 dx, vec2 dy, out float crest, out float unresolvedVariance) {
    // Long wind swells, crossing wavelets and oblique capillary ripples.
    const vec2 dirs[7] = vec2[7](
        vec2(0.8660, 0.5000),
        vec2(0.4226, -0.9063),
        vec2(-0.6428, 0.7660),
        vec2(0.9781, 0.2079),
        vec2(-0.3090, -0.9511),
        vec2(0.7071, -0.7071),
        vec2(-0.8660, 0.5000)
    );
    const float freq[7]   = float[7](0.24, 0.46, 0.94, 2.10, 4.80, 10.8, 23.5);
    const float amp[7]    = float[7](0.30, 0.19, 0.092, 0.038, 0.014, 0.0048, 0.0018);
    const float speeds[7] = float[7](0.61, 0.84, 1.21, 1.82, 2.75, 4.10, 6.15);

    vec2 slope = vec2(0.0);
    crest = 0.0;
    unresolvedVariance = 0.0;
    float crestWeight = 0.0;
    float storm = 1.0 + rainStrength * 0.65;
    #ifndef WIND_SPEED
    #define WIND_SPEED 1.0
    #endif
    float time = frameTimeCounter * (0.85 * WIND_SPEED);

    for(int i = 0; i < WATER_OCTAVES; i++) {
        vec2 d = dirs[i];
        vec2 perp = vec2(-d.y, d.x);
        float k = freq[i];

        float phaseSpeed = speeds[i] * time;
        #ifdef AA_WATER_FAST
        // Two crossing phases curve the crests without the full envelope/cubic model.
        float crossPhase=dot(p,perp)*(k*0.53)-phaseSpeed*0.61+float(i)*1.61803;
        float crossSin=sin(crossPhase),crossCos=cos(crossPhase);
        float phase=dot(p,d)*k-phaseSpeed+float(i)*2.39996+0.65*crossSin;
        vec2 gradPhase=d*k+perp*(k*0.53*0.65*crossCos);
        vec2 pixelPhase=vec2(dot(gradPhase,dx),dot(gradPhase,dy));
        float e=exp(-dot(pixelPhase,pixelPhase)/24.0);
        float e2=e*e,e4=e2*e2;
        float s=sin(phase),c=cos(phase);
        float a=amp[i]*0.78;
        slope+=gradPhase*a*(0.55*c*e+0.32*s*c*e4);
        crest+=(0.5+0.5*s*e)*a;
        crestWeight+=a;
        // Pixel filtering transfers missing ripple energy to the specular width.
        unresolvedVariance+=0.5*a*a*dot(gradPhase,gradPhase)
            *(0.3025*(1.0-e2)+0.0256*(1.0-e4*e4));
        #else
        vec2 envelopeAxis=d*(k*0.13)+perp*(k*0.09);
        float envelopePhase=dot(p,envelopeAxis)-phaseSpeed*0.17+float(i)*3.71;
        vec2 envelopePixel=vec2(dot(envelopeAxis,dx),dot(envelopeAxis,dy));
        float envelopeBand=exp(-dot(envelopePixel,envelopePixel)/24.0);
        float envelope=0.78+0.22*sin(envelopePhase)*envelopeBand;
        vec2 envelopeGradient=envelopeAxis*(0.22*cos(envelopePhase)*envelopeBand);

        // Transverse modulation curves each crest in world space.
        float phaseLong  = dot(p, d) * k - phaseSpeed + float(i) * 2.39996;
        float phaseTrans = dot(p, perp) * (k * 0.53) - phaseSpeed * 0.61 + float(i) * 1.61803;

        float curve = sin(phaseTrans);
        float psi = phaseLong + 0.95 * curve;

        // Cubic crests and broad troughs; geometry remains Minecraft fluid mesh.
        float s = sin(psi);
        // Analytical 2D gradient of crescent wave
        vec2 gradPhase = d * k + perp * (k * (0.53 * 0.95) * cos(phaseTrans));
        float a = amp[i] * envelope;
        // The cubic crest contains three harmonics. Filtering only the base
        // frequency leaves its sharper harmonics aliasing during camera motion.
        vec2 pixelPhase=vec2(dot(gradPhase,dx),dot(gradPhase,dy));
        float variance=dot(pixelPhase,pixelPhase)/12.0;
        float e=exp(-0.5*variance);
        float e2=e*e,e4=e2*e2;
        vec3 band=vec3(e,e4,e4*e4*e);
        float c=cos(psi);
        float peak=0.3125+0.46875*s*band.x
            -0.1875*(1.0-2.0*s*s)*band.y
            -0.03125*s*(3.0-4.0*s*s)*band.z;
        float derivative=0.46875*c*band.x
            +0.375*(2.0*s*c)*band.y-0.09375*(c*(4.0*c*c-3.0))*band.z;
        vec2 octaveSlope=gradPhase*(a*derivative);
        octaveSlope+=envelopeGradient*(amp[i]*peak);

        slope += octaveSlope;
        crest += max(peak,0.0) * a;
        crestWeight += a;
        // Transfer the filtered harmonics into highlight width, not screen noise.
        vec3 harmonicEnergy=vec3(0.21972656,0.140625,0.00878906);
        unresolvedVariance+=0.5*a*a*dot(gradPhase,gradPhase)
            *dot(harmonicEnergy,vec3(1.0)-band*band);
        #endif
    }

    #if !defined(NETHER) && !defined(END)
    if(rainStrength > 0.03) {
        vec2 ripPos = p * 2.6;
        float rt = frameTimeCounter * 3.15;
        float rippleScale = 2.6;
        vec2 ripGrad = vec2(0.0);
        float pixelFootprint=max(length(dx),length(dy));
        #ifdef AA_WATER_FAST
        const int rainLayers=1;
        #else
        const int rainLayers=2;
        #endif
        for(int r = 0; r < rainLayers; r++) {
            // Smaller layers only increase the footprint; every remaining band is zero.
            float rippleBand=1.0-smoothstep(0.7,2.8,pixelFootprint*rippleScale*31.4159);
            if(rippleBand<=0.0) break;
            vec2 cell = floor(ripPos);
            vec2 f = fract(ripPos) - 0.5;
            float h = hash12(cell + float(r) * 19.31);
            float age = fract(rt + h);
            float dist = length(f);
            float ring = sin(clamp(dist - age * 0.40, -0.2, 0.2) * 31.4159);
            float cellFade = 1.0-smoothstep(0.30, 0.48, dist);
            float fade = smoothstep(0.0, 0.08, age) * (1.0 - age) * smoothstep(0.0, 0.06, dist) * (1.0 - smoothstep(age * 0.40, age * 0.40 + 0.08, dist)) * cellFade;
            // The ring frequency is in cell space, so each smaller layer
            // needs its own world-space pixel filter at grazing angles.
            ripGrad += normalize(f + 1e-4) * ring * fade * rippleBand;
            ripPos = ripPos * 1.48 + vec2(7.13, 11.41);
            rippleScale *= 1.48;
        }
        slope += ripGrad * (rainStrength * 0.22);
    }
    #endif

    float strength=WATER_WAVES*storm;
    crest=clamp(crest/max(crestWeight,0.0001),0.0,1.0)*smoothstep(0.0,0.25,WATER_WAVES);
    unresolvedVariance*=strength*strength;
    return slope * strength;
}

vec2 waterSlope(vec2 p,vec2 dx,vec2 dy,out float crest) {
    float variance;
    return waterSlope(p,dx,dy,crest,variance);
}

float waterRoughness(float unresolvedVariance) {
    return sqrt(WATER_ROUGHNESS*WATER_ROUGHNESS+min(0.08,unresolvedVariance*1.6));
}

float waterShoreFoam(vec2 p,float depth,float crest,float footprint) {
    float shoreline=1.0-smoothstep(0.06,0.42,depth);
    float contact=smoothstep(0.005,0.045,depth);
    float time=frameTimeCounter*WIND_SPEED;
    vec2 drift=p+vec2(time*0.07,-time*0.05);
    // Sparse patches instead of curved contour lines or a constant white base.
    float patch=noise2D(drift*1.7+vec2(13.2,7.8));
    float patchMask=smoothstep(0.57,0.79,patch);
    float bubbles=noise2D(drift*11.0+vec2(3.7,23.1));
    bubbles=mix(bubbles,0.5,smoothstep(0.035,0.16,footprint));
    float wash=0.5+0.5*sin(dot(p,vec2(0.31,0.19))-time*0.72);
    float breakup=smoothstep(0.28,0.72,crest*0.60+wash*0.40+shoreline*0.12);
    return shoreline*contact*breakup*patchMask*(0.35+0.65*bubbles)
        *mix(0.16,0.42,rainStrength)*smoothstep(0.0,0.25,WATER_WAVES);
}

vec3 waterSurfaceNormal(vec3 meshNormal,vec2 slope) {
    // Fluid top normals can differ across the two triangles of one block.
    // Use one wave plane for tops; preserve vertical waterfalls and side faces.
    vec3 base=normalize(meshNormal);
    if(abs(base.y)>0.65) return normalize(vec3(-slope.x,sign(base.y),-slope.y));
    return base;
}

float waterFresnel(float nv, bool underwater) {
    float cosine = clamp(abs(nv), 0.0, 1.0);
    // Snell's law gives a critical angle of ~48.6 degrees when exiting water.
    if(underwater) {
        float transmittedSin2 = 1.776889 * (1.0 - cosine * cosine);
        if(transmittedSin2 >= 1.0) return 1.0;
        cosine = sqrt(1.0 - transmittedSin2);
    }
    float f = 1.0 - cosine;
    float f2 = f * f;
    return 0.0204 + 0.9796 * (f2 * f2 * f);
}

vec3 waterAbsorption() {
    // Natural freshwater: retain bed color in shallows, blue-green transmission at depth.
    #ifdef AA_WATER_FAST
    return vec3(0.13,0.065,0.048)/WATER_CLARITY;
    #else
    return vec3(0.14, 0.085, 0.11) / WATER_CLARITY;
    #endif
}

vec3 waterBodyColor(float thickness, float skyLight) {
    // In-scattered freshwater color; transmitted bed radiance is handled separately.
    #ifdef AA_WATER_FAST
    vec3 shallow = vec3(0.040,0.073,0.070);
    vec3 deep    = vec3(0.011,0.038,0.049);
    #else
    vec3 shallow = vec3(0.035, 0.065, 0.055);
    vec3 deep    = vec3(0.012, 0.030, 0.028);
    #endif
    return mix(shallow, deep, smoothstep(1.5, 18.0, thickness))
        * mix(0.15, 1.0, daylight()) * (0.2 + skyLight * 0.8);
}

#include "/lib/water_caustics.glsl"

#endif

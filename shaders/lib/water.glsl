#ifndef AA_WATER
#define AA_WATER

// Photorealistic directional water simulation with 2D non-linear crescent wave synthesis
vec2 waterSlope(vec2 p, vec2 dx, vec2 dy, out float crest) {
    // Multi-directional wind-aligned propagation: natural angular spread without parallel stripes
    const vec2 dirs[7] = vec2[7](
        vec2(0.8660, 0.5000),  // 30 deg: primary rolling ground swell (wind axis)
        vec2(0.9272, 0.3746),  // 22 deg: secondary lake swell (-8 deg)
        vec2(0.7660, 0.6428),  // 40 deg: surface swell (+10 deg)
        vec2(0.9659, 0.2588),  // 15 deg: wind chop (-15 deg)
        vec2(0.6691, 0.7431),  // 48 deg: crossing chop (+18 deg)
        vec2(0.8910, 0.4540),  // 27 deg: capillary ripples (-3 deg)
        vec2(0.7986, 0.6018)   // 37 deg: liquid micro-sheen (+7 deg)
    );
    const float freq[7]   = float[7](0.085, 0.18, 0.42, 1.05, 2.70, 6.80, 16.5);
    const float amp[7]    = float[7](0.32,  0.16, 0.075, 0.032, 0.013, 0.0045, 0.0015);
    const float speeds[7] = float[7](0.26,  0.40, 0.65, 1.08, 1.75, 2.90, 4.60);

    vec2 slope = vec2(0.0);
    crest = 0.0;
    float storm = 1.0 + rainStrength * 0.65;
    #ifndef WIND_SPEED
    #define WIND_SPEED 1.0
    #endif
    float time = mod(frameTimeCounter, 6283.1853) * (0.85 * WIND_SPEED);

    // Organic swell envelope modulates height over space, preventing rigid repetition
    float swellEnv = 0.85 + 0.15 * sin(dot(p, vec2(0.038, 0.024)) - time * 0.18);
    vec2 swellSlope = vec2(0.0);

    for(int i = 0; i < WATER_OCTAVES; i++) {
        vec2 d = dirs[i];
        vec2 perp = vec2(-d.y, d.x);
        float k = freq[i];

        // Band-limiting based on pixel footprint prevents far-distance moiré / shimmering
        float footprint = k * length(vec2(dot(dx, d), dot(dy, d)));
        float band = 1.0 - smoothstep(0.7, 2.8, footprint);
        if(band <= 0.001) continue;

        // Hydrodynamic advection: higher-frequency ripples ride on swell crests
        vec2 pos = (i >= 2) ? (p + swellSlope * (0.05 / (1.0 + k * 0.06))) : p;

        float phaseSpeed = mod(speeds[i] * time, 628.31853);

        // 2D Non-linear crescent wave:
        // Transverse phase modulates longitudinal wave, transforming straight 1D lines
        // into organic 2D crescent-shaped liquid ripples with zero parallel stripes or grid lines
        float phaseLong  = dot(pos, d) * k - phaseSpeed + float(i) * 2.39996;
        float phaseTrans = dot(pos, perp) * (k * 0.65) - phaseSpeed * 0.70 + float(i) * 1.61803;

        float curve = sin(phaseTrans);
        float psi = phaseLong + 0.75 * curve;

        // Gerstner / Trochoidal profile: sharp peaked crests and broad, glassy, calm troughs
        float s = sin(psi);
        float profile = (1.0 + s) * 0.5;
        float peak = profile * profile;

        // Analytical 2D gradient of crescent wave
        vec2 gradPhase = d * k + perp * (k * (0.65 * 0.75) * cos(phaseTrans));
        float a = amp[i] * ((i < 2) ? swellEnv : 1.0) * band;
        vec2 octaveSlope = gradPhase * (cos(psi) * (1.0 + s) * (a * 0.5));

        slope += octaveSlope;
        if(i < 2) swellSlope += octaveSlope;
        crest += peak * a;
    }

    #if !defined(NETHER) && !defined(END)
    if(rainStrength > 0.03) {
        vec2 ripPos = p * 2.6;
        float rt = mod(frameTimeCounter * 4.2, 6283.1853);
        vec2 ripGrad = vec2(0.0);
        for(int r = 0; r < 2; r++) {
            vec2 cell = floor(ripPos);
            vec2 f = fract(ripPos) - 0.5;
            float h = hash12(cell + float(r) * 19.31);
            float age = fract(rt * 0.75 + h);
            float dist = length(f);
            float ring = sin(clamp(dist - age * 0.40, -0.2, 0.2) * 31.4159);
            float cellFade = smoothstep(0.48, 0.30, dist);
            float fade = (1.0 - age) * smoothstep(0.0, 0.06, dist) * (1.0 - smoothstep(age * 0.40, age * 0.40 + 0.08, dist)) * cellFade;
            ripGrad += normalize(f + 1e-4) * ring * fade;
            ripPos = ripPos * 1.48 + vec2(7.13, 11.41);
        }
        slope += ripGrad * (rainStrength * 0.22);
    }
    #endif

    return slope * (WATER_WAVES * storm);
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
    // Photorealistic freshwater absorption (natural clarity with organic sediment/tannin depth)
    return vec3(0.13, 0.09, 0.22) / WATER_CLARITY;
}

vec3 waterBodyColor(float thickness, float skyLight) {
    // Photorealistic natural freshwater: translucent mossy shallows into deep peat-riverbed depth
    vec3 shallow = vec3(0.038, 0.065, 0.048);
    vec3 deep    = vec3(0.012, 0.025, 0.020);
    return mix(shallow, deep, smoothstep(1.5, 18.0, thickness))
        * mix(0.15, 1.0, daylight()) * (0.2 + skyLight * 0.8);
}

// Focused organic cellular caustics
float waterCaustic(vec2 p, float time) {
    vec2 p1 = p * 1.25 + vec2(time * 0.38, time * 0.26);
    vec2 p2 = p * 1.55 - vec2(time * 0.28, -time * 0.35);

    // Cross-advection curves light rays into non-linear cellular loops
    vec2 d1 = vec2(sin(p2.y * 2.2 + time * 0.8), cos(p2.x * 2.2 - time * 0.7)) * 0.38;
    vec2 d2 = vec2(cos(p1.y * 2.6 - time * 0.9), sin(p1.x * 2.6 + time * 0.6)) * 0.38;

    float c1 = length(sin(p1 + d1));
    float c2 = length(cos(p2 + d2));

    float web = pow(clamp(1.0 - (c1 + c2) * 0.44, 0.0, 1.0), 3.5) * 4.2;
    return web;
}

#endif

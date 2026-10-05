#ifndef AA_WATER
#define AA_WATER

// Multi-scale natural water surface with directional dispersion and curved wave crests
vec2 waterSlope(vec2 p, vec2 dx, vec2 dy, out float crest) {
    const vec2 dirs[7] = vec2[7](
        vec2(0.9135, 0.4067),  // 24 deg (primary swell)
        vec2(0.6157, 0.7880),  // 52 deg (crossing swell)
        vec2(0.9962, 0.0872),  //  5 deg (wind chop 1)
        vec2(0.3090, 0.9511),  // 72 deg (wind chop 2)
        vec2(0.9613, -0.2756), // -16 deg (capillary wave 1)
        vec2(0.0698, 0.9976),  // 86 deg (micro ripple 1)
        vec2(0.8480, -0.5299)  // -32 deg (capillary sheen)
    );
    const float freq[7]   = float[7](0.085, 0.17, 0.38, 0.90, 2.4, 6.5, 14.0);
    const float amp[7]    = float[7](0.45,  0.26, 0.15, 0.070, 0.024, 0.008, 0.0025);
    const float speeds[7] = float[7](0.22,  0.35, 0.62, 1.15, 2.10, 3.65, 5.40);

    vec2 slope = vec2(0.0);
    crest = 0.0;
    float storm = 1.0 + rainStrength * 0.65;
    #ifndef WIND_SPEED
    #define WIND_SPEED 1.0
    #endif
    float time = mod(frameTimeCounter, 6283.1853) * (0.85 * WIND_SPEED);

    // Large-scale turbulent fluid flow warp:
    // Destroys linear wave fronts and geometric diamond grids, producing natural fluid curves
    vec2 flowWarp = vec2(
        sin(p.y * 0.075 + time * 0.16 + sin(p.x * 0.055)),
        cos(p.x * 0.065 - time * 0.14 + cos(p.y * 0.048))
    ) * 1.55;
    flowWarp += vec2(
        cos(p.y * 0.16 - time * 0.22),
        sin(p.x * 0.14 + time * 0.20)
    ) * 0.55;

    // Warped sampling coordinates for organic, non-repeating fluid propagation
    vec2 wp = p + flowWarp;

    // Organic swell envelope modulates height over space, preventing rigid repetition
    float swellEnv = 0.82 + 0.18 * sin(dot(wp, vec2(0.038, 0.024)) - time * 0.18);
    vec2 swellSlope = vec2(0.0);

    for(int i = 0; i < WATER_OCTAVES; i++) {
        float k = freq[i];

        // Smooth spatial angular dispersion:
        // Wave propagation direction curves naturally across space by +/- 20 degrees,
        // preventing wave crests from forming parallel straight lines or rigid grid lattices
        float angleDisp = sin(dot(wp, vec2(0.042, 0.032)) * (1.0 + float(i) * 0.25) + float(i) * 1.72 - time * 0.12) * 0.36;
        float cosD = cos(angleDisp), sinD = sin(angleDisp);
        vec2 d = vec2(dirs[i].x * cosD - dirs[i].y * sinD, dirs[i].x * sinD + dirs[i].y * cosD);

        // Band-limiting based on pixel footprint prevents far-distance moiré / shimmering
        float footprint = k * length(vec2(dot(dx, d), dot(dy, d)));
        float band = 1.0 - smoothstep(0.7, 2.8, footprint);
        if(band <= 0.001) continue;

        // Hydrodynamic wave-current interaction: higher-frequency ripples are advected smoothly by
        // the broad underlying swell, eliminating high-frequency recursive feedback and flicker
        vec2 pos = (i >= 2) ? (wp + swellSlope * (0.08 / (1.0 + k * 0.10))) : wp;

        // Finite crest length envelope (wave packets):
        // Real waves exist as localized wave packets that taper off transversely,
        // eliminating infinite continuous lines and cross-hatch waffles
        vec2 perp = vec2(-d.y, d.x);
        float packet = 0.60 + 0.40 * cos(dot(pos, perp) * (k * 0.30) + float(i) * 2.14);

        // Lateral crest curvature: gives waves natural organic curvature
        float latPhase = dot(pos, perp) * (k * 0.45) + float(i) * 1.61803;
        float latWave = sin(latPhase);
        float latDeriv = cos(latPhase);

        float phaseSpeed = mod(speeds[i] * time, 628.31853);
        float phase = dot(pos, d) * k + 0.55 * latWave - phaseSpeed + float(i) * 2.39996;
        vec2 gradPhase = d * k + perp * (0.22 * k * latDeriv);

        // Peaked trochoidal profile with steepened forward slope
        float s = sin(phase);
        float peak = exp(s - 1.0);
        float a = amp[i] * ((i < 2) ? swellEnv : 1.0) * packet * band;
        float peakA = peak * a;
        vec2 octaveSlope = gradPhase * (cos(phase) * peakA);
        slope += octaveSlope;
        if(i < 2) swellSlope += octaveSlope;
        crest += peakA;
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
    // Natural murky freshwater absorption:
    // Humic acids & tannins absorb blue rapidly, while sediment/chlorophyll balances red & green
    return vec3(0.18, 0.12, 0.32) / WATER_CLARITY;
}

vec3 waterBodyColor(float thickness, float skyLight) {
    // Murky natural freshwater: earthy moss/olive shallows transitioning to deep sediment-peat
    vec3 shallow = vec3(0.042, 0.068, 0.040);
    vec3 deep    = vec3(0.015, 0.028, 0.018);
    return mix(shallow, deep, smoothstep(1.0, 14.0, thickness))
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

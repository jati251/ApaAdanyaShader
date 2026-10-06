#ifndef AA_WATER
#define AA_WATER

// World-anchored swells with analytic, pixel-filtered normals.
vec2 waterSlope(vec2 p, vec2 dx, vec2 dy, out float crest) {
    // Crossing swells around the prevailing wind direction.
    const vec2 dirs[7] = vec2[7](
        vec2(0.8660, 0.5000),  // 30 deg: primary rolling ground swell (wind axis)
        vec2(0.9848, -0.1736),
        vec2(0.5736, 0.8192),
        vec2(0.9659, 0.2588),
        vec2(0.1736, 0.9848),
        vec2(0.8910, 0.4540),  // 27 deg: capillary ripples (-3 deg)
        vec2(0.7986, 0.6018)   // 37 deg: liquid micro-sheen (+7 deg)
    );
    const float freq[7]   = float[7](0.18, 0.34, 0.72, 1.55, 3.80, 8.40, 18.0);
    const float amp[7]    = float[7](0.48, 0.25, 0.105, 0.042, 0.017, 0.006, 0.0022);
    const float speeds[7] = float[7](0.52, 0.73, 1.08, 1.56, 2.36, 3.51, 5.15);

    vec2 slope = vec2(0.0);
    crest = 0.0;
    float storm = 1.0 + rainStrength * 0.65;
    #ifndef WIND_SPEED
    #define WIND_SPEED 1.0
    #endif
    float time = frameTimeCounter * (0.85 * WIND_SPEED);

    // Organic swell envelope modulates height over space, preventing rigid repetition
    float envelopePhase=dot(p,vec2(0.038,0.024))-time*0.18;
    float swellEnv=0.85+0.15*sin(envelopePhase);
    vec2 envelopeGradient=0.15*cos(envelopePhase)*vec2(0.038,0.024);

    for(int i = 0; i < WATER_OCTAVES; i++) {
        vec2 d = dirs[i];
        vec2 perp = vec2(-d.y, d.x);
        float k = freq[i];

        vec2 pos = p;
        float phaseSpeed = speeds[i] * time;

        // Transverse modulation curves each crest in world space.
        float phaseLong  = dot(pos, d) * k - phaseSpeed + float(i) * 2.39996;
        float phaseTrans = dot(pos, perp) * (k * 0.65) - phaseSpeed * 0.70 + float(i) * 1.61803;

        float curve = sin(phaseTrans);
        float psi = phaseLong + 0.75 * curve;

        // Cubic crests and broad troughs; geometry remains Minecraft fluid mesh.
        float s = sin(psi);
        float profile = (1.0 + s) * 0.5;
        float peak = profile * profile * profile;

        // Analytical 2D gradient of crescent wave
        vec2 gradPhase = d * k + perp * (k * (0.65 * 0.75) * cos(phaseTrans));
        float a = amp[i] * ((i < 2) ? swellEnv : 1.0);
        // The cubic crest contains three harmonics. Filtering only the base
        // frequency leaves its sharper harmonics aliasing during camera motion.
        vec2 pixelPhase=vec2(dot(gradPhase,dx),dot(gradPhase,dy));
        float variance=dot(pixelPhase,pixelPhase)/12.0;
        vec3 band=exp(-0.5*variance*vec3(1.0,4.0,9.0));
        float derivative=0.46875*cos(psi)*band.x
            +0.375*sin(2.0*psi)*band.y-0.09375*cos(3.0*psi)*band.z;
        vec2 octaveSlope=gradPhase*(a*derivative);
        if(i < 2) octaveSlope+=envelopeGradient*(amp[i]*peak*band.x);

        slope += octaveSlope;
        // Foam and crest light follow the physical wave, not camera pixel size.
        crest += peak * a;
    }

    #if !defined(NETHER) && !defined(END)
    if(rainStrength > 0.03) {
        vec2 ripPos = p * 2.6;
        float rt = frameTimeCounter * 3.15;
        float rippleScale = 2.6;
        vec2 ripGrad = vec2(0.0);
        for(int r = 0; r < 2; r++) {
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
            float rippleFootprint = max(length(dx), length(dy)) * rippleScale * 31.4159;
            float rippleBand = 1.0 - smoothstep(0.7, 2.8, rippleFootprint);
            ripGrad += normalize(f + 1e-4) * ring * fade * rippleBand;
            ripPos = ripPos * 1.48 + vec2(7.13, 11.41);
            rippleScale *= 1.48;
        }
        slope += ripGrad * (rainStrength * 0.22);
    }
    #endif

    return slope * (WATER_WAVES * storm);
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

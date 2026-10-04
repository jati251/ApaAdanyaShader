#ifndef AA_ATMOSPHERE
#define AA_ATMOSPHERE

vec3 skyRadiance(vec3 rd) {
    #ifdef NETHER
    return pow(fogColor, vec3(2.2)) * 0.6 + vec3(0.018, 0.003, 0.001);
    #elif defined(END)
    return mix(vec3(0.016, 0.009, 0.035), vec3(0.07, 0.035, 0.12), exp(-abs(rd.y) * 5.0));
    #else
    vec3 sd = sunDirection(); float day = daylight();
    float horizon = pow(1.0 - max(rd.y, 0.0), 5.0);
    vec3 sky = mix(vec3(0.025, 0.125, 0.34), vec3(0.30, 0.43, 0.56), horizon);
    float sunset = exp(-abs(sd.y) * 10.0);
    float facing = pow(sat(dot(rd, sd) * 0.5 + 0.5), 8.0);
    sky = mix(sky, vec3(0.9, 0.24, 0.065), sunset * horizon * (0.22 + facing * 0.65));
    sky *= mix(0.25, 1.0, smoothstep(-0.08, 0.25, sd.y));
    sky = mix(vec3(0.0018, 0.0035, 0.009) + vec3(0.008, 0.012, 0.024) * horizon, sky, day);
    sky = mix(sky, vec3(dot(sky, vec3(0.2126, 0.7152, 0.0722))) * 0.75, rainStrength * 0.8);
    float sunDot = dot(rd, sd), moonDot = dot(rd, -sd);
    sky += vec3(12.0, 9.5, 6.5) * smoothstep(0.99994, 0.999975, sunDot) * day * (1.0 - rainStrength);
    sky += vec3(0.22, 0.30, 0.48) * smoothstep(0.99982, 0.9999, moonDot) * (1.0 - day);
    sky += lightColor() * pow(sat(sunDot), 512.0) * 0.055;
    vec3 starCell = floor(rd * 650.0);
    sky += vec3(pow(hash13(starCell), 950.0)) * smoothstep(0.02, 0.3, rd.y) * (1.0 - day) * (1.0 - rainStrength) * 0.5;
    return sky;
    #endif
}

// Interleaved Gradient Noise for grain-free raymarching
float ignDither(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// Fast 2D hash for cellular Worley noise
vec2 hash22Fast(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// 2D Worley noise: creates discrete, individual small cumulus cloud puffs
float worley2D(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    float minD = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 g = vec2(float(x), float(y));
            vec2 o = hash22Fast(i + g);
            vec2 diff = g + o - f;
            minD = min(minD, dot(diff, diff));
        }
    }
    return sqrt(minD);
}

// Small, realistic cumulus layer altitude
const float CLOUD_ALT_BASE = 280.0;
const float CLOUD_ALT_THICK = 55.0;

// High-detail small cumulus puff density field
float sampleCloudDensity(vec3 p, bool detail) {
    float h = (p.y - CLOUD_ALT_BASE) / CLOUD_ALT_THICK;
    if (h <= 0.0 || h >= 1.0) return 0.0;

    vec2 wind = vec2(frameTimeCounter * 1.5, frameTimeCounter * 0.6);
    // Higher frequency (0.0068) creates small, distinct cloud puffs (~60-120m across)
    vec2 pos2d = (p.xz + wind) * 0.0068;

    // Base Worley cell: creates isolated individual cloud puffs
    float w1 = 1.0 - worley2D(pos2d);
    float w2 = 1.0 - worley2D(pos2d * 2.6 + vec2(1.7, 4.3));
    float billow = w1 * 0.70 + w2 * 0.30;

    // Macro weather modulation: produces varied sky openings and puff clusters
    float weather = noise3(vec3(p.xz * 0.0007, 0.45));
    float coverage = CLOUD_COVERAGE * 0.70 + rainStrength * 0.30;
    float threshold = 0.60 - coverage * 0.28 + (1.0 - weather) * 0.14;

    if (billow < threshold) return 0.0;

    // Dome profile for each small puff: flat condensation base at dew point, rounded dome top
    float puffCore = sat((billow - threshold) / (1.0 - threshold));
    float dome = sqrt(max(1.0 - (1.0 - puffCore) * (1.0 - puffCore), 0.0));

    float baseFade = smoothstep(0.0, 0.12, h);
    float topFade = smoothstep(dome, dome - 0.25, h);
    float vert = baseFade * topFade;
    if (vert <= 0.001) return 0.0;

    float density = vert * smoothstep(0.0, 0.25, puffCore);

    // Fine 3D fractal cauliflower billow erosion
    if (detail && density > 0.01) {
        vec3 q = (p + vec3(wind.x, 0.0, wind.y)) * 0.022;
        float n1 = noise3(q);
        float n2 = noise3(q * 2.5 + vec3(1.3, 2.1, 0.7));
        float fluff = n1 * 0.65 + n2 * 0.35;
        density = clamp(density - (1.0 - fluff) * 0.28 * smoothstep(0.08, 0.85, h), 0.0, 1.0);
    }

    return density;
}

float cloudDensity(vec3 p) { return sampleCloudDensity(p, true); }

vec3 renderClouds(vec3 rd, vec3 background, vec2 pixel) {
    #ifdef VOLUMETRIC_CLOUDS
    #if !defined(NETHER) && !defined(END)
    // Smooth horizon fade
    if (rd.y < 0.020) return background;
    float horizonFade = smoothstep(0.020, 0.09, rd.y);

    float a = (CLOUD_ALT_BASE - cameraPosition.y) / rd.y;
    float b = (CLOUD_ALT_BASE + CLOUD_ALT_THICK - cameraPosition.y) / rd.y;
    float entry = max(min(a, b), 0.0);
    float leave = max(a, b);
    if (leave <= entry) return background;

    // Bounded raymarching depth: small clouds overhead need tight step length
    float maxRayDist = min(leave - entry, 1500.0);
    float distFade = 1.0 - smoothstep(1000.0, 2000.0, entry);
    float fadeWeight = horizonFade * distFade;
    if (fadeWeight <= 0.001) return background;

    float stepLen = maxRayDist / float(CLOUD_STEPS);

    // High quality interleaved dither
    float dither = ignDither(pixel);
    float t = entry + stepLen * dither;

    vec3 sd = sunDirection();
    float day = daylight();
    vec3 sunCol = lightColor();

    // Dual-lobe Henyey-Greenstein scattering (silver lining facing sun)
    float sunTheta = dot(rd, sd);
    float forwardMie = pow(sat(sunTheta * 0.5 + 0.5), 14.0) * 3.4;
    float backScatter = pow(sat(-sunTheta * 0.5 + 0.5), 4.0) * 0.45;
    float phase = 0.32 + forwardMie + backScatter;

    // Night moonlight scattering
    vec3 md = -sd;
    float moonTheta = dot(rd, md);
    float moonMie = pow(sat(moonTheta * 0.5 + 0.5), 16.0) * 1.6;
    vec3 moonColor = vec3(0.006, 0.010, 0.022) * NIGHT_BRIGHTNESS;

    float trans = 1.0;
    vec3 cloudSum = vec3(0.0);

    for (int i = 0; i < CLOUD_STEPS; i++) {
        vec3 p = cameraPosition + rd * t;
        float density = sampleCloudDensity(p, true);
        if (density > 0.003) {
            // Shadow raymarch towards sun
            vec3 ld = (day > 0.05) ? sd : md;
            float opt1 = sampleCloudDensity(p + ld * 10.0, false);
            float opt2 = sampleCloudDensity(p + ld * 30.0, false);
            float optical = opt1 * 24.0 + opt2 * 48.0;

            // Powder sugar multiple scattering effect
            float powder = 1.0 - exp(-optical * 0.60);
            float directShade = exp(-optical * 0.12) * (0.75 + powder * 0.45);

            // Realistic atmospheric ambient:
            // Day: cool sky blue from above + warm ground bounce from below (creates deep 3D shading on each small puff)
            // Night: dark silhouette matching starry sky
            float hRel = sat((p.y - CLOUD_ALT_BASE) / CLOUD_ALT_THICK);
            vec3 skyAmbient = vec3(0.24, 0.36, 0.52) * (0.30 + hRel * 0.70);
            vec3 groundBounce = vec3(0.18, 0.16, 0.12) * (0.80 - hRel * 0.50);
            vec3 dayAmbient = (skyAmbient + groundBounce) * (0.45 + 0.55 * exp(-density * 2.5));
            vec3 nightAmbient = vec3(0.0004, 0.0007, 0.0016) * NIGHT_BRIGHTNESS;
            vec3 ambient = mix(nightAmbient, dayAmbient, day);

            // Direct light: bright sunlit highlight vs soft moonlight rim
            vec3 dayDirect = sunCol * (directShade * phase + 0.04 * exp(-optical * 0.025));
            vec3 nightDirect = moonColor * (directShade * (0.03 + moonMie));
            vec3 directLight = mix(nightDirect, dayDirect, day);

            vec3 light = ambient + directLight;

            float opacity = 1.0 - exp(-density * stepLen * 0.08);
            cloudSum += trans * light * opacity;
            trans *= (1.0 - opacity);
        }
        t += stepLen;
        if (trans < 0.015) break;
    }

    // Atmospheric perspective haze
    float aerial = 1.0 - exp(-entry * 0.0012);
    cloudSum = mix(cloudSum, background * (1.0 - trans), aerial);

    vec3 result = background * trans + cloudSum;
    return mix(background, result, fadeWeight);
    #endif
    #endif
    return background;
}

#endif

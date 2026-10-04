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

// Interleaved Gradient Noise for perceptual grain-free dithering
float ignDither(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// 2D cloud coverage noise: defines distinct, natural cloud bodies across the sky
float cloud2D(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    float n1 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);

    vec2 p2 = p * 2.2 + vec2(1.7, 4.3);
    vec2 i2 = floor(p2), f2 = fract(p2);
    f2 = f2 * f2 * (3.0 - 2.0 * f2);
    float a2 = hash12(i2);
    float b2 = hash12(i2 + vec2(1.0, 0.0));
    float c2 = hash12(i2 + vec2(0.0, 1.0));
    float d2 = hash12(i2 + vec2(1.0, 1.0));
    float n2 = mix(mix(a2, b2, f2.x), mix(c2, d2, f2.x), f2.y);

    return n1 * 0.65 + n2 * 0.35;
}

// Elevated cloud altitude (majestic high ceiling, ~200 blocks above player)
const float CLOUD_ALT_BASE = 300.0;
const float CLOUD_ALT_THICK = 100.0;

// High-fidelity 3D cumulus dome density field
float sampleCloudDensity(vec3 p, bool detail) {
    // Earth curvature compensation: curves clouds over horizon, eliminating horizontal pancake stretching
    vec2 camDist = p.xz - cameraPosition.xz;
    float curvedY = p.y - dot(camDist, camDist) * 0.000008;

    float h = (curvedY - CLOUD_ALT_BASE) / CLOUD_ALT_THICK;
    if (h <= 0.0 || h >= 1.0) return 0.0;

    vec2 wind = vec2(frameTimeCounter * 1.2, frameTimeCounter * 0.5);
    vec2 pos2d = (p.xz + wind) * 0.0018;

    float shape2D = cloud2D(pos2d);
    float coverage = CLOUD_COVERAGE * 0.75 + rainStrength * 0.25;
    float threshold = 0.50 - coverage * 0.35;

    if (shape2D < threshold - 0.05) return 0.0;

    // Cumulus dome: cloud height scales naturally with 2D cloud body core
    float domeHeight = smoothstep(threshold - 0.05, threshold + 0.32, shape2D);
    if (h > domeHeight) return 0.0;

    // Vertical profile: flat condensation base at dew point, rounded dome top
    float baseFade = smoothstep(0.0, 0.12, h);
    float topFade = smoothstep(domeHeight, domeHeight - 0.22, h);
    float vert = baseFade * topFade;

    float density = vert * smoothstep(threshold - 0.05, threshold + 0.18, shape2D);

    // 3D volumetric erosion: sculpts fluffy cauliflower billows into the dome sides
    if (detail && density > 0.01) {
        float n3d = noise3((p + vec3(wind.x, 0.0, wind.y)) * 0.010);
        density = clamp(density - (1.0 - n3d) * 0.25 * smoothstep(0.08, 0.90, h), 0.0, 1.0);
    }

    return density;
}

float cloudDensity(vec3 p) { return sampleCloudDensity(p, true); }

vec3 renderClouds(vec3 rd, vec3 background, vec2 pixel) {
    #ifdef VOLUMETRIC_CLOUDS
    #if !defined(NETHER) && !defined(END)
    // Horizon fade prevents artificial walls near distant horizon
    if (rd.y < 0.018) return background;
    float horizonFade = smoothstep(0.018, 0.09, rd.y);

    float a = (CLOUD_ALT_BASE - cameraPosition.y) / rd.y;
    float b = (CLOUD_ALT_BASE + CLOUD_ALT_THICK - cameraPosition.y) / rd.y;
    float entry = max(min(a, b), 0.0);
    float leave = max(a, b);
    if (leave <= entry) return background;

    // Clamp raymarching depth: avoids distant step stretching and banding
    float maxRayDist = min(leave - entry, 1800.0);
    float distFade = 1.0 - smoothstep(1200.0, 2400.0, entry);
    float fadeWeight = horizonFade * distFade;
    if (fadeWeight <= 0.001) return background;

    float stepLen = maxRayDist / float(CLOUD_STEPS);

    // High quality interleaved dither (smooth, no stepping lines)
    float dither = ignDither(pixel);
    float t = entry + stepLen * dither;

    vec3 sd = sunDirection();
    float day = daylight();
    vec3 sunCol = lightColor();

    // Dual-lobe Henyey-Greenstein scattering (silver lining facing sun, bright backscatter)
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
            // Shadow raymarch towards primary light source
            vec3 ld = (day > 0.05) ? sd : md;
            float opt1 = sampleCloudDensity(p + ld * 14.0, false);
            float opt2 = sampleCloudDensity(p + ld * 42.0, false);
            float optical = opt1 * 28.0 + opt2 * 56.0;

            // Powder sugar multiple scattering effect
            float powder = 1.0 - exp(-optical * 0.55);
            float directShade = exp(-optical * 0.10) * (0.75 + powder * 0.45);

            // Realistic atmospheric ambient:
            // Day: cool sky blue from above + warm ground bounce from below (creates deep 3D shading)
            // Night: dark silhouette matching starry night sky (no radioactive glowing fog)
            float hRel = sat((p.y - CLOUD_ALT_BASE) / CLOUD_ALT_THICK);
            vec3 skyAmbient = vec3(0.20, 0.30, 0.45) * (0.25 + hRel * 0.75);
            vec3 groundBounce = vec3(0.15, 0.14, 0.11) * (0.80 - hRel * 0.50);
            vec3 dayAmbient = (skyAmbient + groundBounce) * (0.45 + 0.55 * exp(-density * 2.2));
            vec3 nightAmbient = vec3(0.0004, 0.0007, 0.0016) * NIGHT_BRIGHTNESS;
            vec3 ambient = mix(nightAmbient, dayAmbient, day);

            // Direct light: bright sunlit highlight vs soft moonlight rim
            vec3 dayDirect = sunCol * (directShade * phase + 0.04 * exp(-optical * 0.02));
            vec3 nightDirect = moonColor * (directShade * (0.03 + moonMie));
            vec3 directLight = mix(nightDirect, dayDirect, day);

            vec3 light = ambient + directLight;

            float opacity = 1.0 - exp(-density * stepLen * 0.06);
            cloudSum += trans * light * opacity;
            trans *= (1.0 - opacity);
        }
        t += stepLen;
        if (trans < 0.015) break;
    }

    // Atmospheric perspective haze
    float aerial = 1.0 - exp(-entry * 0.0010);
    cloudSum = mix(cloudSum, background * (1.0 - trans), aerial);

    vec3 result = background * trans + cloudSum;
    return mix(background, result, fadeWeight);
    #endif
    #endif
    return background;
}

#endif

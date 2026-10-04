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

float sampleCloudDensity(vec3 p, bool detail) {
    // Cloud vertical boundary: base at 220, top at 360 (140 blocks depth)
    float h = (p.y - 220.0) / 140.0;
    if (h <= 0.0 || h >= 1.0) return 0.0;

    vec3 wind = vec3(frameTimeCounter * 1.4, 0.0, frameTimeCounter * 0.5);
    vec3 q = p + wind;

    // Macro weather distribution: creates natural cumulus clusters with open clear skies
    float weather = noise3(vec3(q.x * 0.00045, 0.12, q.z * 0.00045));
    float coverage = CLOUD_COVERAGE * 0.85 + rainStrength * 0.22;
    if (weather + coverage < 0.62) return 0.0;

    // 3-octave billow noise: rounded cauliflower domes
    vec3 p1 = q * 0.0028;
    vec3 p2 = q * 0.0068;
    vec3 p3 = q * 0.0150;

    float b1 = 1.0 - abs(noise3(p1) * 2.0 - 1.0);
    float b2 = 1.0 - abs(noise3(p2) * 2.0 - 1.0);
    float b3 = detail ? (1.0 - abs(noise3(p3) * 2.0 - 1.0)) : 0.5;

    float base = b1 * 0.52 + b2 * 0.34 + b3 * 0.14;

    // Flat condensation base (dew point altitude) + convective billow domes on top
    float baseFade = smoothstep(0.0, 0.08, h);
    float topFade = 1.0 - smoothstep(0.48, 1.0, h * (0.85 + (1.0 - b1) * 0.55));
    float verticalProfile = baseFade * topFade;

    float threshold = 0.58 - coverage * 0.40 + (1.0 - weather) * 0.20;
    if (base < threshold - 0.08) return 0.0;

    float density = smoothstep(threshold - 0.08, threshold + 0.14, base) * verticalProfile;

    // Fine wispy erosion
    if (detail && density > 0.01) {
        float wisp = noise3(q * 0.040) * 0.6 + noise3(q * 0.085) * 0.4;
        density = clamp(density - (1.0 - wisp) * 0.14 * smoothstep(0.1, 0.85, h), 0.0, 1.0);
    }

    return density;
}

float cloudDensity(vec3 p) { return sampleCloudDensity(p, true); }

vec3 renderClouds(vec3 rd, vec3 background, vec2 pixel) {
    #ifdef VOLUMETRIC_CLOUDS
    #if !defined(NETHER) && !defined(END)
    if (rd.y < 0.012) return background;

    float a = (220.0 - cameraPosition.y) / rd.y;
    float b = (360.0 - cameraPosition.y) / rd.y;
    float entry = max(min(a, b), 0.0);
    float leave = min(max(a, b), 8000.0);
    if (leave <= entry) return background;

    float stepLen = (leave - entry) / float(CLOUD_STEPS);

    // Interleaved spatial dither to eliminate banding
    float dither = fract(sin(dot(floor(pixel), vec2(12.9898, 78.233))) * 43758.5453);
    float t = entry + dither * stepLen;

    vec3 ld = sunDirection();
    float cosTheta = dot(rd, ld);

    // Dual-lobe Henyey-Greenstein scattering: intense silver lining towards sun, bright backscatter away
    float forwardMie = pow(sat(cosTheta * 0.5 + 0.5), 14.0) * 3.2;
    float backScatter = pow(sat(-cosTheta * 0.5 + 0.5), 4.0) * 0.42;
    float phase = 0.35 + forwardMie + backScatter;

    float trans = 1.0;
    vec3 cloudSum = vec3(0.0);
    float day = daylight();
    vec3 sunCol = lightColor();

    for (int i = 0; i < CLOUD_STEPS; i++) {
        vec3 p = cameraPosition + rd * t;
        float density = sampleCloudDensity(p, true);
        if (density > 0.002) {
            // Strategic 2-sample shadow raymarch towards sun
            float opt1 = sampleCloudDensity(p + ld * 16.0, false);
            float opt2 = sampleCloudDensity(p + ld * 50.0, false);
            float optical = opt1 * 32.0 + opt2 * 65.0;

            // Multiple scattering (powder sugar effect)
            float powder = 1.0 - exp(-optical * 0.45);
            float directShade = exp(-optical * 0.075) * (0.80 + powder * 0.40);

            // Natural atmospheric ambient lighting (soft sky blue above + warm terrain bounce below)
            float hRel = sat((p.y - 220.0) / 140.0);
            vec3 skyAmbient = mix(vec3(0.04, 0.06, 0.12), vec3(0.55, 0.68, 0.85), day) * (0.45 + hRel * 0.55);
            vec3 groundBounce = mix(vec3(0.015, 0.02, 0.025), vec3(0.48, 0.44, 0.38), day) * (0.85 - hRel * 0.40);
            vec3 ambient = (skyAmbient + groundBounce) * (0.65 + 0.35 * exp(-density * 2.5));

            vec3 light = ambient + sunCol * (directShade * phase + 0.05 * exp(-optical * 0.012));

            float opacity = 1.0 - exp(-density * stepLen * 0.045);
            cloudSum += trans * light * opacity;
            trans *= (1.0 - opacity);
        }
        t += stepLen;
        if (trans < 0.01) break;
    }

    // Aerial atmospheric perspective
    float aerial = 1.0 - exp(-entry * 0.000055);
    cloudSum = mix(cloudSum, background * (1.0 - trans), aerial);

    return background * trans + cloudSum;
    #endif
    #endif
    return background;
}

#endif

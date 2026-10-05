#ifndef AA_ATMOSPHERE
#define AA_ATMOSPHERE

// Fast 2D noise
float noise2D(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 skyRadiance(vec3 rd) {
    #ifdef NETHER
    return pow(fogColor, vec3(2.2)) * 0.6 + vec3(0.018, 0.003, 0.001);
    #elif defined(END)
    return mix(vec3(0.016, 0.009, 0.035), vec3(0.07, 0.035, 0.12), exp(-abs(rd.y) * 5.0));
    #else
    vec3 sd = sunDirection(); float day = daylight();
    float horizon = pow(1.0 - max(rd.y, 0.0), 3.5);
    vec3 zenithCol = vec3(0.06, 0.24, 0.72);
    vec3 horizonCol = vec3(0.48, 0.72, 0.94);
    vec3 sky = mix(zenithCol, horizonCol, horizon);
    float sunset = exp(-abs(sd.y) * 8.5);
    float facing = pow(sat(dot(rd, sd) * 0.5 + 0.5), 6.0);
    vec3 sunsetCol = vec3(1.35, 0.42, 0.08);
    sky = mix(sky, sunsetCol, sunset * horizon * (0.28 + facing * 0.72));
    sky *= mix(0.20, 1.0, smoothstep(-0.08, 0.25, sd.y));
    sky = mix(vec3(0.0018, 0.0035, 0.009) + vec3(0.008, 0.012, 0.024) * horizon, sky, day);
    sky = mix(sky, vec3(dot(sky, vec3(0.2126, 0.7152, 0.0722))) * 0.75, rainStrength * 0.8);
    float sunDot = dot(rd, sd), moonDot = dot(rd, -sd);
    #ifdef SUN_MOON_GLOW
    // ==================== [ REALISTIC PROCEDURAL SUN ] ====================
    if (day > 0.001) {
        float sunElev = smoothstep(-0.06, 0.35, sd.y);
        float sunsetFactor = 1.0 - sunElev;

        // Realistic celestial sun disc: ~0.77 deg (noon) to ~1.03 deg (sunset)
        float sunCos = mix(0.99991, 0.99984, sunsetFactor);
        float discEdge = 0.00008;
        float disc = smoothstep(sunCos - discEdge, sunCos, sunDot);

        if (disc > 0.0) {
            // Solar limb darkening: bright radiant core with soft golden rim
            float limb = sat((sunDot - (sunCos - discEdge)) / max(1.0 - (sunCos - discEdge), 0.00001));
            float coreBright = pow(limb, 0.50);

            vec3 noonCore = vec3(24.0, 22.0, 18.0);
            vec3 noonRim  = vec3(12.0, 9.5, 5.5);
            vec3 sunsetCore = vec3(18.0, 6.0, 1.2);
            vec3 sunsetRim  = vec3(8.0, 2.0, 0.3);

            vec3 coreCol = mix(noonCore, sunsetCore, sunsetFactor);
            vec3 rimCol  = mix(noonRim, sunsetRim, sunsetFactor);
            vec3 sunCol  = mix(rimCol, coreCol, coreBright);

            sky += sunCol * disc * day * (1.0 - rainStrength);
        }

        // --- Multi-layer Atmospheric Solar Corona & Mie Glow ---
        // 1. Delicate inner corona hugging the solar disc (~1.5 to 2.5 deg)
        float innerHalo = pow(sat(sunDot), 750.0);
        vec3 innerCol = mix(vec3(1.10, 0.90, 0.60), vec3(1.60, 0.65, 0.15), sunsetFactor);
        sky += innerCol * innerHalo * 0.85 * day * (1.0 - rainStrength);

        // 2. Soft atmospheric Mie scattering halo (~8 to 12 deg)
        float midHalo = pow(sat(sunDot), 80.0);
        vec3 midCol = mix(vec3(0.20, 0.17, 0.12), vec3(0.60, 0.22, 0.05), sunsetFactor);
        sky += midCol * midHalo * 0.50 * day * (1.0 - rainStrength * 0.75);

        // 3. Subtle optical diffraction flare / starburst spikes
        if (sunDot > 0.992) {
            vec3 sunUp = abs(sd.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
            vec3 sunRight = normalize(cross(sd, sunUp));
            vec3 sunRealUp = cross(sunRight, sd);
            vec2 sunUV = vec2(dot(rd, sunRight), dot(rd, sunRealUp));
            float angle = atan(sunUV.y, sunUV.x);
            float rays1 = sin(angle * 6.0) * 0.5 + 0.5;
            float rays2 = sin(angle * 10.0 + 1.25) * 0.5 + 0.5;
            float spikePattern = pow(rays1 * 0.60 + rays2 * 0.40, 2.0);
            float flareFade = smoothstep(0.992, 0.998, sunDot);
            float glare = pow(sat(sunDot), 300.0) * spikePattern * flareFade;
            sky += mix(vec3(0.8, 0.65, 0.4), vec3(1.2, 0.40, 0.08), sunsetFactor) * glare * 0.35 * day * (1.0 - rainStrength);
        }
    }

    // ==================== [ REALISTIC PROCEDURAL MOON ] ====================
    if (day < 0.95) {
        float moonCos = 0.99990;
        float discEdge = 0.00008;
        float disc = smoothstep(moonCos - discEdge, moonCos, moonDot);

        if (disc > 0.0) {
            // Lunar maria (procedural dark basaltic plains on the Moon surface)
            vec3 moonUp = abs(sd.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
            vec3 moonRight = normalize(cross(-sd, moonUp));
            vec3 moonRealUp = cross(moonRight, -sd);
            vec2 moonUV = vec2(dot(rd, moonRight), dot(rd, moonRealUp)) * 260.0;
            float mare = clamp(noise2D(moonUV) * 0.35 + 0.68, 0.42, 1.0);

            vec3 moonDiscColor = vec3(2.2, 2.5, 3.0) * mare;
            sky += moonDiscColor * disc * (1.0 - day) * (1.0 - rainStrength);
        }

        // Soft nocturnal atmospheric lunar halo
        float moonHalo = pow(sat(moonDot), 120.0) * 0.18;
        vec3 moonAura = vec3(0.03, 0.06, 0.12) * NIGHT_BRIGHTNESS * moonHalo;
        sky += moonAura * (1.0 - day) * (1.0 - rainStrength * 0.8);
    }
    #endif
    #ifdef STARS
    vec3 starCell = floor(rd * 650.0);
    sky += vec3(pow(hash13(starCell), 950.0)) * smoothstep(0.02, 0.3, rd.y) * (1.0 - day) * (1.0 - rainStrength) * 0.5;
    #endif
    return sky;
    #endif
}

// Rotated fractal noise: breaks grid alignment, producing organic fluid cloud shapes
const mat2 rotCloud = mat2(0.80, -0.60, 0.60, 0.80);

float cloudFractal(vec2 p) {
    vec2 pos = p;
    float n = noise2D(pos);
    pos = rotCloud * pos * 2.02;
    n += noise2D(pos) * 0.50;
    pos = rotCloud * pos * 2.03;
    n += noise2D(pos) * 0.25;
    pos = rotCloud * pos * 2.01;
    n += noise2D(pos) * 0.125;
    return n / 1.875;
}

// Natural elevated cumulus altitude (high above mountains & Distant Horizons terrain)
const float CLOUD_ALT_BASE = CLOUD_ALTITUDE;
const float CLOUD_ALT_THICK = 110.0;

// Organic, realistic 3D cumulus density field
float sampleCloudDensity(vec3 p, bool detail) {
    // Earth curvature compensation: prevents horizontal pancake distortion
    vec2 camDist = p.xz - cameraPosition.xz;
    float curvedY = p.y - dot(camDist, camDist) * 0.000008;

    float h = (curvedY - CLOUD_ALT_BASE) / CLOUD_ALT_THICK;
    if (h <= 0.0 || h >= 1.0) return 0.0;

    vec2 wind = vec2(frameTimeCounter * 1.2, frameTimeCounter * 0.5);
    vec2 pos2d = (p.xz + wind) * 0.0016;

    // Macro weather distribution: creates sunny clearings and cloud clusters
    float weather = noise2D(pos2d * 0.32 + vec2(0.2, 0.7));
    float coverage = CLOUD_COVERAGE * 0.75 + rainStrength * 0.25;

    float fbm = cloudFractal(pos2d);
    fbm += (weather - 0.5) * 0.18;

    // Natural cumulus profile:
    // Base threshold is low (wide flat condensation base at dew point)
    // Threshold increases smoothly with altitude h (narrows into rounded cauliflower lobes at top)
    float threshold = mix(0.44 - coverage * 0.18, 0.68 - coverage * 0.10, h);
    if (fbm < threshold - 0.04) return 0.0;

    float baseFade = smoothstep(0.0, 0.10, h);
    float topFade = 1.0 - smoothstep(0.85, 1.0, h);
    float density = smoothstep(threshold - 0.04, threshold + 0.16, fbm) * baseFade * topFade;

    // Subtle 3D fractal cauliflower billow texturing
    #ifdef CLOUD_DETAIL
    if (detail && density > 0.01) {
        vec3 q = (p + vec3(wind.x, 0.0, wind.y)) * 0.016;
        float n1 = noise3D(q);
        float n2 = noise3D(q * 2.3 + vec3(1.3, 2.1, 0.7));
        float fluff = n1 * 0.65 + n2 * 0.35;
        density = clamp(density - (1.0 - fluff) * 0.22 * smoothstep(0.08, 0.85, h), 0.0, 1.0);
    }
    #endif

    return density;
}

vec4 cloudLayer(vec3 rd, vec2 pixel) {
    #if CLOUDS == 2
    #if !defined(NETHER) && !defined(END)
    // Smooth horizon fade
    if (abs(rd.y) < 0.015) return vec4(0.0);
    float horizonFade = smoothstep(0.015, 0.08, abs(rd.y));

    float a = (CLOUD_ALT_BASE - cameraPosition.y) / rd.y;
    float b = (CLOUD_ALT_BASE + CLOUD_ALT_THICK - cameraPosition.y) / rd.y;
    float entry = max(min(a, b), 0.0);
    float leave = max(a, b);
    if (leave <= entry) return vec4(0.0);

    // Clamp raymarching depth: avoids distant step stretching
    float maxRayDist = min(leave - entry, 2400.0);
    float distFade = 1.0 - smoothstep(2200.0, 4200.0, entry);
    float fadeWeight = horizonFade * distFade;
    if (fadeWeight <= 0.001) return vec4(0.0);

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
        if(t>leave) break;
        vec3 p = cameraPosition + rd * t;
        float density = sampleCloudDensity(p, true);
        if (density > 0.003) {
            // Shadow raymarch towards light source
            vec3 ld = (day > 0.05) ? sd : md;
            float opt1 = sampleCloudDensity(p + ld * 12.0, false);
            float opt2 = sampleCloudDensity(p + ld * 36.0, false);
            float optical = opt1 * 26.0 + opt2 * 52.0;

            // Powder sugar multiple scattering effect
            float powder = 1.0 - exp(-optical * 0.60);
            float directShade = exp(-optical * 0.11) * (0.75 + powder * 0.45);

            // Realistic atmospheric ambient:
            // Day: cool sky blue from above + warm ground bounce from below (creates deep 3D shading)
            // Night: dark silhouette matching starry sky
            float hRel = sat((p.y - CLOUD_ALT_BASE) / CLOUD_ALT_THICK);
            vec3 skyAmbient = vec3(0.22, 0.34, 0.50) * (0.30 + hRel * 0.70);
            vec3 groundBounce = vec3(0.16, 0.15, 0.12) * (0.80 - hRel * 0.50);
            vec3 dayAmbient = (skyAmbient + groundBounce) * (0.45 + 0.55 * exp(-density * 2.5));
            vec3 nightAmbient = vec3(0.0004, 0.0007, 0.0016) * NIGHT_BRIGHTNESS;
            vec3 ambient = mix(nightAmbient, dayAmbient, day);

            // Direct light: bright sunlit highlight vs soft moonlight rim
            vec3 dayDirect = sunCol * (directShade * phase + 0.04 * exp(-optical * 0.022));
            vec3 nightDirect = moonColor * (directShade * (0.03 + moonMie));
            vec3 directLight = mix(nightDirect, dayDirect, day);

            vec3 light = ambient + directLight;

            float opacity = 1.0 - exp(-density * stepLen * 0.07);
            cloudSum += trans * light * opacity;
            trans *= (1.0 - opacity);
            t += stepLen;
        } else {
            t += stepLen * 1.6;
        }
        if (trans < 0.015) break;
    }

    float visibility = exp(-entry * 0.0010) * fadeWeight;
    return vec4(cloudSum, 1.0 - trans) * visibility;
    #endif
    #endif
    return vec4(0.0);
}

vec3 renderClouds(vec3 rd, vec3 background, vec2 pixel) {
    vec4 layer = cloudLayer(rd, pixel);
    return background * (1.0 - layer.a) + layer.rgb;
}

vec3 renderFastClouds(vec3 rd, vec3 background) {
    #if !defined(NETHER) && !defined(END)
    if (rd.y < 0.02) return background;
    float planeDist = (CLOUD_ALTITUDE - cameraPosition.y) / max(rd.y, 0.02);
    if (planeDist < 0.0) return background;
    vec2 wind = vec2(frameTimeCounter * 1.2, frameTimeCounter * 0.5);
    vec2 pos = (cameraPosition.xz + rd.xz * planeDist + wind) * 0.00030;
    float fbm = cloudFractal(pos);
    float threshold = 0.54 - CLOUD_COVERAGE * 0.22;
    float density = smoothstep(threshold, threshold + 0.16, fbm);
    if (density > 0.005) {
        vec3 sd = sunDirection();
        float day = daylight();
        vec3 sunCol = lightColor();

        // Pseudo-volumetric self-shadowing: sample slightly towards the sun
        float fbmSun = cloudFractal(pos + sd.xz * 0.012);
        float shade = clamp(1.0 - (fbmSun - threshold) * 2.4, 0.42, 1.0);

        // Forward Mie scattering (silver lining highlight facing sun)
        float sunTheta = dot(rd, sd);
        float silver = pow(sat(sunTheta * 0.5 + 0.5), 10.0) * 1.6 * day;

        // Realistic ambient: soft blue from sky + warm sunlight bounce
        vec3 ambientCloud = mix(vec3(0.012, 0.018, 0.035) * NIGHT_BRIGHTNESS, vec3(0.70, 0.78, 0.90), day);
        vec3 directCloud = (sunCol * 0.40 + silver * sunCol) * shade;
        vec3 cloudCol = ambientCloud + directCloud;

        // Sunset horizon golden glow
        float horizon = pow(1.0 - max(rd.y, 0.0), 3.0);
        float sunset = exp(-abs(sd.y) * 8.0) * horizon;
        cloudCol = mix(cloudCol, vec3(1.15, 0.45, 0.12), sunset * 0.70);

        // Horizon distance fade
        float fade = smoothstep(0.02, 0.12, rd.y) * (1.0 - smoothstep(1200.0, 3600.0, planeDist));
        return mix(background, cloudCol, min(density * fade, 0.90));
    }
    #endif
    return background;
}

#endif

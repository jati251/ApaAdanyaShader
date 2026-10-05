#ifndef AA_COLOR_GRADING
#define AA_COLOR_GRADING

// =============================================================================
// Tonemapping Operators
// =============================================================================

// 0: ACES Filmic (Narkowicz 2015 fit with luminance balance)
vec3 tonemapACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    vec3 filmRGB = clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
    float lumaIn = dot(x, vec3(0.2126, 0.7152, 0.0722));
    float lumaOut = (lumaIn * (a * lumaIn + b)) / (lumaIn * (c * lumaIn + d) + e);
    vec3 filmLuma = x * (clamp(lumaOut, 0.0, 1.0) / max(lumaIn, 0.0001));
    return mix(filmRGB, filmLuma, 0.45);
}

// 1: AgX (Modern standard: preserves highlight hues without clipping to yellow/magenta)
vec3 tonemapAgX(vec3 c) {
    const mat3 agxIn = mat3(
        0.842479062223, 0.078433599999, 0.079223745147,
        0.042328242261, 0.878468636492, 0.079166127460,
        0.042375654905, 0.078433600000, 0.879142973793
    );
    vec3 val = max(c * agxIn, vec3(1e-5));
    vec3 logVal = clamp((log2(val) + 10.0) / 16.5, 0.0, 1.0);
    vec3 sCurve = logVal * logVal * (3.0 - 2.0 * logVal);
    float luma = dot(sCurve, vec3(0.2126, 0.7152, 0.0722));
    float highlight = smoothstep(0.7, 1.0, luma);
    return mix(sCurve, vec3(luma), highlight * 0.40);
}

// 2: Khronos PBR Neutral (True color fidelity, minimal tint distortion)
vec3 tonemapKhronos(vec3 c) {
    const float startCompression = 0.75;
    const float desaturation = 0.15;
    float x = min(c.r, min(c.g, c.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    c -= offset;
    float peak = max(c.r, max(c.g, c.b));
    if (peak < startCompression) return max(c, vec3(0.0));
    float d = 1.0 - startCompression;
    float newPeak = 1.0 - d * d / (peak + d - startCompression);
    c *= newPeak / max(peak, 0.0001);
    float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
    return max(mix(c, vec3(newPeak), g), vec3(0.0));
}

// 3: Uncharted 2 / Hable Filmic
vec3 hablePartial(vec3 x) {
    const float A = 0.15, B = 0.50, C = 0.10, D = 0.20, E = 0.02, F = 0.30;
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}
vec3 tonemapHable(vec3 x) {
    const float W = 11.2;
    vec3 curr = hablePartial(x * 1.8);
    vec3 whiteScale = 1.0 / hablePartial(vec3(W));
    return curr * whiteScale;
}

// 4: Reinhard-Jodie (Smooth luminance-preserving roll-off)
vec3 tonemapReinhardJodie(vec3 c) {
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    vec3 tv = c / (1.0 + c);
    return mix(c / (1.0 + l), tv, tv);
}

// 5: Linear (Clipped)
vec3 tonemapLinear(vec3 c) {
    return clamp(c, 0.0, 1.0);
}

// =============================================================================
// Color Grading Profiles (Presets / Variants)
// =============================================================================

vec3 applyColorProfile(vec3 c) {
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));

    #if COLOR_PROFILE == 1
    // --- Profile 1: Vibrant Fantasy ---
    // Punchy colors, saturated foliage greens, rich skies, golden warmth
    vec3 satBoost = max(mix(vec3(luma), c, 1.25),vec3(0.0));
    satBoost.r = pow(satBoost.r, 0.95) * 1.04;
    satBoost.g = pow(satBoost.g, 0.94) * 1.05;
    satBoost.b = pow(satBoost.b, 0.97) * 1.02;
    satBoost += vec3(0.02, 0.015, 0.0) * (1.0 - abs(luma - 0.5) * 2.0);
    return clamp(satBoost, 0.0, 1.0);

    #elif COLOR_PROFILE == 2
    // --- Profile 2: Cinematic Teal & Orange ---
    // Deep teal shadows, warm bronze/orange skin/highlights, filmic tone
    float shadowMask = 1.0 - smoothstep(0.0, 0.65, luma);
    float highlightMask = smoothstep(0.35, 1.0, luma);
    c += vec3(-0.03, 0.02, 0.07) * shadowMask * 0.75;
    c += vec3(0.07, 0.03, -0.04) * highlightMask * 0.70;
    c = mix(vec3(luma), c, 1.08);
    return clamp(c, 0.0, 1.0);

    #elif COLOR_PROFILE == 3
    // --- Profile 3: Golden Hour / Warm Sunset ---
    // Soft romantic warmth, peachy highlights, rich amber glow
    c.r = pow(c.r, 0.92) * 1.08;
    c.g = pow(c.g, 0.96) * 1.02;
    c.b = pow(c.b, 1.06) * 0.90;
    c += vec3(0.04, 0.02, -0.01) * smoothstep(0.1, 0.8, luma);
    return clamp(c, 0.0, 1.0);

    #elif COLOR_PROFILE == 4
    // --- Profile 4: Cold Nordic / Boreal ---
    // Chilly cyan-blue cast, desaturated organic tones, high atmosphere
    c.r = pow(c.r, 1.05) * 0.92;
    c.g = pow(c.g, 0.99) * 0.98;
    c.b = pow(c.b, 0.92) * 1.10;
    c = mix(vec3(luma), c, 0.88);
    c += vec3(-0.02, 0.01, 0.05) * (1.0 - luma);
    return clamp(c, 0.0, 1.0);

    #elif COLOR_PROFILE == 5
    // --- Profile 5: Retro 35mm Analog Film ---
    // Raised crushed blacks (faded toe), subtle nostalgic warm fade, gentle highlights
    c = mix(vec3(0.035, 0.03, 0.04), c, 0.92);
    c.r = pow(c.r, 0.96) * 1.03;
    c.b = pow(c.b, 1.03) * 0.95;
    c = mix(vec3(luma), c, 0.95);
    return clamp(c, 0.0, 1.0);

    #elif COLOR_PROFILE == 6
    // --- Profile 6: Bleach Bypass / Gritty Dark Fantasy ---
    // High contrast, silver desaturated midtones, intense hard shadows
    vec3 sCurve = c * c * (3.0 - 2.0 * c);
    vec3 desat = vec3(luma);
    c = mix(c, desat, 0.42);
    c = mix(c, sCurve, 0.65);
    return clamp(c, 0.0, 1.0);

    #elif COLOR_PROFILE == 7
    // --- Profile 7: Cyberpunk / Electric Night ---
    // Deep indigo shadows with vibrant electric magenta and cyan highlights
    float shadow = 1.0 - smoothstep(0.0, 0.5, luma);
    float bright = smoothstep(0.5, 1.0, luma);
    c += vec3(0.02, -0.02, 0.06) * shadow;
    c += vec3(0.08, -0.01, 0.05) * bright * 0.6;
    c = mix(vec3(luma), c, 1.20);
    return clamp(c, 0.0, 1.0);

    #else
    // --- Profile 0: Standard / Natural ---
    return c;
    #endif
}

// =============================================================================
// White Balance (Color Temperature & Tint)
// =============================================================================

vec3 applyWhiteBalance(vec3 c, float temp, float tint) {
    vec3 tempScale = vec3(
        1.0 + temp * 0.15,
        1.0 + temp * 0.03 - abs(tint) * 0.05,
        1.0 - temp * 0.18
    );
    vec3 tintScale = vec3(
        1.0 + tint * 0.08,
        1.0 - tint * 0.12,
        1.0 + tint * 0.08
    );
    return max(c * tempScale * tintScale, vec3(0.0));
}

// =============================================================================
// Smart Vibrance & Saturation
// =============================================================================

vec3 applyVibranceSaturation(vec3 c, float sat, float vib) {
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float currentSat = maxC - minC;

    // Vibrance selectively boosts muted colors without oversaturating already vibrant blocks
    if (vib != 0.0) {
        float vibFactor = (1.0 - currentSat) * vib;
        c = mix(vec3(luma), c, 1.0 + vibFactor);
    }

    // Global saturation
    if (sat != 1.0) {
        c = mix(vec3(luma), c, sat);
    }

    return clamp(c, 0.0, 1.0);
}

// =============================================================================
// Master Color Grading Entry Point
// =============================================================================

vec3 applyColorGrading(vec3 hdrColor, vec2 uv) {
    // 1. Dynamic Camera Exposure
    float exposure = EXPOSURE * mix(1.15, 0.90, daylight());
    vec3 scaledColor = hdrColor * exposure;

    // 2. White Balance in Linear HDR space
    #if defined(COLOR_TEMPERATURE) || defined(COLOR_TINT)
    scaledColor = applyWhiteBalance(scaledColor, COLOR_TEMPERATURE, COLOR_TINT);
    #endif

    // 3. Tonemapping Operator (HDR -> Display SDR)
    vec3 sdr;
    #if TONEMAP_OPERATOR == 0
    sdr = tonemapACES(scaledColor);
    #elif TONEMAP_OPERATOR == 1
    sdr = tonemapAgX(scaledColor);
    #elif TONEMAP_OPERATOR == 2
    sdr = tonemapKhronos(scaledColor);
    #elif TONEMAP_OPERATOR == 3
    sdr = tonemapHable(scaledColor);
    #elif TONEMAP_OPERATOR == 4
    sdr = tonemapReinhardJodie(scaledColor);
    #else
    sdr = tonemapLinear(scaledColor);
    #endif

    // Gamma correction to standard gamma 2.2 (AgX already includes internal display curve)
    #if TONEMAP_OPERATOR != 1
    sdr = pow(clamp(sdr, 0.0, 1.0), vec3(1.0 / 2.2));
    #endif

    // 4. Stylized Color Grading Profile / Variant
    sdr = applyColorProfile(sdr);

    // 5. Smart Vibrance & Global Saturation
    sdr = applyVibranceSaturation(sdr, COLOR_SATURATION, COLOR_VIBRANCE);

    // 6. Contrast S-Curve
    if (COLOR_CONTRAST != 1.0) {
        vec3 sCurve = sdr * sdr * (3.0 - 2.0 * sdr);
        sdr = clamp(mix(sdr, sCurve, COLOR_CONTRAST - 1.0), 0.0, 1.0);
    }

    // 7. Natural Lens Vignette
    #ifdef VIGNETTE
    vec2 vigUV = uv * (1.0 - uv.yx);
    float vig = vigUV.x * vigUV.y * 15.0;
    sdr *= clamp(pow(vig, VIGNETTE_STRENGTH), 0.0, 1.0);
    #endif

    return sdr;
}

#endif // AA_COLOR_GRADING

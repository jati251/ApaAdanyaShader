#ifndef AA_COLOR_GRADING
#define AA_COLOR_GRADING
#ifdef AUTO_EXPOSURE
uniform sampler2D colortex16;
#endif

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
    const float startCompression = 0.76;
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
    #ifdef AUTO_EXPOSURE
    float measured=texelFetch(colortex16,ivec2(0),0).r;
    if(measured>=0.35 && measured<=3.0) exposure=EXPOSURE*measured;
    #endif
    vec3 scaledColor = hdrColor * exposure;

    // 2. White Balance in Linear HDR space
#if (defined(COLOR_TEMPERATURE) || defined(COLOR_TINT))
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

    // Scene/display sRGB transfer (AgX-style already contains a display curve)
#if TONEMAP_OPERATOR != 1
    sdr = linearToSrgb(sdr);
    #endif

    // 4. Stylized Color Grading Profile / Variant
    

    // 5. Smart Vibrance & Global Saturation
    sdr = applyVibranceSaturation(sdr, COLOR_SATURATION, COLOR_VIBRANCE);

    // 6. Contrast S-Curve
    if (COLOR_CONTRAST != 1.0) {
        vec3 sCurve = sdr * sdr * (3.0 - 2.0 * sdr);
        sdr = clamp(mix(sdr, sCurve, COLOR_CONTRAST - 1.0), 0.0, 1.0);
    }

    #ifdef AUTO_EXPOSURE
    // Scotopic human rod vision shift: subtle desaturation of deep dark tones in pitch black environments
    float measuredDark = texelFetch(colortex16, ivec2(0), 0).r;
    if(measuredDark > 1.8) {
        float scotopicWeight = smoothstep(1.8, 2.9, measuredDark);
        float luma = dot(sdr, vec3(0.2126, 0.7152, 0.0722));
        vec3 rodTone = vec3(luma * 0.93, luma * 0.97, luma * 1.06);
        sdr = mix(sdr, rodTone, scotopicWeight * 0.22 * (1.0 - smoothstep(0.04, 0.40, luma)));
    }
    #endif

    // 7. Natural Lens Vignette

    return sdr;
}

#endif // AA_COLOR_GRADING

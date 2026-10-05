#ifndef AA_TAA
#define AA_TAA

#ifdef TAA

uniform sampler2D colortex13;

#ifndef DEPTH_COLORTEX2_DECLARED
#define DEPTH_COLORTEX2_DECLARED
uniform sampler2D depthtex0, colortex2;
#endif

uniform mat4 gbufferPreviousModelView, gbufferPreviousProjection;
uniform vec3 previousCameraPosition;

#if defined(DISTANT_HORIZONS) && !defined(DH_PROJECTION_INVERSE_DECLARED)
#define DH_PROJECTION_INVERSE_DECLARED
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif

vec3 applyTAA(vec2 uv, vec3 currentRGB) {
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);
    vec2 edgeMargin = px * 4.0;

    // 1. Initial safety guards: startup, pauses, large teleports
    if (frameCounter < 2 || frameTime <= 0.0 || frameTime > 0.2) {
        return currentRGB;
    }
    vec3 camDelta = cameraPosition - previousCameraPosition;
    if (dot(camDelta, camDelta) > 4.0) {
        return currentRGB;
    }

    // 2. Hand rejection: first-person hand & held items NEVER blend with history (0% ghosting)
    float depth = texture(depthtex0, uv).r;
    if (depth < 0.56 && texture(colortex2, uv).a > 0.5) {
        return currentRGB;
    }

    // 3. Fast reprojection to previous frame
    mat4 prevViewProj = gbufferPreviousProjection * gbufferPreviousModelView;
    mat4 reprojMatrix = prevViewProj * gbufferModelViewInverse;
    vec4 camTranslationClip = prevViewProj * vec4(camDelta, 0.0);

    bool isSky = false;
    vec3 viewPos;
    if (depth >= 0.999999) {
        #ifdef DISTANT_HORIZONS
        float dh = texture(dhDepthTex0, uv).r;
        if (dh < 0.999999) {
            vec4 p = dhProjectionInverse * vec4(uv * 2.0 - 1.0, dh * 2.0 - 1.0, 1.0);
            viewPos = p.xyz / p.w;
        } else
        #endif
        {
            isSky = true;
            vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
            viewPos = normalize(p.xyz / p.w) * (far * 0.5);
        }
    } else {
        vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
        viewPos = p.xyz / p.w;
    }

    vec4 prevClip = reprojMatrix * vec4(viewPos, 1.0) + (isSky ? vec4(0.0) : camTranslationClip);
    if (prevClip.w <= 0.0) {
        return currentRGB;
    }

    vec2 historyUV = prevClip.xy / prevClip.w * 0.5 + 0.5;

    // 4. Strict screen boundary check: prevent white borders at screen edges
    if (historyUV.x <= edgeMargin.x || historyUV.x >= 1.0 - edgeMargin.x ||
        historyUV.y <= edgeMargin.y || historyUV.y >= 1.0 - edgeMargin.y) {
        return currentRGB;
    }

    // 5. Motion gate: on camera or player movement, immediately drop history
    // In Hybrid mode (no camera jitter), temporal accumulation is exclusively for
    // stabilizing static views and subtle shimmering. Movement uses pure current frame + FXAA.
    vec2 pixelVelocity = (uv - historyUV) * vec2(viewWidth, viewHeight);
    float motionLen = length(pixelVelocity);

    // If pixel moved more than 0.25 pixels, completely bypass history to eliminate ghosting
    if (motionLen > 0.25) {
        return currentRGB;
    }

    // 6. Sample history buffer with safe clamped coordinates
    vec2 clampedUV = clamp(historyUV, edgeMargin, 1.0 - edgeMargin);
    vec3 historyColor = texture(colortex13, clampedUV).rgb;

    // 7. Strict color delta validation: reject history if color shifted (e.g. moving entity or foliage)
    vec3 colDiff = abs(historyColor - currentRGB);
    float maxDiff = max(colDiff.r, max(colDiff.g, colDiff.b));
    if (maxDiff > 0.08) {
        return currentRGB;
    }

    // 8. Static temporal stabilization blend
    float motionFade = smoothstep(0.25, 0.0, motionLen);
    float blend = TAA_BLEND * motionFade;

    // Anti-flicker Karis luma weighting
    float lumaCurr = dot(currentRGB, vec3(0.2126, 0.7152, 0.0722));
    float lumaHist = dot(historyColor, vec3(0.2126, 0.7152, 0.0722));
    float wCurr = 1.0 / (1.0 + lumaCurr);
    float wHist = 1.0 / (1.0 + lumaHist);

    float denom = wCurr * (1.0 - blend) + wHist * blend;
    vec3 resolved = (currentRGB * wCurr * (1.0 - blend) + historyColor * wHist * blend) / max(denom, 0.0001);

    // 9. Crisp contrast sharpening
    #ifdef TAA_SHARPENING
    vec3 n = texture(colortex13, clamp(uv + vec2(0.0, px.y), edgeMargin, 1.0 - edgeMargin)).rgb;
    vec3 s = texture(colortex13, clamp(uv - vec2(0.0, px.y), edgeMargin, 1.0 - edgeMargin)).rgb;
    vec3 e = texture(colortex13, clamp(uv + vec2(px.x, 0.0), edgeMargin, 1.0 - edgeMargin)).rgb;
    vec3 w = texture(colortex13, clamp(uv - vec2(px.x, 0.0), edgeMargin, 1.0 - edgeMargin)).rgb;
    vec3 crossBlur = (n + s + e + w) * 0.25;
    resolved = clamp(resolved + (resolved - crossBlur) * (TAA_SHARPEN_STRENGTH * 0.35), 0.0, 1.0);
    #endif

    return clamp(resolved, 0.0, 1.0);
}

#endif // TAA
#endif // AA_TAA

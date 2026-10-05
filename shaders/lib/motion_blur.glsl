#ifndef AA_MOTION_BLUR
#define AA_MOTION_BLUR

#ifdef MOTION_BLUR

uniform sampler2D depthtex0;
uniform sampler2D colortex2;
uniform mat4 gbufferPreviousModelView, gbufferPreviousProjection;
uniform vec3 previousCameraPosition;

#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif

// Fast view-position reconstruction for terrain, Distant Horizons, and sky
vec3 getViewPos(vec2 uv, float depth, out bool isSky) {
    isSky = false;
    if (depth >= 0.999999) {
        #ifdef DISTANT_HORIZONS
        float dh = texture(dhDepthTex0, uv).r;
        if (dh < 0.999999) {
            vec4 p = dhProjectionInverse * vec4(uv * 2.0 - 1.0, dh * 2.0 - 1.0, 1.0);
            return p.xyz / p.w;
        }
        #endif
        isSky = true;
        vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
        return normalize(p.xyz / p.w) * (far * 0.5);
    }
    vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return p.xyz / p.w;
}

vec3 applyMotionBlur(vec2 uv, vec3 currentRGB) {
    // -------------------------------------------------------------
    // Latency Gate 1: Global Movement Guard (Uniform-only cost)
    // When the camera is stationary, exit immediately with 0 texture
    // lookups and 0 ALU work across the entire screen.
    // -------------------------------------------------------------
    vec3 camDelta = cameraPosition - previousCameraPosition;
    float camMoveSq = dot(camDelta, camDelta);
    float rotDelta = abs(gbufferModelView[0][0] - gbufferPreviousModelView[0][0]) +
                     abs(gbufferModelView[1][1] - gbufferPreviousModelView[1][1]) +
                     abs(gbufferModelView[2][2] - gbufferPreviousModelView[2][2]) +
                     abs(gbufferModelView[0][1] - gbufferPreviousModelView[0][1]) +
                     abs(gbufferModelView[1][0] - gbufferPreviousModelView[1][0]);

    if (camMoveSq < 0.000001 && rotDelta < 0.000005) {
        return currentRGB;
    }

    // Safety checks: startup frames, lag spikes, teleports, and FOV snaps
    if (frameCounter < 2 || frameTime <= 0.0 || frameTime > 0.2 || camMoveSq > 256.0) {
        return currentRGB;
    }
    if (abs(gbufferProjection[1][1] - gbufferPreviousProjection[1][1]) > 0.05) {
        return currentRGB;
    }

    // -------------------------------------------------------------
    // Latency Gate 2: First-Person Hand & Held Item Check
    // Keep held items 100% crisp without blurring or dragging trails
    // -------------------------------------------------------------
    float depth = texture(depthtex0, uv).r;
    #ifndef MOTION_BLUR_HAND
    if (depth < 0.56 && texture(colortex2, uv).a > 0.5) {
        return currentRGB;
    }
    #endif

    // -------------------------------------------------------------
    // Optimized Fast Reprojection (Algebraically Combined Matrix)
    // Collapses 4 separate matrix-vector multiplications into 1
    // -------------------------------------------------------------
    mat4 prevViewProj = gbufferPreviousProjection * gbufferPreviousModelView;
    mat4 reprojMatrix = prevViewProj * gbufferModelViewInverse;
    vec4 camTranslationClip = prevViewProj * vec4(camDelta, 0.0);

    bool isSky;
    vec3 viewPos = getViewPos(uv, depth, isSky);
    vec4 prevClip = reprojMatrix * vec4(viewPos, 1.0) + (isSky ? vec4(0.0) : camTranslationClip);

    if (prevClip.w <= 0.0) {
        return currentRGB;
    }

    vec2 prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
    vec2 velocity = uv - prevUV;

    // Frame-rate independence: normalized to 60 FPS reference
    float timeFactor = clamp(0.0166667 / max(frameTime, 0.001), 0.25, 3.0);
    velocity *= MOTION_BLUR_STRENGTH * timeFactor;

    // -------------------------------------------------------------
    // Latency Gate 3: Per-Pixel Motion Magnitude Threshold
    // Skip accumulation loop if displacement is sub-pixel or imperceptible
    // -------------------------------------------------------------
    float speed = length(velocity);
    if (speed < 0.0004) {
        return currentRGB;
    }

    // Clamp maximum blur radius
    #ifdef MOTION_BLUR_LOW_LATENCY
    const float maxSpeed = 0.035;
    const int SAMPLES = 5;
    #else
    const float maxSpeed = 0.06;
    const int SAMPLES = MOTION_BLUR_SAMPLES;
    #endif

    if (speed > maxSpeed) {
        velocity *= maxSpeed / speed;
    }

    // Interleaved gradient noise for spatial/temporal dither
    float dither = ignDither(gl_FragCoord.xy);

    // -------------------------------------------------------------
    // Fast Accumulation Loop (Single-cycle ALU, 1 texture fetch per tap)
    // -------------------------------------------------------------
    vec3 sum = vec3(0.0);
    float totalWeight = 0.0;

    for (int i = 0; i < SAMPLES; i++) {
        float offset = ((float(i) + dither) / float(SAMPLES)) - 0.5;
        vec2 sampleUV = uv + velocity * offset;

        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) {
            continue;
        }

        vec3 tap = texture(colortex0, sampleUV).rgb;

        // Fast gamma 2.0 linear approximation (single-cycle multiply instead of pow)
        vec3 linearTap = tap * tap;

        float weight = 1.0 - abs(offset) * 0.6;
        sum += linearTap * weight;
        totalWeight += weight;
    }

    if (totalWeight < 0.001) {
        return currentRGB;
    }

    // Fast linear to gamma reconstruction
    return sqrt(max(sum / totalWeight, vec3(0.0)));
}

#endif // MOTION_BLUR
#endif // AA_MOTION_BLUR

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
        float dh = depthScreen(dhDepthTex0, uv);
        if (dh < 0.999999) {
            vec4 p = dhProjectionInverse * vec4(uv * 2.0 - 1.0, dh * 2.0 - 1.0, 1.0);
            return p.xyz / p.w;
        }
        #endif
        isSky = true;
        vec4 p = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
        return normalize(p.xyz / p.w);
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
    float depth = depthScreen(depthtex0, uv);
    #ifndef MOTION_BLUR_HAND
    if (depth < 0.56 && textureScreen(colortex2, uv).a > 0.5) {
        return currentRGB;
    }
    #endif

    // -------------------------------------------------------------
    // Optimized Fast Reprojection (Algebraically Combined Matrix)
    // Collapses 4 separate matrix-vector multiplications into 1
    // -------------------------------------------------------------
    bool isSky;
    vec3 viewPos = getViewPos(uv, depth, isSky);
    vec4 relWorld = isSky ? vec4(mat3(gbufferModelViewInverse)*viewPos,0.0)
                         : gbufferModelViewInverse * vec4(viewPos, 1.0);
    if (!isSky) relWorld.xyz += camDelta;
    vec4 prevClip = gbufferPreviousProjection * (gbufferPreviousModelView * relWorld);

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
    vec3 sum = currentRGB*currentRGB;
    float totalWeight = 1.0;
    vec2 margin=0.5/vec2(viewWidth,viewHeight);
    ivec2 sceneSize=screenTextureSize(colortex0);
    ivec2 depthSize=screenTextureSize(depthtex0);

    for (int i = 0; i < SAMPLES; i++) {
        float offset = ((float(i) + dither) / float(SAMPLES)) - 0.5;
        vec2 sampleUV = uv + velocity * offset;

        if (any(lessThan(sampleUV,margin)) || any(greaterThan(sampleUV,1.0-margin))) {
            continue;
        }

        float tapDepth=depthScreen(depthtex0,sampleUV,depthSize);
        #ifndef MOTION_BLUR_HAND
        if(tapDepth<0.56 && textureScreen(colortex2,sampleUV).a>0.5) continue;
        #endif
        bool tapSky;
        vec3 tapPos=getViewPos(sampleUV,tapDepth,tapSky);
        // Prevent bright background/sky trails across dark terrain silhouettes.
        if(tapSky!=isSky) continue;
        float depthWeight=isSky?1.0:1.0-smoothstep(0.04,0.20,
            abs(tapPos.z-viewPos.z)/max(-viewPos.z,1.0));
        if(depthWeight<0.001) continue;
        // Match the validated depth texel; bilinear color could still borrow bright sky.
        vec3 tap = texelFetch(colortex0,clamp(ivec2(sampleUV*vec2(sceneSize)),ivec2(0),sceneSize-1),0).rgb;

        // Fast gamma 2.0 linear approximation (single-cycle multiply instead of pow)
        vec3 linearTap = tap * tap;

        float weight = (1.0 - abs(offset) * 0.6)*depthWeight;
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

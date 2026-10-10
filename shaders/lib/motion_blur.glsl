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

// Tap rejection only needs view-space Z, not a full position/sky direction.
float blurTapViewZ(vec2 uv,float depth,out bool isSky) {
    isSky=depth>=0.999999;
    vec4 clip=vec4(uv*2.0-1.0,depth*2.0-1.0,1.0);
    mat4 inverseProjection=gbufferProjectionInverse;
    #ifdef DISTANT_HORIZONS
    if(isSky) {
        float dh=depthScreen(dhDepthTex0,uv);
        if(dh<0.999999) {
            isSky=false;clip.z=dh*2.0-1.0;inverseProjection=dhProjectionInverse;
        }
    }
    #endif
    if(isSky) return 0.0;
    vec4 rowZ=vec4(inverseProjection[0][2],inverseProjection[1][2],inverseProjection[2][2],inverseProjection[3][2]);
    vec4 rowW=vec4(inverseProjection[0][3],inverseProjection[1][3],inverseProjection[2][3],inverseProjection[3][3]);
    return dot(rowZ,clip)/dot(rowW,clip);
}

vec3 applyMotionBlur(vec2 uv, vec3 currentRGB) {
    // Uniform camera guard: exit before sampling any screen texture.
    vec3 camDelta=cameraPosition-previousCameraPosition;
    float camMoveSq=dot(camDelta,camDelta);
    vec3 r0=gbufferModelView[0].xyz-gbufferPreviousModelView[0].xyz;
    vec3 r1=gbufferModelView[1].xyz-gbufferPreviousModelView[1].xyz;
    vec3 r2=gbufferModelView[2].xyz-gbufferPreviousModelView[2].xyz;
    float rotationSq=dot(r0,r0)+dot(r1,r1)+dot(r2,r2);
    if(camMoveSq<0.000001 && rotationSq<0.0000000001) return currentRGB;

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
    float materialMask = textureScreen(colortex2, uv).a;
    // Water's animated reflection/refraction does not share the mesh velocity.
    // Camera-only blur drags the pattern during a jump, then snaps it back.
    if(materialMask>0.20 && materialMask<0.30) return currentRGB;
    if (depth < 0.56 && materialMask > 0.5) {
        return currentRGB;
    }

    // -------------------------------------------------------------
    // Center reprojection
    // Reconstruct only once for the center; sky ignores camera translation.
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
    velocity *= 0.50 * timeFactor;

    // Work in pixels so the threshold/radius are stable across aspect ratios.
    float speed=length(velocity*vec2(viewWidth,viewHeight));
    if(speed<0.75) return currentRGB;
    velocity*=min(1.0,24.0/max(speed,0.001));
    // Two balanced taps plus the existing center. A fixed kernel removes
    // post-TAA dither shimmer as well as the four-tap fast-motion path.
    const int MAX_TAPS=2;

    // -------------------------------------------------------------
    // Bounded accumulation: reject depth/mask before fetching tap color.
    // -------------------------------------------------------------
    vec3 sum = currentRGB*currentRGB;
    float totalWeight = 1.0;
    vec2 margin=0.5/vec2(viewWidth,viewHeight);
    ivec2 sceneSize=screenTextureSize(colortex0);
    ivec2 depthSize=screenTextureSize(depthtex0);

    for (int i = 0; i < MAX_TAPS; i++) {
        // Gauss nodes for the [-0.5,0.5] shutter interval, with equal weights.
        float offset = (float(i)-0.5)*0.577350269;
        vec2 sampleUV = uv + velocity * offset;

        if (any(lessThan(sampleUV,margin)) || any(greaterThan(sampleUV,1.0-margin))) {
            continue;
        }

        float tapDepth=depthScreen(depthtex0,sampleUV,depthSize);
        float tapMask=textureScreen(colortex2,sampleUV).a;
        if(tapMask>0.20 && tapMask<0.30) continue;
        if(tapDepth<0.56 && tapMask>0.5) continue;
        bool tapSky;
        float tapZ=blurTapViewZ(sampleUV,tapDepth,tapSky);
        // Prevent bright background/sky trails across dark terrain silhouettes.
        if(tapSky!=isSky) continue;
        float depthWeight=isSky?1.0:1.0-smoothstep(0.04,0.20,
            abs(tapZ-viewPos.z)/max(-viewPos.z,1.0));
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

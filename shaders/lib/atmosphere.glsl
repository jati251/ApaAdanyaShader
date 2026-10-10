#ifndef AA_ATMOSPHERE
#define AA_ATMOSPHERE
float clearAirOpticalDepth(float dist,float altitude) {
    float heightFactor=clamp(exp(-max(altitude-110.0,0.0)*0.003),0.55,1.0);
    return pow(max(dist-12.0,0.0)*0.00045*FOG_DENSITY,1.25)*heightFactor;
}


vec3 atmosphereBackground(vec3 rd) {
    #ifdef NETHER
    return pow(fogColor, vec3(2.2)) * 0.6 + vec3(0.018, 0.003, 0.001);
    #elif defined(END)
    return mix(vec3(0.016, 0.009, 0.035), vec3(0.07, 0.035, 0.12), exp(-abs(rd.y) * 5.0));
    #else
    vec3 sd = sunDirection(); float day = daylight();
    float horizon = pow(1.0 - max(rd.y, 0.0), 3.5);
    vec3 zenithCol = vec3(0.075, 0.22, 0.48);
    vec3 horizonCol = vec3(0.38, 0.49, 0.63);
    vec3 sky = mix(zenithCol, horizonCol, horizon);
    float sunset = exp(-abs(sd.y) * 8.5);
    float facing = pow(sat(dot(rd, sd) * 0.5 + 0.5), 6.0);
    vec3 sunsetCol = vec3(1.35, 0.42, 0.08);
    sky = mix(sky, sunsetCol, sunset * horizon * (0.28 + facing * 0.72));
    sky *= mix(0.20, 1.0, smoothstep(-0.08, 0.25, sd.y));
    sky = mix(vec3(0.0018, 0.0035, 0.009) + vec3(0.008, 0.012, 0.024) * horizon, sky, day);
    sky = mix(sky, vec3(dot(sky, vec3(0.2126, 0.7152, 0.0722))) * 0.75, rainStrength * 0.8);
    return sky;
    #endif
}

vec3 skyRadiance(vec3 rd) {
    #if defined(NETHER) || defined(END)
    return atmosphereBackground(rd);
    #else
    vec3 sd=sunDirection();float day=daylight();
    vec3 sky=atmosphereBackground(rd);
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
        if (sunDot > 0.6) {
            // 2. Soft atmospheric Mie scattering halo (~8 to 12 deg)
            float midHalo = pow(sunDot, 80.0);
            vec3 midCol = mix(vec3(0.20, 0.17, 0.12), vec3(0.60, 0.22, 0.05), sunsetFactor);
            sky += midCol * midHalo * 0.50 * day * (1.0 - rainStrength * 0.75);

            // 1. Delicate inner corona hugging the solar disc (~1.5 to 2.5 deg)
            if (sunDot > 0.95) {
                float innerHalo = pow(sunDot, 750.0);
                vec3 innerCol = mix(vec3(1.10, 0.90, 0.60), vec3(1.60, 0.65, 0.15), sunsetFactor);
                sky += innerCol * innerHalo * 0.85 * day * (1.0 - rainStrength);
            }

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
                float glare = pow(sunDot, 300.0) * spikePattern * flareFade;
                sky += mix(vec3(0.8, 0.65, 0.4), vec3(1.2, 0.40, 0.08), sunsetFactor) * glare * 0.35 * day * (1.0 - rainStrength);
            }
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
        if (moonDot > 0.7) {
            float moonHalo = pow(moonDot, 120.0) * 0.18;
            vec3 moonAura = vec3(0.03, 0.06, 0.12) * NIGHT_BRIGHTNESS * moonHalo;
            sky += moonAura * (1.0 - day) * (1.0 - rainStrength * 0.8);
        }
    }
    #endif
    #ifdef STARS
    if (day < 0.95 && rd.y > 0.02 && rainStrength < 0.9) {
        vec3 starCell = floor(rd * 650.0);
        sky += vec3(pow(hash13(starCell), 950.0)) * smoothstep(0.02, 0.3, rd.y) * (1.0 - day) * (1.0 - rainStrength) * 0.5;
    }
    #endif
    sky+=stormFlash()*(0.3+0.7*max(rd.y,0.0));
    return sky;
    #endif
}

#include "/lib/cloud_noise.glsl"
#include "/lib/cloud_weather.glsl"

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

// Density and ray bounds share the same layer; lighting uses the same cloud body.
float sampleCloudDensity(vec3 p, bool detail, float footprint) {
    float h=(p.y-CLOUD_ALT_BASE)*(1.0/CLOUD_ALT_THICK);
    if(h<=0.0 || h>=1.0) return 0.0;
    vec2 wind=vec2(1.15,0.48)*frameTimeCounter;
    vec2 pos=(p.xz+wind)*0.0021;
    float weather=noise2D(pos*0.27+vec2(0.2,0.7));
    float coverage=clamp(CLOUD_COVERAGE+rainStrength*0.26,0.10,0.95);
    // Weather bends the smaller formations; gaps are decided before opacity.
    float macro=noise2D(pos)*0.65;
    macro+=noise2D(rotCloud*pos*2.13+vec2(weather*0.8,-weather*0.6))*0.35;
    macro+=(weather-0.5)*0.16;
    float threshold=mix(0.60,0.34,coverage);
    // Dense cells build tall towers, while weaker formations have lower crowns.
    float base=0.035+weather*0.075;
    float top=mix(0.46,1.0,smoothstep(threshold-0.06,threshold+0.25,macro));
    if(h<=base || h>=top) return 0.0;
    float crown=sat((h-base)/max(top-base,0.1));
    threshold+=crown*crown*0.24;
    // A conservative empty-space test avoids all 3D noise in clear cells.
    if(macro+0.20<threshold-0.015) return 0.0;
    vec3 q=vec3((p.xz+wind)*0.010,(p.y-CLOUD_ALT_BASE)*0.013);
    q.xy+=vec2(h*0.7,-h*0.2);
    // Fade noise octaves that the pixel or march interval cannot resolve.
    // Keep their mean rather than allowing sub-sample detail to become stripes.
    float billow=mix(cloudNoise3D(q),0.5,smoothstep(0.35,1.0,footprint*0.013));
    float lobes=mix(cloudNoise3D(q*2.04+vec3(2.7,5.3,1.1)),0.5,
        smoothstep(0.25,0.85,footprint*(0.013*2.04)));
    float body=macro+(billow-0.5)*0.28+(lobes-0.5)*0.12;
    float density=smoothstep(threshold-0.015,threshold+0.12,body);
    float edgeFade=smoothstep(base,base+0.075,h);
    edgeFade*=1.0-smoothstep(top*0.82,top,h);
    density*=edgeFade;
    #ifdef CLOUD_DETAIL
    float detailWeight=1.0-smoothstep(0.20,0.75,footprint*(0.013*3.1));
    if(detail && density>0.005){
        float erosion=0.5;
        if(detailWeight>0.001) erosion=mix(0.5,cloudNoise3D(q*3.1+vec3(1.3,2.1,0.7)),detailWeight);
        density=max(density-(1.0-erosion)*0.17*(1.0-density),0.0);
    }
    #endif
    return density*mix(1.0,1.35,rainStrength);
}
float sampleCloudDensity(vec3 p, bool detail) {
    return sampleCloudDensity(p,detail,0.0);
}

vec4 cumulusLayerSteps(vec3 rd, vec2 pixel, int steps, float dither) {
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
    float maxRayDist = min(leave - entry, 2500.0);
    float distFade = 1.0 - smoothstep(2200.0, 4400.0, entry);
    float fadeWeight = horizonFade * distFade;
    if (fadeWeight <= 0.001) return vec4(0.0);

    // Horizon rays used the same count as short overhead rays, stretching a
    // step past a whole noise cell. Subdivide only the distant sky pass.
    int marchSteps=steps;
    if(steps>=12) {
        float interval=mix(125.0,32.0,smoothstep(600.0,1600.0,entry));
        marchSteps=max(steps,min(80,int(ceil(maxRayDist/interval))));
    }
    float stepLen = maxRayDist / float(marchSteps);
    // Half-resolution sky buffer covers two screen pixels per cloud sample.
    float angularFootprint=2.0/(max(viewHeight,1.0)*abs(gbufferProjection[1][1]));
    #if defined(CLOUD_RECONSTRUCTION) && !defined(CLOUD_FULL_RES)
    angularFootprint*=2.0;
    #endif

    float t = entry + stepLen * dither;

    vec3 sd = sunDirection();
    float day = daylight();
    vec3 sunCol = solarLightColor();

    // Dual-lobe phase function for forward scattering and the backlit cloud body.
    float sunTheta = dot(rd, sd);
    // Forward Mie scattering (silver lining rim facing the sun)
    float g1 = 0.80;
    float hg1 = (1.0 - g1 * g1) / max(pow(1.0 + g1 * g1 - 2.0 * g1 * sunTheta, 1.5), 0.0001) * (1.0 / (4.0 * PI));
    // Backward Glory scattering (luminous backscatter halo facing opposite the sun)
    float g2 = -0.30;
    float hg2 = (1.0 - g2 * g2) / max(pow(1.0 + g2 * g2 - 2.0 * g2 * sunTheta, 1.5), 0.0001) * (1.0 / (4.0 * PI));
    float phase = 0.65 * hg1 + 0.25 * hg2 + 0.10 * (0.75 * (1.0 + sunTheta * sunTheta) / (4.0 * PI));
    phase = clamp(phase * 3.5, 0.15, 3.8);

    // Night moonlight scattering
    vec3 md = -sd;
    float moonTheta = dot(rd, md);
    float moonMie = pow(sat(moonTheta * 0.5 + 0.5), 18.0) * 1.5;
    vec3 moonColor = vec3(0.005, 0.008, 0.018) * NIGHT_BRIGHTNESS;

    vec3 ld=(day>0.05 && sd.y>-0.02)?sd:md;
    float sunsetFactor=exp(-abs(sd.y)*8.5)*smoothstep(-0.02,0.05,sd.y);
    float trans = 1.0;
    vec3 cloudSum = vec3(0.0);

    // Sun direct illumination only reaches clouds when sun is above the horizon
    float sunDirectVis = smoothstep(-0.02, 0.08, sd.y);

    for (int i = 0; i < marchSteps; i++) {
        if(t > leave) break;
        vec3 p = cameraPosition + rd * t;
        float densityFootprint=max(t*angularFootprint,stepLen*0.5);
        float density = sampleCloudDensity(p, true, densityFootprint);
        if (density > 0.003) {
            // Light source raymarch (optical depth sampling)
            float opt1 = sampleCloudDensity(p + ld * 12.0, false, densityFootprint);
            float opt2 = sampleCloudDensity(p + ld * 38.0, false, densityFootprint);
            float optical = opt1 * 26.0 + opt2 * 54.0;
            #if CLOUD_LIGHT_SAMPLES >= 4
            optical+=sampleCloudDensity(p+ld*82.0,false,densityFootprint)*64.0;
            optical+=sampleCloudDensity(p+ld*158.0,false,densityFootprint)*88.0;
            #endif
            #if CLOUD_LIGHT_SAMPLES >= 6
            optical+=sampleCloudDensity(p+ld*254.0,false,densityFootprint)*108.0;
            optical+=sampleCloudDensity(p+ld*372.0,false,densityFootprint)*128.0;
            #endif

            // Approximate higher scattering orders with lower effective extinction.
            float beer = exp(-optical * CLOUD_EXTINCTION);
            float powder = 1.0 - exp(-density * stepLen * 0.16);
            // Two reduced-extinction orders illuminate the body without losing
            // the primary sun-path shadows and bright, thin backlit edges.
            float multiScatter = exp(-optical * CLOUD_EXTINCTION * 0.34) * 0.30;
            multiScatter+=exp(-optical * CLOUD_EXTINCTION * 0.085) * 0.12;
            float directShade = beer * (0.65 + powder * 0.65) + multiScatter;

            // Realistic atmospheric ambient:
            // Day: cool zenith azure from above + warm terrain ground bounce from below
            // Sunset: rich fiery amber glow on sun-facing rims, cool lavender-indigo shadows
            float hRel = sat((p.y - CLOUD_ALT_BASE) / CLOUD_ALT_THICK);
            vec3 skyAmbient = vec3(0.20, 0.28, 0.40) * (0.24 + hRel * 0.76);
            vec3 groundBounce = vec3(0.10, 0.095, 0.083) * (0.85 - hRel * 0.55);
            vec3 dayAmbient = (skyAmbient + groundBounce) * (0.42 + 0.58 * exp(-density * 2.4));

            // Dramatic sunset rim warm tint (strictly when sun is at the horizon during sunset)
            vec3 sunsetRim = vec3(1.4, 0.52, 0.12) * sunsetFactor * (0.4 + hRel * 0.6);
            dayAmbient += sunsetRim * 0.35;

            vec3 nightAmbient = vec3(0.0004, 0.0007, 0.0016) * NIGHT_BRIGHTNESS;
            vec3 ambient = mix(nightAmbient, dayAmbient, day * sunDirectVis);

            // Direct light: brilliant sunlit highlight by day vs gentle nocturnal moonlight rim by night
            vec3 dayDirect = sunCol * (directShade * phase + 0.04 * exp(-optical * 0.022)) * sunDirectVis;
            vec3 nightDirect = moonColor * (directShade * (0.025 + moonMie * 0.7));
            vec3 directLight = mix(nightDirect, dayDirect, day * sunDirectVis);

            vec3 light = ambient + directLight + stormFlash()*(0.5+hRel*0.5);

            float opacity = 1.0 - exp(-density * stepLen * CLOUD_EXTINCTION);
            cloudSum += trans * light * opacity;
            trans *= (1.0 - opacity);
        }
        t+=stepLen;
        if (trans < 0.012) break;
    }

    // Distant clouds keep their opacity while their radiance approaches aerial haze.
    vec3 haze=mix(vec3(0.002,0.004,0.009)*NIGHT_BRIGHTNESS,vec3(0.38,0.50,0.68),day);
    cloudSum=mix(haze*(1.0-trans),cloudSum,exp(-entry*0.00012));
    return vec4(cloudSum,1.0-trans)*fadeWeight;
    #endif
    #endif
    return vec4(0.0);
}

// Premultiplied scattering; combine in ray order, including cameras above clouds.
vec4 cloudOver(vec4 front,vec4 back) {
    return front+back*(1.0-front.a);
}
vec4 sheetCloudLayer(vec3 rd,bool high) {
    if(abs(rd.y)<0.015) return vec4(0.0);
    float altitude=high?CLOUD_HIGH_ALT:CLOUD_MID_ALT;
    float distance=(altitude-cameraPosition.y)/rd.y;
    if(distance<=0.0) return vec4(0.0);
    vec2 p=cameraPosition.xz+rd.xz*distance;
    float density=sheetCloudDensity(p,high);
    float path=(high?10.0:34.0)/max(abs(rd.y),0.12);
    float opacity=1.0-exp(-density*path*(high?0.032:0.045));
    opacity*=smoothstep(0.015,0.08,abs(rd.y))*(1.0-smoothstep(12000.0,22000.0,distance));
    if(opacity<0.001) return vec4(0.0);
    vec3 sd=sunDirection();float day=daylight();
    vec3 ld=sd.y>0.0?sd:-sd;
    float toward=pow(sat(dot(rd,ld)),high?12.0:8.0);
    float shade=exp(-sheetCloudDensity(p+ld.xz*90.0,high)*(high?0.8:2.3));
    float sunset=exp(-abs(sd.y)*8.5)*smoothstep(-0.02,0.06,sd.y);
    vec3 ambient=mix(vec3(0.001,0.002,0.004)*NIGHT_BRIGHTNESS,
        mix(vec3(0.20,0.26,0.35),vec3(0.38,0.23,0.20),sunset*0.5),day);
    vec3 light=ambient+lightColor()*shade*(0.16+toward*0.65);
    light+=stormFlash()*0.65;
    light=mix(atmosphereBackground(rd),light,exp(-distance*0.000045));
    return vec4(light*opacity,opacity);
}
vec4 cloudLayerSteps(vec3 rd,vec2 pixel,int steps,float dither) {
    vec4 low=cumulusLayerSteps(rd,pixel,steps,dither);
    #if CLOUDS == 2 && !defined(NETHER) && !defined(END)
    #if CLOUD_LAYERS >= 2
    vec4 mid=sheetCloudLayer(rd,false);
    #if CLOUD_LAYERS >= 3
    vec4 high=sheetCloudLayer(rd,true);
    if(rd.y>0.0) return cloudOver(low,cloudOver(mid,high));
    return cloudOver(high,cloudOver(mid,low));
    #else
    return rd.y>0.0?cloudOver(low,mid):cloudOver(mid,low);
    #endif
    #endif
    #endif
    return low;
}

vec4 cloudLayer(vec3 rd,vec2 pixel){
    // IGN's diagonal correlation becomes visible on stretched horizon rays.
    float dither=hash13(vec3(floor(pixel),19.37));
    #if defined(TEMPORAL_CLOUDS) && defined(CLOUD_RECONSTRUCTION)
    dither=hash13(vec3(floor(pixel),float(frameCounter%1024)+19.37));
    #endif
    return cloudLayerSteps(rd,pixel,CLOUD_STEPS,dither);
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
        vec3 sunCol = solarLightColor();

        // Pseudo-volumetric self-shadowing: sample slightly towards the sun
        float fbmSun = noise2D(pos + sd.xz * 0.012);
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
        float sunset = exp(-abs(sd.y) * 8.0) * horizon * smoothstep(-0.04,0.04,sd.y);
        cloudCol = mix(cloudCol, vec3(1.15, 0.45, 0.12), sunset * 0.70);

        // Horizon distance fade
        float fade = smoothstep(0.02, 0.12, rd.y) * (1.0 - smoothstep(1200.0, 3600.0, planeDist));
        return mix(background, cloudCol, min(density * fade, 0.90));
    }
    #endif
    return background;
}

#endif

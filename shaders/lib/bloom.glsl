vec3 blurBloom(sampler2D source,vec2 uv,vec2 axis) {
    vec2 margin=0.5/vec2(screenTextureSize(source));
    vec3 sum=textureScreen(source,uv).rgb*0.1641044;
    const float offsets[3]=float[3](1.4378235,3.3581660,5.2856376);
    const float weights[3]=float[3](0.2685693,0.1207749,0.02860365);
    // Combine adjacent Gaussian taps through bilinear filtering.
    for(int i=0;i<3;i++) {
        vec2 offset=axis*offsets[i];
        sum+=(textureScreen(source,clamp(uv+offset,margin,1.0-margin)).rgb
             +textureScreen(source,clamp(uv-offset,margin,1.0-margin)).rgb)*weights[i];
    }
    return sum;
}

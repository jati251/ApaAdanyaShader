#ifndef AA_SMOKE_FLOW
#define AA_SMOKE_FLOW
const int AA_SMOKE_NODES=16;
const float AA_SMOKE_HEIGHT=7.5;
// Symmetric endpoints encode the centre and radial spread, rather than a
// single selected escape direction. The centre can be advected independently.
vec2 smokePathCenter(vec4 path) { return (path.xy+path.zw)*.5; }
// Evaluate the widening continuously, rather than joining half-block radii
// into a hard cone. Begin bending before contact and recover over several blocks.
float smokeRoofSpread(vec4 roof,float height) {
    if(roof.x<0.0) return 0.0;
    float fan=smoothstep(max(roof.x-1.6,0.0),max(roof.x+.45,.75),height);
    float rejoin=1.0-smoothstep(roof.y+.65,roof.y+3.0,height);
    return roof.z*fan*rejoin;
}
bool smokeGridInside(ivec3 cell) {
    return all(greaterThanEqual(cell,ivec3(0))) && all(lessThan(cell,ivec3(32)));
}
#endif

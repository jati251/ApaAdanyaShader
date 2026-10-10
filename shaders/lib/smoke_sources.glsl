#ifndef AA_SMOKE_SOURCES
#define AA_SMOKE_SOURCES
// Tiny per-frame emitter table; flow history lives in the shared path cache.
const int AA_SMOKE_SOURCE_SLOTS=128;
const int AA_SMOKE_RAY_PLUMES=8;
vec3 smokeGridOrigin() { return floor(cameraPosition)-vec3(16.0); }
uint smokeSourceSlot(ivec3 worldCell) {
    uvec3 p=uvec3(worldCell);
    return ((p.x*73856093u)^(p.y*19349663u)^(p.z*83492791u))&63u;
}
uint smokeOverflowSlot(ivec3 worldCell) {
    uvec3 p=uvec3(worldCell);
    uint h=p.x*1597334677u+p.y*3812015801u+p.z*2798796415u;
    h^=h>>16u;return 64u+(h&63u);
}
uint smokePackSource(ivec3 cell,bool soul) {
    vec3 delta=vec3(cell)+0.5-(cameraPosition-smokeGridOrigin());
    uint priority=uint(clamp(1023.0-dot(delta,delta),1.0,1023.0));
    return uint(cell.x)|(uint(cell.y)<<5u)|(uint(cell.z)<<10u)
        |(soul?32768u:0u)|65536u|(priority<<17u);
}
vec3 smokeSourcePosition(uint source) {
    return smokeGridOrigin()+vec3(source&31u,(source>>5u)&31u,(source>>10u)&31u)+0.5;
}
bool smokeSoulSource(uint source) { return (source&32768u)!=0u; }
bool smokeSourceAtCell(uint emitter,ivec3 cell) {
    return emitter!=0u && all(equal(ivec3(emitter&31u,(emitter>>5u)&31u,(emitter>>10u)&31u),cell));
}
float smokeSourceFade(vec3 source) {
    return 1.0-smoothstep(SMOKE_DISTANCE*0.75,SMOKE_DISTANCE,length(source-cameraPosition));
}
#endif

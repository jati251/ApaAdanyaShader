// Rebuild compact streamlines once per source, rather than seeking exits per pixel.
#include "/lib/common.glsl"
#include "/lib/smoke_sources.glsl"
#include "/lib/smoke_flow.glsl"
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
const ivec3 workGroups=ivec3(2,1,1);
#ifdef AA_SMOKE
layout(r32ui) uniform readonly uimage2D aaSmokeEmitterImage;
#ifdef AA_VOXELS
layout(r32ui) uniform readonly uimage3D aaVoxelImage;
ivec3 smokeEmitterCell;
#else
layout(r32ui) uniform readonly uimage3D aaSmokeObstacleImage;
#endif
// Each invocation owns one complete source row, including its history.
layout(rgba32f) uniform image2D aaSmokePathImage;
bool smokeBlocked(vec3 p) {
    ivec3 cell=ivec3(floor(p));
    #ifdef AA_VOXELS
    // The existing 64-cube grid includes this 32-cube region at offset 16.
    // Ignore the emitter's own campfire cube so its volume can leave the fire.
    if(!smokeGridInside(cell) || all(equal(cell,smokeEmitterCell))
        || imageLoad(aaVoxelImage,cell+ivec3(16)).r==0u) return false;
    // Adjacent registered flames/campfires are emitters, not solid roof cubes.
    int slot=int(smokeSourceSlot(cell+ivec3(smokeGridOrigin())));
    if(smokeSourceAtCell(imageLoad(aaSmokeEmitterImage,ivec2(slot,0)).r,cell)) return false;
    slot=int(smokeOverflowSlot(cell+ivec3(smokeGridOrigin())));
    return !smokeSourceAtCell(imageLoad(aaSmokeEmitterImage,ivec2(slot,0)).r,cell);
    #else
    return smokeGridInside(cell) && imageLoad(aaSmokeObstacleImage,cell).r!=0u;
    #endif
}
bool smokeClear(vec3 p) {
    return !smokeBlocked(p) && !smokeBlocked(p+vec3(.28,0,0))
        && !smokeBlocked(p-vec3(.28,0,0)) && !smokeBlocked(p+vec3(0,0,.28))
        && !smokeBlocked(p-vec3(0,0,.28));
}
void main() {
    int slot=int(gl_GlobalInvocationID.x);
    uint emitter=imageLoad(aaSmokeEmitterImage,ivec2(slot,0)).r;
    if(emitter==0u) {
        for(int i=0;i<22;i++) imageStore(aaSmokePathImage,ivec2(i,slot),vec4(0));
        return;
    }
    vec3 source=smokeSourcePosition(emitter)-smokeGridOrigin();
    #ifdef AA_VOXELS
    smokeEmitterCell=ivec3(floor(source));
    #endif
    vec3 worldSource=source+smokeGridOrigin();float seed=hash12(worldSource.xz);
    vec4 oldOrigin=imageLoad(aaSmokePathImage,ivec2(18,slot));
    vec4 oldSource=imageLoad(aaSmokePathImage,ivec2(19,slot));
    vec4 oldRoof=imageLoad(aaSmokePathImage,ivec2(20,slot));
    float dt=frameTimeCounter-oldOrigin.w;
    bool sameSource=oldSource.w==12347.0 && dt>=0.0
        && all(lessThan(abs(oldSource.xyz+oldOrigin.xyz-worldSource),vec3(.01)));
    // Keep source age across camera-grid shifts and hitches, independently of
    // the short-lived flow history. Empty/replaced slots start transparent.
    float age=sameSource?min(1.5,imageLoad(aaSmokePathImage,ivec2(21,slot)).r+clamp(dt,0.0,.1)):0.0;
    // New schema tag prevents interpreting an older capsule cache as a fan.
    bool history=oldSource.w==12347.0 && dt>0.0 && dt<=.25
        && all(lessThan(abs(oldSource.xyz+oldOrigin.xyz-worldSource),vec3(.01)))
        && all(lessThan(abs(oldOrigin.xyz-smokeGridOrigin()),vec3(8.0)));
    vec4 oldPath[16];
    if(history) for(int i=0;i<16;i++)
        oldPath[i]=imageLoad(aaSmokePathImage,ivec2(i,slot));
    float transport=1.0-exp(-clamp(dt,0.0,.25)*2.1);
    float inertia=exp(-clamp(dt,0.0,.25)*.9);
    float phase=mod(frameTimeCounter,6283.1853)*.55+seed*6.2831853;
    vec2 wind=vec2(.11,.045)*WIND_SPEED;

    // Detect the roof from the stationary source column, not from a moving
    // streamline. This removes direction changes at voxel boundaries.
    vec4 roof=vec4(-1,0,0,0);float ceiling=AA_SMOKE_HEIGHT;
    for(int i=1;i<16;i++) {
        vec3 probe=source+vec3(0,float(i)*.5,0);
        if(!smokeBlocked(probe)) continue;
        roof.x=floor(probe.y)-source.y;
        roof.y=roof.x+1.0;
        for(int j=1;j<8;j++) {
            if(!smokeBlocked(vec3(source.x,source.y+roof.y+.01,source.z))) break;
            roof.y+=1.0;
        }
        break;
    }
    if(roof.x>=0.0) {
        float nearestExit=2.0;
        const vec2 directions[8]=vec2[8](vec2(1,0),vec2(.7071,.7071),vec2(0,1),vec2(-.7071,.7071),
            vec2(-1,0),vec2(-.7071,-.7071),vec2(0,-1),vec2(.7071,-.7071));
        for(int d=0;d<8;d++) {
            // Only seek exits that the bounded local billow can reach. Distant
            // roof edges cannot contribute and need no occupancy searches.
            for(int ring=1;ring<=3;ring++) {
                float radius=float(ring)*.375;
                vec2 side=source.xz+directions[d]*radius;
                bool open=true;
                // Check the full height of a stacked obstruction. Adjacent
                // registered fire cells remain permeable on tracing presets.
                for(int y=0;y<8;y++) {
                    float h=roof.x+.1+float(y);
                    if(h>=roof.y) break;
                    if(!smokeClear(vec3(side.x,source.y+h,side.y))) {open=false;break;}
                }
                if(!open) continue;
                nearestExit=min(nearestExit,radius);roof.w+=1.0;
                break;
            }
        }
        // A long beam must not inflate every side to its farthest end. Keep a
        // local billow around the fire and use the nearest reachable edge.
        roof.z=min(nearestExit,1.25);
        if(roof.w==0.0 || nearestExit>1.25) {
            // Broad ceilings retain local smoke below them instead of creating
            // a room-sized ring or resuming above a roof it cannot get around.
            roof.z=min(1.25,max(roof.x,.5));
            ceiling=min(ceiling,max(roof.x-.02,.35));
        }
    }
    bool actualRoof=roof.x>=0.0;
    // Retain the integration band while widening relaxes after removing a
    // block. Negative exit count marks a fading, no-longer-solid obstruction.
    if(!actualRoof && history && oldRoof.x>=0.0
        && imageLoad(aaSmokePathImage,ivec2(17,slot)).w>.005) {
        roof=oldRoof;roof.w=-1.0;
    }
    vec2 position=source.xz;
    vec3 lo=source,hi=source;float maxSpread=0.0;
    for(int i=0;i<AA_SMOKE_NODES;i++) {
        float height=float(i)*.5;
        vec2 curl=sin(vec2(height*1.15,height*.87)-phase)*(.025+height*.006);
        vec2 desired=position+wind*.5+curl;
        if(history && i>0) {
            vec2 advected=mix(smokePathCenter(oldPath[i]),smokePathCenter(oldPath[i-1]),transport)
                +oldOrigin.xz-smokeGridOrigin().xz;
            desired=mix(desired,advected+(wind+curl*3.0)*dt,inertia);
        }
        if(i==0) desired=source.xz;
        float spread=actualRoof?smokeRoofSpread(roof,height):0.0;
        if(history) {
            float previousSpread=abs(oldPath[i].z-oldPath[i].x)*.5;
            spread=mix(previousSpread,spread,1.0-exp(-dt*4.0));
        }
        if(roof.x>=0.0) {
            float fan=smoothstep(max(roof.x-1.6,0.0),max(roof.x-.15,.15),height);
            float rejoin=1.0-smoothstep(roof.y+.35,roof.y+3.0,height);
            // Keep the obstacle fan centred on its real emitter as billows move.
            desired=mix(desired,source.xz,fan*rejoin);
        }
        if(spread==0.0 && !smokeClear(vec3(desired.x,source.y+height,desired.y)))
            desired=source.xz;
        position=desired;
        maxSpread=max(maxSpread,spread);
        vec4 path=vec4(position-vec2(spread,0),position+vec2(spread,0));
        imageStore(aaSmokePathImage,ivec2(i,slot),path);
        lo=min(lo,vec3(position.x-spread,source.y+height,position.y-spread));
        hi=max(hi,vec3(position.x+spread,source.y+height,position.y+spread));
    }
    float width=.32+AA_SMOKE_HEIGHT*.16+.12;
    imageStore(aaSmokePathImage,ivec2(16,slot),vec4(lo-vec3(width,.05,width),ceiling));
    imageStore(aaSmokePathImage,ivec2(17,slot),vec4(hi+vec3(width,.05,width),maxSpread));
    imageStore(aaSmokePathImage,ivec2(18,slot),vec4(smokeGridOrigin(),frameTimeCounter));
    imageStore(aaSmokePathImage,ivec2(19,slot),vec4(source,12347.0));
    imageStore(aaSmokePathImage,ivec2(20,slot),roof);
    imageStore(aaSmokePathImage,ivec2(21,slot),vec4(age,0,0,0));
}
#else
void main() {}
#endif

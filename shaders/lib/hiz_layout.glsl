#ifndef AA_HIZ_LAYOUT
#define AA_HIZ_LAYOUT
ivec2 hizTileOffset(int level,ivec2 size) {
    if(level==0) return ivec2(0);
    if(level==1) return ivec2(size.x/2,0);
    if(level==2) return ivec2(size.x/2,size.y/4);
    return ivec2(size.x/2,size.y/4+size.y/8);
}
#endif

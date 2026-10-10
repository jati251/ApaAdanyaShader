#version 330 compatibility
#define NETHER

#include "/lib/settings.glsl"
#ifdef CLOUD_FULL_RES
#define AA_TARGET_FRACTION 1.0
#else
#define AA_TARGET_FRACTION .5
#endif
#include "/program/fullscreen.vsh"

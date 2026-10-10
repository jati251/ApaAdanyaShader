#version 330 compatibility
#ifdef MC_GL_ARB_shader_image_load_store
#extension GL_ARB_shader_image_load_store : enable
#endif
#define AA_VOXEL_WRITER
#include "/program/shadow.vsh"

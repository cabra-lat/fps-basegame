shader_type spatial;

#define LIT diffuse_lambert, vertex_lighting
#define CULL cull_back
#define DEPTH depth_draw_always
#define BLEND blend_mix
#define ALPHA_BLEND
#define EXTERNAL

#include "psx_base.gdshaderinc"

#include "/lib/common.glsl"
out vec4 glcolor;
void main() {
    glcolor=gl_Color;
    gl_Position=scaleSceneClip(ftransform(),vec2(1.0));
}

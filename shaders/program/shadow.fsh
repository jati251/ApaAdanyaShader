uniform sampler2D gtexture;
in vec2 texcoord;
in vec4 glcolor;
flat in float materialId;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
void main(){
    if(materialId>1002.5 && materialId<1003.5) discard;
    color=texture(gtexture,texcoord)*glcolor;
    if(color.a<0.1) discard;
}

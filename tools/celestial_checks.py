"""Actual GPU solar/lunar radiance across the Iris shadow-source handoff."""
import math
from quality_checks import Fixture


def run(api):
    f=Fixture(api,16,16)
    values=api['resolve']('REALISM')
    prefix=api['source'](api['ROOT']/'prepare.fsh',values,False).split('in vec2 texcoord;')[0]
    frag=prefix+'in vec2 texcoord;layout(location=0) out vec4 color;void main(){color=vec4(lightColor(),1);}'
    program=f.program('prepare.fsh',values,fragment=frag)
    target=f.texture(None,0)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    def draw(elevation,program=program):
        sun=(math.sqrt(1-elevation*elevation),elevation,0.)
        light=sun if elevation>=0 else tuple(-v for v in sun)
        u=dict(gbufferModelViewInverse=identity,sunPosition=sun,shadowLightPosition=light,rainStrength=0.)
        return f.render(program,[target],u)[:3]
    for elevation in [-.001,-.005,-.02,-.04,-.08,-.2,-.8]:
        color=draw(elevation)
        assert 0<color[0]<color[1]<color[2], ('Sunset color transferred to moon',elevation,color)
        assert abs(color[2]/color[0]-.09/.055)<1e-4, 'Lunar hue depends on sunset elevation'
    sunset=draw(.04)
    assert sunset[0]>sunset[1]>sunset[2], 'The source fix removed the warm setting sun'
    assert max(draw(0))<1e-6, 'Direct light did not fade through the source handoff'
    assert max(draw(.001)+draw(-.001))<.003, 'Direct radiance jumped at the horizon'
    disc=prefix+'in vec2 texcoord;layout(location=0) out vec4 color;void main(){vec3 d=-sunDirection();color=vec4(skyRadiance(d)-atmosphereBackground(d),1);}'
    p=f.program('prepare.fsh',values,fragment=disc)
    for elevation in [-.001,-.04,-.2]:
        color=draw(elevation,p)
        assert color[2]>color[1]>color[0]>0, 'Lunar disc inherited a solar halo'
    print('PASS: GPU sunset/sunrise source handoff, constant lunar hue, warm sun and independent lunar disc',flush=True)
    f.close()

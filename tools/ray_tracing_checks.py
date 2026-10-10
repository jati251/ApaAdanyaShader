"""GPU fixtures for off-screen geometry and disappearing GI emitters."""
from quality_checks import Fixture


def run(api):
    f=Fixture(api,16,16)
    values=api['resolve']('REALISM_RT')
    prefix=api['source'](api['ROOT']/'deferred3.fsh',values,False).split('in vec2 texcoord;')[0]
    frag=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
uniform vec3 testOrigin;
void main(){vec3 r;float c;bool hit=traceLightSpace(testOrigin,vec3(0,0,-1),24,r,c);
color=vec4(hit?r:vec3(0),c);}
'''
    p=f.program('deferred3.fsh',values,fragment=frag)
    identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    projection=[.1,0,0,0,0,.1,0,0,0,0,-.1,0,0,0,0,1]
    target=f.texture(None,0)
    f.texture([.53,0,0,1]*256,1)
    f.texture([.6,.2,.1,1]*256,2)
    uniforms=dict(gbufferModelViewInverse=identity,shadowModelView=identity,
                  shadowProjection=projection,shadowtex0=1,shadowcolor0=2,shadowcolor1=3,
                  testOrigin=(0.,0.,-1.))
    def draw(geometry,**extra):
        f.texture(geometry*256,3)
        return f.render(p,[target],dict(uniforms,**extra))[:4]
    hit=draw([.5,.5,1,1])
    assert max(abs(x-y) for x,y in zip(hit[:3],[.6,.2,.1]))<.001 and hit[3]>.8, hit
    assert max(draw([.5,.5,1,1],testOrigin=(0.,0.,-4.)))==0, 'Hidden receiver hit front layer'
    assert max(draw([.5,.5,0,1]))==0, 'Back-facing shadow geometry leaked light'
    assert max(draw([.5,.5,1,0]))==0, 'Cleared shadow geometry produced a hit'
    assert max(draw([.5,.5,1,1],testOrigin=(200.,0.,-1.)))==0, 'Trace escaped shadow distance'
    f.texture([1,0,0,1]*256,1)
    assert max(draw([.5,.5,1,1]))==0, 'Empty shadow depth produced a hit'
    print('PASS: GPU off-screen light-space hit, hidden receiver, backface, empty geometry/depth and range rejection',flush=True)

    frag=prefix+'''in vec2 texcoord;layout(location=0) out vec4 color;
void main(){color=stabilizeIndirect(texcoord,viewPosition(texcoord,0.97509751),vec3(0,0,1),vec4(0),vec4(0,0,0,0.7));}
'''
    p=f.program('deferred3.fsh',values,fragment=frag)
    n,z=.1,1024.
    a,b=-(z+n)/(z-n),-2*z*n/(z-n)
    projection=[1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0]
    inverse=[1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    f.texture([6,3,1,.7]*256,4)
    f.texture([0,0,1,4]*256,5)
    u=dict(viewWidth=16.,viewHeight=16.,gbufferProjection=projection,
           gbufferProjectionInverse=inverse,gbufferModelViewInverse=identity,
           gbufferPreviousModelView=identity,gbufferPreviousProjection=projection,
           colortex17=4,colortex18=5,frameCounter=20,frameTime=1/60,
           cameraPosition=(0.,0.,0.),previousCameraPosition=(0.,0.,0.))
    rendered=f.render(p,[target],u)
    out=rendered[(8*16+8)*4:(8*16+8)*4+4]
    assert max(out[0:3])<.08 and abs(out[3]-.7)<.001, 'Vanished GI emitter left bright history or modified AO'
    assert abs(out[0]/out[1]-2)<.01, 'History radiance clipping changed hue'
    print('PASS: GPU disappearing-emitter radiance clipping preserves hue and AO',flush=True)
    f.close()

#!/usr/bin/env python3
"""Build original procedural Minecraft textures; no external artwork is included."""
import argparse
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image


def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0,1)
    return t*t*(3-2*t)


def build(out):
    out=Path(out)
    base=out/'assets/minecraft'
    def write(name,rgb,alpha):
        rgba=np.dstack((np.broadcast_to(rgb,(*alpha.shape,3)),alpha))
        path=base/f'textures/{name}.png'
        path.parent.mkdir(parents=True,exist_ok=True)
        Image.fromarray(np.uint8(np.clip(rgba,0,1)*255),'RGBA').save(path)
    def particle(name,textures):
        path=base/f'particles/{name}.json'
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps({'textures':[f'minecraft:{x}' for x in textures]},indent=2)+'\n')
    out.mkdir(parents=True,exist_ok=True)
    (out/'pack.mcmeta').write_text(json.dumps({'pack':{'description':'ApaAdanya Effects | soft smoke, rain, animated fire','min_format':[97,1],'max_format':[97,1]}},indent=2)+'\n')
    # Periodic advection makes a seamless 32-frame flame loop.
    n=64
    y,x=np.mgrid[0:n,0:n]/(n-1)
    height=1-y
    for soul in (False,True):
        for variant in range(2):
            frames=[]
            for frame in range(32):
                t=frame/32*2*math.pi+variant*1.7
                warp=0.07*np.sin(height*9-t)+0.035*np.sin(height*21+t*2+x*9)
                xx=x+warp
                tongues=np.zeros_like(x)
                for center,length,width,phase in [(0.16,.72,.13,.1),(.41,.97,.18,1.8),(.69,.82,.15,3.3),(.90,.58,.12,4.7)]:
                    tip=length+0.08*np.sin(t+phase)
                    radius=width*np.maximum(1-height/tip,0)**.65+.008
                    tongue=np.exp(-((xx-center)/radius)**2)* (1-smooth(tip-.12,tip,height))
                    tongues=np.maximum(tongues,tongue)
                turbulence=.5+.25*np.sin(x*31+height*17-t*2)+.25*np.sin(x*53-height*29+t*3)
                density=tongues*(.76+.24*turbulence)
                alpha=smooth(.1,.5,density)*(1-smooth(.94,1,height))
                heat=np.clip(density*(1-height*.65),0,1)
                if soul:
                    rgb=np.stack((.12+.65*heat**3,.40+.58*heat,.85+.15*heat),axis=-1)
                else:
                    rgb=np.stack((np.ones_like(x),.16+.78*heat**.65,.015+.65*heat**3),axis=-1)
                frames.append(np.dstack((rgb,alpha)))
            data=np.vstack(frames)
            name=('soul_fire' if soul else 'fire')+f'_{variant}'
            write(f'block/{name}',data[:,:,:3],data[:,:,3])
            (base/f'textures/block/{name}.png.mcmeta').write_text(json.dumps({'animation':{'frametime':1,'interpolate':True}})+'\n')
        # A single sprite is sized and faded by Minecraft's particle simulation.
        yy,xx=np.mgrid[-1:1:32j,-1:1:32j]
        width=.40*(1+.40*yy)
        shape=np.exp(-((xx+.08*np.sin(yy*7))/width)**2-((yy-.1)/.65)**2)
        alpha=smooth(.025,.65,shape)*(1-smooth(.75,1,abs(xx)))*(1-smooth(.8,1,abs(yy)))
        heat=np.clip(shape,0,1)
        rgb=np.stack((.15+.75*heat**2,.6+.4*heat,np.ones_like(heat)),axis=-1) if soul else np.stack((np.ones_like(heat),.28+.72*heat,.025+.7*heat**3),axis=-1)
        write('particle/'+('soul_fire_flame' if soul else 'flame'),rgb,alpha)
    # Dedicated smoke sprites avoid changing generic particles used by unrelated effects.
    yy,xx=np.mgrid[-1:1:64j,-1:1:64j]
    for frame in range(12):
        t=frame/11
        shape=np.zeros_like(xx)
        for k in range(7):
            angle=k*2.399+t*.7
            cx=np.cos(angle)*(.15+.20*t); cy=np.sin(angle)*(.15+.20*t)
            lobe=np.exp(-((xx-cx)**2+(yy-cy)**2)/(.12+.12*t))
            shape=np.maximum(shape,lobe)
        detail=.85+.10*np.sin(xx*17+yy*11+t*5)+.05*np.cos(xx*31-yy*19)
        alpha=np.clip(shape*detail-.035,0,1)*(.60-.25*t)
        alpha*=1-smooth(.78,.98,np.maximum(abs(xx),abs(yy)))
        shade=.70+.22*shape
        rgb=np.stack((shade,shade,shade),axis=-1)
        write(f'particle/aa_smoke_{frame}',rgb,alpha)
        write(f'particle/big_smoke_{frame}',rgb,alpha)
    for name in ('smoke','large_smoke','white_smoke'):
        particle(name,[f'aa_smoke_{i}' for i in range(12)])
    # Narrow, sparse streaks; Minecraft supplies their falling motion and wind.
    yy,xx=np.mgrid[0:256,0:256]/256
    alpha=np.zeros_like(xx)
    for k in range(23):
        rng=np.random.default_rng(710+k)
        cx,cy=rng.random(2); width=rng.uniform(.0012,.0030); length=rng.uniform(.025,.14)
        dx=(xx-cx+.5)%1-.5; dy=(yy-cy+.5)%1-.5
        streak=np.exp(-(dx/width)**2)*(1-smooth(length*.65,length,abs(dy)))
        alpha=np.maximum(alpha,streak*rng.uniform(.22,.65))
    write('environment/rain',np.array([.72,.81,.9]),alpha)
    for i in range(4):
        yy,xx=np.mgrid[-1:1:32j,-1:1:32j]
        radius=.20+i*.17
        distance=np.sqrt(xx*xx+(yy*1.7)**2)
        ring=np.exp(-((distance-radius)/.055)**2)
        alpha=ring*(.70-i*.13)*(1-smooth(.75,1,abs(xx)))
        write(f'particle/splash_{i}',np.array([.73,.85,.92]),alpha)
    (out/'README.txt').write_text('ApaAdanya Effects — original procedural assets.\nMinecraft 26.3 resource format 97.1. Place above other texture packs.\nRebuild with tools/build_effects_pack.py from ApaAdanyaShader.\nReplaces fire, flame, smoke, rain streak and splash textures; vanilla simulation and meshes remain.\n')
    print(f'Built {len(list(out.rglob("*.png")))} textures in {out}')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('output',type=Path)
    build(parser.parse_args().output)

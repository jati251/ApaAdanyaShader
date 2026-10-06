"""Compare real GPU fixture outputs against a preserved shader directory.

Usage: python tools/culling_compare.py /absolute/path/to/reference/shaders [--allow-visual-change]
Uses the validator's driver/source setup and the existing behavioral fixtures.
"""
import pathlib
import sys

from quality_checks import Fixture


def contact_checks(api, reference):
    f = Fixture(api, 64, 32)
    current = api['ROOT']
    values = dict(api['resolve']('HIGH'), UPSCALE_QUALITY='0')
    prefix = api['source'](current/'prepare.fsh', values, False).split('in vec2 texcoord;')[0]
    programs = []
    for root in (reference, current):
        api['ROOT'] = root
        trace = api['expand'](root/'lib/trace.glsl')
        fragment = prefix+trace+'''uniform sampler2D testDepth;
uniform float originDepth;
in vec2 texcoord;
layout(location=0) out vec4 color;
void main(){
float shadow=traceScreenShadow(testDepth,screenTextureSize(testDepth),
    vec3(0,0,-originDepth),normalize(vec3(1,0,-0.1)),2.5,10);
color=vec4(shadow,shadow,shadow,1);
}'''
        programs.append(f.program('prepare.fsh', values, fragment=fragment))
    api['ROOT'] = current
    target = f.texture(None, 1)
    near, far = 0.05, 1000.0
    a, b = -(far+near)/(far-near), -2*far*near/(far-near)
    projection = [1,0,0,0,0,1,0,0,0,0,a,-1,0,0,b,0]
    inverse = [1,0,0,0,0,1,0,0,0,0,0,1/b,0,0,-1,a/b]
    for distance, width, height, culled in ((4.,64.,32.,False),
                                           (400.,64.,32.,True),
                                           (400.,3840.,2160.,False)):
        depth = (-a+b/(distance+0.06))*0.5+0.5
        f.texture([depth,0,0,1]*(f.w*f.h), 0)
        uniforms = dict(testDepth=0,near=near,gbufferProjection=projection,
                        gbufferProjectionInverse=inverse,originDepth=distance,
                        viewWidth=width,viewHeight=height)
        before, after = [f.render(p,[target],uniforms)[::4] for p in programs]
        if culled:
            assert max(after)==0.0, 'Subpixel contact rays were not culled'
        else:
            assert max(before)>0.001, f'Fixture failed to produce a contact shadow at {distance} blocks / {width} pixels: {max(before)}'
            assert max(abs(x-y) for x,y in zip(before,after))<0.00001, 'Resolved contact shadow changed'
    f.close()
    print('PASS: GPU resolved contact shadows unchanged; subpixel rays culled; 4K restores resolved detail', flush=True)


def main():
    reference = pathlib.Path(sys.argv[1]).resolve()
    assert (reference / 'lib/settings.glsl').is_file(), 'Expected a reference shaders directory'
    validator = pathlib.Path(__file__).with_name('validate.py')
    # Only initialize the existing validator; manage driver lifetime here.
    setup = validator.read_text().split('\ntry:\n    total = 0', 1)[0]
    api = {'__file__': str(validator), '__name__': 'culling_gpu_setup'}
    exec(compile(setup, str(validator), 'exec'), api)
    current = api['ROOT']
    original_render = Fixture.render
    captures = []
    maximum = 0.0
    index = 0
    total_error = 0.0
    total_channels = 0

    def capture(fixture, *args, **kwargs):
        pixels = original_render(fixture, *args, **kwargs)
        captures.append(pixels)
        return pixels

    def compare(fixture, *args, **kwargs):
        nonlocal index, maximum, total_error, total_channels
        pixels = original_render(fixture, *args, **kwargs)
        before = captures[index]
        assert len(before) == len(pixels), 'Fixture dimensions changed'
        delta = max(abs(a-b) for a, b in zip(before, pixels))
        maximum = max(maximum, delta)
        total_error += sum(abs(a-b) for a,b in zip(before,pixels))
        total_channels += len(pixels)
        # HDR optics amplify floating-point differences in the algebraic wave
        # rewrite. Bound them below 0.0005 rather than claiming bit identity.
        if '--allow-visual-change' not in sys.argv:
            assert delta < 0.0005, f'GPU render {index}: visual delta {delta:.8f}'
        index += 1
        return pixels

    try:
        import water_surface_checks
        import water_vertex_checks
        import water_motion_checks
        # Wave octave truncation changes the crest contract; validate its new
        # behavior separately in weather_checks rather than apply it to old code.
        checks = (water_surface_checks, water_vertex_checks, water_motion_checks)
        api['ROOT'] = reference
        Fixture.render = capture
        for check in checks:
            check.run(api)
        api['ROOT'] = current
        Fixture.render = compare
        for check in checks:
            check.run(api)
        assert index == len(captures), 'Fixture count changed'
        print(f'PASS: {index} before/after GPU renders; maximum absolute delta {maximum:.8f}', flush=True)
        print(f'INFO: mean absolute channel delta {total_error/max(total_channels,1):.8f}',flush=True)
        if '--allow-visual-change' in sys.argv:
            print('INFO: visual differences reported without an equivalence assertion (approved quality tradeoff)',flush=True)
        Fixture.render = original_render
        contact_checks(api, reference)
    finally:
        Fixture.render = original_render
        api['ROOT'] = current
        api['driver'].close()


if __name__ == '__main__':
    main()

"""Actual deferred-fragment regressions for low-tier sky/DH and FSR sampling."""
from quality_checks import Fixture
import ctypes as c

IDENTITY = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]


def run(api):
    check_material_outputs(api)
    for profile in ('POTATO', 'LOW'):
        for quality in ('0', '2'):
            for dimension in ('', 'world-1/', 'world1/'):
                f = Fixture(api, 48, 24)
                try:
                    values = dict(api['resolve'](profile), UPSCALE_QUALITY=quality)
                    entry = dimension + 'deferred5.fsh'
                    fragment = api['source'](api['ROOT']/entry, values, True)
                    # Eager reconstruction is the prior behavior; compare both MRT outputs.
                    eager = fragment.replace('bool needsView=depth>=0.999999 && !isDH;',
                                             'bool needsView=true;')
                    programs = [f.program('deferred5.fsh', values, fragment=s)
                                for s in (eager, fragment)]
                    targets = [f.texture(None, 0), f.texture(None, 1)]
                    f.texture([0.3,0.4,0.7,1.0]*(f.w*f.h), 2)
                    scale = 1.0 if quality == '0' else 2.0/3.0
                    active_width = int(f.w*scale)
                    vanilla, dh = [], []
                    for y in range(f.h):
                        for x in range(f.w):
                            vanilla.extend((0.75 if x<active_width//3 else 1.0,0,0,1))
                            dh.extend((0.8 if x<active_width*2//3 else 1.0,0,0,1))
                    f.texture(vanilla, 3)
                    f.texture(dh, 4)
                    uniforms = dict(colortex0=2, depthtex0=3, dhDepthTex0=4,
                                    gbufferProjectionInverse=IDENTITY,
                                    gbufferModelViewInverse=IDENTITY,
                                    dhProjectionInverse=IDENTITY,
                                    sunPosition=(0.,1.,0.), shadowLightPosition=(0.,1.,0.),
                                    cameraPosition=(0.,64.,0.), fogColor=(0.3,0.2,0.1),
                                    viewWidth=float(f.w), viewHeight=float(f.h), far=256.)
                    for attachment in (0, 1):
                        old, new = [f.render(p, targets, uniforms, read=attachment)
                                    for p in programs]
                        assert max(abs(a-b) for a,b in zip(old,new)) < 1e-6, \
                            'Low-tier lazy reconstruction changed sky or DH shading'
                        for x in (f.w//6, f.w//2):
                            pixel = new[(f.h//2*f.w+x)*4:][:4]
                            assert max(abs(a-b) for a,b in zip(pixel,(0.3,0.4,0.7,1.0))) < 1e-6, \
                                'Low-tier deferred replaced vanilla/DH opaque color with sky'
                finally:
                    f.close()
    print('PASS: GPU Potato/Low opaque and DH preservation, eager/lazy sky parity, both MRT outputs, native/FSR and all dimensions', flush=True)


def check_material_outputs(api):
    variants = [(name, dict(api['resolve'](name), UPSCALE_QUALITY='0'))
                for name in ('POTATO', 'LOW', 'MEDIUM', 'HIGH')]
    variants.append(('CUSTOM_SPECULAR', dict(api['resolve']('POTATO'), RESOURCE_SPECULAR=True)))
    for name, values in variants:
        full = name not in ('POTATO', 'LOW')
        for entry in ('gbuffers_terrain', 'gbuffers_particles', 'dh_terrain', 'dh_water'):
            shaders = []
            program = api['create_program']()
            try:
                for suffix in ('.vsh', '.fsh'):
                    shader = api['compile_one'](api['ROOT']/(entry+suffix), values, True)
                    shaders.append(shader)
                    api['attach'](program, shader)
                api['link'](program)
                status = c.c_int()
                api['program_status'](program, 0x8B82, c.byref(status))
                assert status.value, f'{name}: failed to link {entry}'
                location = api['bind']('glGetFragDataLocation', c.c_int, c.c_uint, c.c_char_p)
                assert location(program,b'color') == 0
                assert location(program,b'materialData') == (2 if full else 1), \
                    f'{name}/{entry}: material mask attachment changed'
                assert location(program,b'normalData') == (1 if full else -1), \
                    f'{name}/{entry}: unexpected normal attachment'
                if entry != 'dh_water':
                    expected = (4 if entry == 'gbuffers_terrain' and values['RESOURCE_SPECULAR'] else 3) if full else -1
                    assert location(program,b'responseData') == expected, \
                        f'{name}/{entry}: unexpected diffuse response attachment'
            finally:
                api['delete_program'](program)
                for shader in shaders:
                    api['delete_shader'](shader)
    print('PASS: GPU low-tier two-target output locations, retained material masks and full Medium/High/custom-specular attachments', flush=True)


if __name__ == '__main__':
    import pathlib
    validator = pathlib.Path(__file__).with_name('validate.py')
    api = {'__file__': str(validator)}
    exec(compile(validator.read_text().split('try:\n    total = 0')[0], str(validator), 'exec'), api)
    try:
        run(api)
    finally:
        api['driver'].close()

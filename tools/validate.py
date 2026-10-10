#!/usr/bin/env python3
"""Validate real preset values and compile/link with the local OpenGL driver.

Compatibility builtins are bridged to core inputs, as Iris does at runtime.
This catches GLSL errors, not Iris framebuffer/texture binding errors.
"""
import ctypes as c
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1] / 'shaders'
SETTINGS = (ROOT / 'lib/settings.glsl').read_text()
PROPS = (ROOT / 'shaders.properties').read_text()
DEFINES = re.compile(r'^(?://)?#define (\w+)(?: ([^/\n]+?))?\s*(?://.*)?$', re.M)
options = {}
for line in SETTINGS.splitlines():
    m = re.match(r'(?://)?#define (\w+)(?: ([^/]+?))?\s*(?://.*)?$', line)
    if m and m[1] != 'AA_SETTINGS':
        value = m[2].strip() if m[2] else not line.startswith('//')
        choices = re.search(r'\[([^]]+)\]', line)
        options[m[1]] = (value, choices[1].split() if choices else None)
    m = re.match(r'const (?:int|float) (\w+) = ([^;]+);.*\[([^]]+)\]', line)
    if m:
        options[m[1]] = (m[2], m[3].split())
profiles = dict(re.findall(r'^profile\.(\w+)=(.*)$', PROPS, re.M))
historical_profiles = json.loads((ROOT.parent/'tools/fixtures/historical_profiles.json').read_text())

def resolve(name, stack=()):
    # Historical stress fixtures are not Iris profiles or preset exports.
    if name not in profiles:
        assert name in historical_profiles, f'Unknown test configuration: {name}'
        return dict(historical_profiles[name])
    assert name not in stack, f'Profile cycle: {name}'
    result = {}
    for token in profiles[name].split():
        if token.startswith('profile.'):
            result.update(resolve(token[8:], stack + (name,)))
        else:
            if ':' in token:
                key, value = token.split(':', 1)
            else:
                key, value = token.lstrip('!'), not token.startswith('!')
            assert key in options, f'Unknown option {key}'
            choices = options[key][1]
            assert choices is None or value in choices, f'{name}: invalid {key}={value}'
            result[key] = value
    return result

for profile in profiles:
    assert resolve(profile).keys() == options.keys(), f'{profile}: incomplete profile'
for screen in re.findall(r'^screen(?:\.[A-Z]+)?=(.*)$', PROPS, re.M):
    for item in screen.split():
        assert item.startswith(('[', '<')) or item in options, f'Unknown menu option {item}'
for locale in ('en_us', 'id_id'):
    lang = (ROOT / f'lang/{locale}.lang').read_text()
    for option in options:
        assert f'option.{option}=' in lang, f'{locale}: missing {option}'
    for profile in profiles:
        assert f'profile.{profile}=' in lang and f'profile.{profile}.comment=' in lang, f'{locale}: missing profile description {profile}'
    locale_keys=re.findall(r'^([^#=\s]+)=',lang,re.M)
    assert len(locale_keys)==len(set(locale_keys)), f'{locale}: duplicate translation keys'
print(f'PASS: {len(profiles)} complete profiles, legal option values, both translations', flush=True)
exported=set()
for preset in sorted((ROOT.parent/'presets').glob('*.txt')):
    text=preset.read_text()
    header=re.search(r'^# Profile: (\w+)$',text,re.M)
    assert header and header[1] in profiles, f'{preset.name}: missing/unknown profile ID'
    name=header[1]
    assert name not in exported, f'Duplicate preset export: {name}'
    exported.add(name)
    values={}
    for line in text.splitlines():
        if not line or line.startswith('#'): continue
        key,value=line.split('=',1)
        assert key in options and key not in values, f'{preset.name}: unknown/duplicate option {key}'
        if isinstance(options[key][0],bool):
            assert value in ('true','false'), f'{preset.name}: invalid boolean {key}'
            value=value=='true'
        values[key]=value
    assert values==resolve(name), f'{preset.name}: saved values differ from Iris profile {name}'
assert exported==set(profiles), 'Missing saved profile exports'
print(f'PASS: {len(exported)} saved presets exactly match Iris profiles; every profile has both descriptions',flush=True)
assert not re.search(r'^uniform\.bool\.\w+\s*=\s*(?:true|false)\s*$', PROPS, re.M), 'Iris custom bool uniforms require comparison expressions'
all_source = '\n'.join(p.read_text() for p in ROOT.rglob('*') if p.suffix in ('.glsl','.fsh','.vsh'))
# Iris interprets format names in comments, not GLSL enum declarations. The
# synthetic compiler bridge defines these names, so check the actual pack too.
uncommented_source=re.sub(r'/\*.*?\*/|//[^\n]*','',all_source,flags=re.S)
assert not re.search(r'const\s+int\s+\w+Format\s*=\s*(?:RGBA\w*|R\d+F)\s*;',uncommented_source), 'Iris buffer format directives must be inside comments'
# Iris parses buffer clear colors independently of GLSL compilation. Its vec4
# directive parser requires four literal components, even for a scalar splat.
for name,constructor in re.findall(r'const\s+vec4\s+((?:colortex\d+|shadowcolor\d+)ClearColor)\s*=\s*vec4\(([^)]*)\)',all_source):
    components=constructor.split(',')
    assert len(components)==4, f'Iris {name} requires four explicit components: {constructor}'
    for component in components:
        assert re.fullmatch(r'\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[fF]?\s*',component), f'Iris {name} requires literal components: {constructor}'
print('PASS: Iris clear-color directives use four explicit literal components',flush=True)
cache_size=re.search(r'const\s+ivec2\s+size\s*=\s*ivec2\((\d+),\s*(\d+)\)', (ROOT/'lib/environment.glsl').read_text())
if cache_size:
    configured=re.search(r'^size\.buffer\.colortex7=(\d+)\s+(\d+)\s*$',PROPS,re.M)
    assert configured and cache_size.groups()==configured.groups(), 'Static sky-cache size differs from Iris buffer allocation'
    print('PASS: static sky-cache dimensions match Iris buffer allocation',flush=True)
for key,(value,_) in options.items():
    if isinstance(value,bool):
        assert re.search(r'#ifn?def\s+'+key+r'\b',all_source), f'{key}: option not discoverable by Iris'
for directory in ('world-1','world1'):
    for entry in ROOT.glob('*sh'):
        assert (ROOT/directory/entry.name).exists(), f'{directory}: missing {entry.name}'

def enabled_properties(values, features):
    """Evaluate the pack's allocation/pass gates, including optional features."""
    defines = dict(values, **{name: True for name in features})
    def condition(expression):
        expression = re.sub(r'defined\((\w+)\)', lambda m: str(bool(defines.get(m[1], False))), expression)
        expression = re.sub(r'\b[A-Z][A-Z_0-9]*\b', lambda m: str(defines.get(m[0], 0)), expression)
        expression = expression.replace('&&', ' and ').replace('||', ' or ')
        expression = re.sub(r'!(?!=)', ' not ', expression)
        return bool(eval(expression, {'__builtins__': {}}, {}))
    output = {}; stack = []; active = True
    for line in PROPS.splitlines():
        if line.startswith(('#ifdef ', '#ifndef ', '#if ')):
            if line.startswith('#ifdef '): branch = bool(defines.get(line[7:], False))
            elif line.startswith('#ifndef '): branch = not bool(defines.get(line[8:], False))
            else: branch = condition(line[4:])
            stack.append((active, branch)); active = active and branch
        elif line == '#else':
            parent, branch = stack[-1]; active = parent and not branch
        elif line == '#endif':
            active = stack.pop()[0]
        elif active and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1); output[key] = value
    assert not stack, 'Unbalanced shader properties conditions'
    return output

advanced_features = ['IRIS_FEATURE_CUSTOM_IMAGES', 'IRIS_FEATURE_COMPUTE_SHADERS']
for profile in profiles:
    values = resolve(profile)
    for features in ([], advanced_features[:1], advanced_features[1:], advanced_features):
        props = enabled_properties(values, features)
        volumetric = all(values[k] for k in ('VOLUMETRIC_LIGHT','HALF_RES_LIGHTING','SHADOWS'))
        smoke = len(features)==2 and values['SMOKE_MODE']=='1' and values['SHADOWS']
        assert props.get('program.composite.enabled') == str(volumetric or smoke).lower(), f'{profile}: volumetric gate mismatch'
        assert ('image.aaSmokeEmitterImage' in props)==smoke
        assert ('image.aaSmokePresenceImage' in props)==smoke
        assert ('image.aaSmokeObstacleImage' in props)==(smoke and not values['VOXEL_TRACING'])
        assert ('image.aaSmokePathImage' in props)==smoke
        assert props['program.shadowcomp1.enabled']==str(smoke).lower()
        assert props['program.world-1/shadowcomp1.enabled']=='false'
        assert props['program.world1/shadowcomp1.enabled']=='false'
        assert props['size.buffer.colortex21']==('0.5 0.5' if smoke else '1 1')
        assert props.get('uniform.bool.aaVLReady') == ('1 == 1' if volumetric else '1 == 0')
        for dimension in ('world-1/', 'world1/'):
            assert props.get('program.'+dimension+'composite.enabled') == 'false'
        supported = len(features) == 2
        hiz = supported and values['HIZ_TRACING']
        voxel = supported and values['VOXEL_TRACING'] and values['SHADOWS']
        denoise = supported and all(values[k] for k in ('SVGF_DENOISER','SSGI','HALF_RES_LIGHTING','TEMPORAL_INDIRECT'))
        assert ('image.aaHiZImage' in props) == hiz
        assert ('image.aaVoxelImage' in props) == voxel
        assert ('image.aaDenoiseImageA' in props) == denoise
        for directory in ('', 'world-1/', 'world1/'):
            for pass_name, enabled in [('deferred', hiz)] + [('deferred'+suffix, False) for suffix in ('_a','_b','_c')] + [('deferred4'+suffix, denoise) for suffix in ('','_a','_b')] + [('shadowcomp', voxel)]:
                assert props.get('program.'+directory+pass_name+'.enabled') == str(enabled).lower(), f'{profile}: compute gate mismatch {pass_name}'
        if not supported:
            assert not any(key.startswith('image.') for key in props), f'{profile}: unsupported custom images allocated'
print('PASS: optional GPU feature gates disable every compute stage and image allocation on fallback profiles', flush=True)
for changes in [dict(SMOKE_MODE='0'),dict(SHADOWS=False)]:
    props=enabled_properties(dict(resolve('HIGH'),**changes),advanced_features)
    assert not any(key.startswith('image.aaSmoke') for key in props)
    assert props['program.shadowcomp1.enabled']=='false'
    assert props['size.buffer.colortex21']=='1 1'
print('PASS: Minecraft smoke mode and shadows-off remove all smoke images, cache dispatch and half-size smoke target',flush=True)

if '--static' in sys.argv:
    sys.exit(0)
from gl_context import GLContext
driver = GLContext()
bind = driver.bind
CORE_VERSION = '330'  # Compile the same language version on macOS and Windows.
get_string = bind('glGetString', c.c_char_p, c.c_uint)
print('GPU:', get_string(0x1F01).decode(), flush=True)
create_shader = bind('glCreateShader', c.c_uint, c.c_uint)
shader_source = bind('glShaderSource', None, c.c_uint, c.c_int, c.POINTER(c.c_char_p), c.POINTER(c.c_int))
compile_shader = bind('glCompileShader', None, c.c_uint)
shader_status = bind('glGetShaderiv', None, c.c_uint, c.c_uint, c.POINTER(c.c_int))
shader_log = bind('glGetShaderInfoLog', None, c.c_uint, c.c_int, c.POINTER(c.c_int), c.c_char_p)
create_program = bind('glCreateProgram', c.c_uint)
attach = bind('glAttachShader', None, c.c_uint, c.c_uint)
link = bind('glLinkProgram', None, c.c_uint)
program_status = bind('glGetProgramiv', None, c.c_uint, c.c_uint, c.POINTER(c.c_int))
program_log = bind('glGetProgramInfoLog', None, c.c_uint, c.c_int, c.POINTER(c.c_int), c.c_char_p)
delete_shader = bind('glDeleteShader', None, c.c_uint)
delete_program = bind('glDeleteProgram', None, c.c_uint)

def expand(path, stack=()):
    assert path not in stack, f'Include cycle: {path}'
    def include(m):
        target = ROOT / m[1].lstrip('/') if m[1].startswith('/') else path.parent / m[1]
        return expand(target, stack + (path,))
    return re.sub(r'^\s*#include "([^"]+)".*$', include, path.read_text(), flags=re.M)

def source(path, values, dh):
    code = expand(path)
    for key, value in values.items():
        if isinstance(value, bool):
            code = re.sub(r'^(?://)?#define ' + re.escape(key) + r'\b[^\n]*', ('#define ' if value else '//#define ') + key, code, flags=re.M)
        else:
            code = re.sub(r'^(#define ' + re.escape(key) + r' )[^\n]*', lambda m: m[1] + value, code, flags=re.M)
            code = re.sub(r'(const (?:float|int) ' + re.escape(key) + r'\s*=\s*)[^;]+', lambda m: m[1] + value, code)
    version='430' if path.suffix=='.csh' else CORE_VERSION
    code=re.sub(r'^#version \d+ compatibility', '#version '+version+' core',code,flags=re.M)
    builtins = '''
#define RGBA8 32856
#define RGBA16F 34842
#define R16F 33325
#define IS_IRIS
uniform mat4 aa_ModelView, aa_Projection, aa_TextureMatrix[8];
uniform mat3 aa_NormalMatrix;
'''
    if values.get('__native_compile'):
        builtins += '#define IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS\n'
    if '--advanced' in sys.argv and (values.get('__native_compile') or values.get('__advanced_fixture')):
        builtins='''
#extension GL_ARB_shader_image_load_store : enable
#define MC_GL_ARB_shader_image_load_store
#define IRIS_FEATURE_CUSTOM_IMAGES
#define IRIS_FEATURE_COMPUTE_SHADERS
#define IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
'''+builtins
        # Keep extension directives in the prelude, ahead of synthetic uniforms.
        code=re.sub(r'^#extension GL_ARB_shader_image_load_store.*$','',code,flags=re.M)
    if path.suffix == '.vsh':
        builtins += '''
in vec4 aa_Vertex, aa_Color, aa_MultiTexCoord0, aa_MultiTexCoord1;
in vec3 aa_Normal;
vec4 aa_ftransform() { return aa_Projection*aa_ModelView*aa_Vertex; }
'''
    if dh:
        builtins += '#define DISTANT_HORIZONS\n'
        if path.name.startswith('dh_') and path.suffix == '.fsh':
            builtins += 'bool dh_hasTexture(){return false;}\nvec4 dh_sampleTexture(){return vec4(1.0);}\n'
    # Legacy behavioral fixtures intentionally hold the old procedural cloud
    # field fixed. performance_checks separately binds and tests the actual LUT.
    if not values.get('__native_compile'):
        builtins += '#define AA_PROCEDURAL_CLOUDS\n'
    for old, new in {'gl_ModelViewMatrix':'aa_ModelView','gl_ProjectionMatrix':'aa_Projection','gl_TextureMatrix':'aa_TextureMatrix','gl_NormalMatrix':'aa_NormalMatrix','gl_Vertex':'aa_Vertex','gl_Color':'aa_Color','gl_MultiTexCoord0':'aa_MultiTexCoord0','gl_MultiTexCoord1':'aa_MultiTexCoord1','gl_Normal':'aa_Normal','ftransform':'aa_ftransform'}.items():
        code = re.sub(r'\b' + old + r'\b', new, code)
    return code.replace('#version '+version+' core', '#version '+version+' core\n' + builtins, 1)

def compile_one(path, values, dh):
    shader = create_shader(0x91B9 if path.suffix=='.csh' else (0x8B31 if path.suffix == '.vsh' else 0x8B30))
    text = c.c_char_p(source(path, dict(values,__native_compile=True), dh).encode())
    shader_source(shader, 1, c.byref(text), None)
    compile_shader(shader)
    status = c.c_int()
    shader_status(shader, 0x8B81, c.byref(status))
    if not status.value:
        log = c.create_string_buffer(32768)
        shader_log(shader, len(log), None, log)
        raise RuntimeError(f'{path.relative_to(ROOT)}\n{log.value.decode()}')
    return shader

try:
    total = 0
    variants = [(name, resolve(name)) for name in profiles]
    variants += [('DEFAULT', dict((k,v[0]) for k,v in options.items())), ('MANUAL_FOCUS', dict(resolve('HIGH'), DOF_AUTOFOCUS=False))]
    active_file=ROOT.parent.parent/(ROOT.parent.name+'.txt')
    if active_file.exists():
        active=dict((k,v[0]) for k,v in options.items())
        for line in active_file.read_text().splitlines():
            if not line or line.startswith('#') or '=' not in line: continue
            key,value=line.split('=',1)
            assert key in options, f'Active preset has unknown option: {key}'
            if isinstance(options[key][0],bool):
                assert value in ('true','false'), f'Invalid boolean in active preset: {line}'
                value=value=='true'
            else:
                assert options[key][1] is None or value in options[key][1], f'Invalid active setting: {line}'
            active[key]=value
        variants += [('ACTIVE_INSTANCE',active)]
    variants += [('POM_NO_NORMALS', dict(resolve('HIGH'), RESOURCE_NORMALS=False)),
                 ('POM_NO_SPECULAR', dict(resolve('HIGH'), RESOURCE_SPECULAR=False)),
                 ('POM_ZERO_DEPTH', dict(resolve('HIGH'), POM_DEPTH='0.0'))]
    variants += [('FULL_RES_REFERENCE', dict(resolve('EXTREME'), CLOUD_RECONSTRUCTION=False, TEMPORAL_CLOUDS=False, HALF_RES_LIGHTING=False, HALF_RES_DOF=False)),
                 ('NO_CLOUD_HISTORY', dict(resolve('HIGH'), TEMPORAL_CLOUDS=False)),
                 ('AO_ONLY_RECONSTRUCTION', dict(resolve('HIGH'), SSGI=False))]
    variants += [(f'FSR1_{q}',dict(resolve('HIGH'),UPSCALE_QUALITY=str(q))) for q in (1,2,3)]
    variants += [('FSR1_EXTREME',dict(resolve('EXTREME'),UPSCALE_QUALITY='1')),
                 ('FSR1_POTATO',dict(resolve('POTATO'),UPSCALE_QUALITY='3')),
                 ('FSR1_NO_SHARPEN',dict(resolve('HIGH'),UPSCALE_QUALITY='2',UPSCALE_SHARPNESS='0.0'))]
    requested_profiles={arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--profile=')}
    if requested_profiles:
        assert requested_profiles <= set(profiles), 'Unknown requested shader profile'
        variants = [(name, resolve(name)) for name in profiles if name in requested_profiles]
    if '--images-only' in sys.argv:
        variants = []
    requested_programs={arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--program=')}
    if '--shadow-only' in sys.argv:
        requested_programs = {'shadow'}
    if '--water-only' in sys.argv:
        requested_programs = {'gbuffers_water','dh_water','composite1','composite4','composite7'}
    if '--water-lod-only' in sys.argv:
        requested_programs = {'dh_water'}
    if '--smoke-only' in sys.argv:
        requested_programs = {'shadow','shadow_solid','shadow_cutout','composite','composite1','gbuffers_terrain','gbuffers_particles','gbuffers_particles_translucent'}
    if '--aquatic-only' in sys.argv:
        requested_programs = {'shadow','shadow_solid','shadow_cutout','gbuffers_terrain'}
    if requested_programs:
        assert requested_programs <= {p.stem for p in ROOT.glob('*.vsh')}, 'Unknown requested shader program'
    for name, values in variants:
        for dh in (False, True):
            for vertex in sorted(ROOT.rglob('*.vsh')):
                if vertex.parent.name in ('program', 'lib'):
                    continue
                if requested_programs and vertex.stem not in requested_programs:
                    continue
                fragment = vertex.with_suffix('.fsh')
                if not fragment.exists():
                    raise RuntimeError(f'Missing fragment for {vertex}')
                vs, fs = compile_one(vertex, values, dh), compile_one(fragment, values, dh)
                program = create_program()
                attach(program, vs)
                attach(program, fs)
                link(program)
                status = c.c_int()
                program_status(program, 0x8B82, c.byref(status))
                if not status.value:
                    log = c.create_string_buffer(32768)
                    program_log(program, len(log), None, log)
                    raise RuntimeError(f'{vertex}\n{log.value.decode()}')
                delete_program(program)
                delete_shader(vs)
                delete_shader(fs)
                total += 1
        print(f'PASS: {name}, with/without DH', flush=True)
        if '--advanced' in sys.argv:
            for compute in sorted(ROOT.rglob('*.csh')):
                if compute.parent.name in ('lib','program'): continue
                for dh in (False,True):
                    cs=compile_one(compute,values,dh)
                    program=create_program();attach(program,cs);link(program)
                    status=c.c_int();program_status(program,0x8B82,c.byref(status))
                    if not status.value:
                        log=c.create_string_buffer(32768);program_log(program,len(log),None,log)
                        raise RuntimeError(f'{compute}\n{log.value.decode()}')
                    delete_program(program);delete_shader(cs);total+=1
    if total:
        print(f'PASS: {total} program variants compiled and linked', flush=True)
    if '--smoke-only' in sys.argv:
        if '--advanced' in sys.argv:
            import smoke_checks
            smoke_checks.run(globals())
        sys.exit(0)
    import shadow_checks
    shadow_checks.run(globals())
    if '--shadow-only' in sys.argv:
        sys.exit(0)
    if '--aquatic-only' in sys.argv:
        import aquatic_geometry_checks
        aquatic_geometry_checks.run(globals())
        sys.exit(0)
    if '--water-lod-only' in sys.argv:
        import water_lod_overlap_checks
        water_lod_overlap_checks.run(globals())
        sys.exit(0)
    if '--water-only' in sys.argv:
        import weather_checks
        weather_checks.run(globals())
        import water_surface_checks
        water_surface_checks.run(globals())
        import water_vertex_checks
        water_vertex_checks.run(globals())
        import water_motion_checks
        water_motion_checks.run(globals())
        import water_optics_checks
        water_optics_checks.run(globals())
        import water_lod_overlap_checks
        water_lod_overlap_checks.run(globals())
        import aquatic_geometry_checks
        aquatic_geometry_checks.run(globals())
        sys.exit(0)
    import low_tier_checks
    low_tier_checks.run(globals())
    import render_checks
    render_checks.run(globals())
    import quality_checks
    quality_checks.run(globals())
    import weather_checks
    weather_checks.run(globals())
    import realism_checks
    realism_checks.run(globals())
    import water_surface_checks
    water_surface_checks.run(globals())
    import water_vertex_checks
    water_vertex_checks.run(globals())
    import water_optics_checks
    water_optics_checks.run(globals())
    import water_lod_overlap_checks
    water_lod_overlap_checks.run(globals())
    import aquatic_geometry_checks
    aquatic_geometry_checks.run(globals())
    import pom_checks
    pom_checks.run(globals())
    import dh_checks
    dh_checks.run(globals())
    if "--dh-benchmark" in sys.argv:
        dh_checks.benchmark(globals())
    import photoreal_checks
    photoreal_checks.run(globals())
    import ray_tracing_checks
    ray_tracing_checks.run(globals())
    import celestial_checks
    celestial_checks.run(globals())
    if '--advanced' in sys.argv:
        import advanced_checks
        advanced_checks.run(globals())
        import smoke_checks
        smoke_checks.run(globals())
finally:
    driver.close()

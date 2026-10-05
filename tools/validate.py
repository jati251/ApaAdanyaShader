#!/usr/bin/env python3
"""Validate real preset values and compile/link with the local OpenGL driver.

Compatibility builtins are bridged to core inputs, as Iris does at runtime.
This catches GLSL errors, not Iris framebuffer/texture binding errors.
"""
import ctypes as c
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

def resolve(name, stack=()):
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
print(f'PASS: {len(profiles)} complete profiles, legal option values, both translations', flush=True)
all_source = '\n'.join(p.read_text() for p in ROOT.rglob('*') if p.suffix in ('.glsl','.fsh','.vsh'))
for key,(value,_) in options.items():
    if isinstance(value,bool):
        assert re.search(r'#ifn?def\s+'+key+r'\b',all_source), f'{key}: option not discoverable by Iris'
for directory in ('world-1','world1'):
    for entry in ROOT.glob('*sh'):
        assert (ROOT/directory/entry.name).exists(), f'{directory}: missing {entry.name}'

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
    code = code.replace('#version 330 compatibility', '#version '+CORE_VERSION+' core')
    builtins = '''
#define RGBA8 32856
#define RGBA16F 34842
#define R16F 33325
uniform mat4 aa_ModelView, aa_Projection, aa_TextureMatrix[8];
uniform mat3 aa_NormalMatrix;
'''
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
    for old, new in {'gl_ModelViewMatrix':'aa_ModelView','gl_ProjectionMatrix':'aa_Projection','gl_TextureMatrix':'aa_TextureMatrix','gl_NormalMatrix':'aa_NormalMatrix','gl_Vertex':'aa_Vertex','gl_Color':'aa_Color','gl_MultiTexCoord0':'aa_MultiTexCoord0','gl_MultiTexCoord1':'aa_MultiTexCoord1','gl_Normal':'aa_Normal','ftransform':'aa_ftransform'}.items():
        code = re.sub(r'\b' + old + r'\b', new, code)
    return code.replace('#version '+CORE_VERSION+' core', '#version '+CORE_VERSION+' core\n' + builtins, 1)

def compile_one(path, values, dh):
    shader = create_shader(0x8B31 if path.suffix == '.vsh' else 0x8B30)
    text = c.c_char_p(source(path, values, dh).encode())
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
    if '--images-only' in sys.argv:
        variants = []
    for name, values in variants:
        for dh in (False, True):
            for vertex in sorted(ROOT.rglob('*.vsh')):
                if vertex.parent.name in ('program', 'lib'):
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
    if total:
        print(f'PASS: {total} program variants compiled and linked', flush=True)
    import render_checks
    render_checks.run(globals())
    import quality_checks
    quality_checks.run(globals())
    import weather_checks
    weather_checks.run(globals())
    import pom_checks
    pom_checks.run(globals())
finally:
    driver.close()

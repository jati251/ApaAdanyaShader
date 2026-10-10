"""Write complete preset exports from the four menu profile declarations."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
EXPORTS = {
    'POTATO': ('Lightweight', 'Lightweight.txt'),
    'MEDIUM': ('Balanced', 'Balanced.txt'),
    'HIGH': ('Detailed', 'Detailed.txt'),
    'EXTREME': ('Extreme', 'Extreme.txt'),
}

def main():
    profiles = {}
    source = (ROOT/'shaders/shaders.properties').read_text(encoding='utf-8')
    for name, declaration in re.findall(r'^profile\.(\w+)=(.*)$',source,re.M):
        options = {}
        for token in declaration.split():
            if token.startswith('profile.'):
                options.update(profiles[token[8:]])
            elif ':' in token:
                key, value = token.split(':',1)
                options[key] = value
            else:
                options[token.lstrip('!')] = 'false' if token.startswith('!') else 'true'
        profiles[name] = options
    for name, (label, filename) in EXPORTS.items():
        lines = [f'# Profile: {name}', f'# {label}']
        lines += [f'{key}={value}' for key,value in sorted(profiles[name].items())]
        (ROOT/'presets'/filename).write_text('\n'.join(lines)+'\n',encoding='utf-8')
        print(f'Wrote {filename}: {len(profiles[name])} options')

if __name__=='__main__':
    main()

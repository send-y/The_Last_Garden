"""Preserve original virtual dispatch when a module calls another facade method."""
import re
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.resolve().parents[1]
source = (HERE / 'first_night_simulation.before.gd').read_text(encoding='utf-8-sig')
types = dict(re.findall(r'^func (\w+)\([\s\S]*?\)\s*->\s*([^:]+):', source, re.M))
tokens = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|#[^\n]*|\b[A-Za-z_]\w*\b')
for path in (ROOT / 'game/src/simulation/systems').glob('*.gd'):
    text = path.read_text(encoding='utf-8')
    edits = []
    for match in tokens.finditer(text):
        name = match[0]
        if name not in types:
            continue
        prefix = text[:match.start()].rsplit('\n', 1)[-1].rstrip()
        if prefix.endswith('.') or prefix.endswith('func'):
            continue
        suffix = re.match(r'\(\s*sim\s*(,\s*|(?=\)))', text[match.end():])
        if not suffix:
            continue
        # New calendar-only implementation call has a notification argument
        # intentionally outside the old one-argument facade contract.
        if name == '_advance_clock' and path.stem == 'world_calendar':
            continue
        edits.append((match.start(), match.end() + suffix.end(), 'sim.' + name + '('))
    for start, end, replacement in reversed(edits):
        text = text[:start] + replacement + text[end:]
    def typed(match):
        return f'{match[1]}: {types[match[2]].strip()} = sim.{match[2]}('
    text = re.sub(r'(var\s+\w+)\s*:=\s*sim\.(\w+)\(', typed, text)
    path.write_text(text, encoding='utf-8')
print('Restored facade dispatch for extracted methods')

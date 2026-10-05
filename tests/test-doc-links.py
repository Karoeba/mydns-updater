from pathlib import Path
import re
import unicodedata

root = Path(__file__).resolve().parents[1]
def slug(text):
    text = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', text).replace('`', '').lower()
    return ''.join(c for c in text if c in '-_ ' or not unicodedata.category(c).startswith(('P', 'S'))).replace(' ', '-')

def headings(text):
    found = set()
    for line in text.splitlines():
        if re.match(r'^#{1,6} ', line):
            name = slug(re.sub(r'^#+ ', '', line))
            target = name
            n = 0
            while target in found:
                n += 1
                target = f'{name}-{n}'
            found.add(target)
    return found

issues = []
blocks = 0
for path in [root / 'README.md', *sorted((root / 'docs').rglob('*.md'))]:
    source = path.read_text(encoding='utf-8')
    fences = re.findall(r'^```.*$', source, re.M)
    if len(fences) % 2:
        issues.append(f'{path.relative_to(root)}: unpaired fence')
    blocks += len(re.findall(r'^```(?:sh|bash)\s*$', source, re.M))
    for match in re.finditer(r'\]\(([^)\s]+)\)', source):
        link = match[1]
        if re.match(r'^[a-z]+:', link):
            continue
        name, _, anchor = link.partition('#')
        dest = (path.parent / name) if name else path
        if not dest.exists():
            issues.append(f'{path.relative_to(root)} -> {link}: missing file')
        elif anchor and dest.suffix == '.md' and anchor not in headings(dest.read_text(encoding='utf-8')):
            issues.append(f'{path.relative_to(root)} -> {link}: missing heading')
print(f'Documented shell blocks: {blocks}')
for issue in issues:
    print(issue)
print(f'Link/fence issues: {len(issues)}')
raise SystemExit(bool(issues))

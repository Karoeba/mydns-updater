"""Check current install instructions, deliberately excluding historical records."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PAGES = ['current-version', 'docker', 'synology', 'linux', 'docker-recovery',
         'docker-systemd-recovery', 'synology-recovery', 'linux-recovery',
         'docker-testing', 'linux-testing']

def check(texts, version):
    errors = []
    expected_branch = 'v1.11.0-image-package'
    for page in ['current-version', 'docker', 'linux']:
        if f'--branch {expected_branch} --single-branch' not in texts[f'docs/{page}.md']:
            errors.append(f'{page}: acquisition branch differs from trial target')
    for page in ['current-version', 'synology', 'synology-recovery']:
        if f'refs/heads/{expected_branch}.zip' not in texts[f'docs/{page}.md']:
            errors.append(f'{page}: acquisition ZIP differs from trial target')
    if 'まだmainにありません' in texts['README.md'] or 'review-fixes-v1.10.1ブランチを取得' in texts['README.md']:
        errors.append('README: stale unmerged instruction')
    for page in PAGES:
        path = f'docs/{page}.md'
        source = texts[path]
        if f'<!-- current-version: {version} -->' not in source:
            errors.append(f'{path}: current-version marker differs from update.sh')
        if page != 'current-version' and '(current-version.md)' not in source:
            errors.append(f'{path}: missing acquisition/preservation guide')
        if f'**v{version}**' not in source:
            errors.append(f'{path}: visible target version differs')
        # Match current success/placement instructions, not feature-introduction history.
        patterns = [r'バージョン(?:は|が)\s*`?v?(\d+\.\d+\.\d+)',
                    r'版が\s*`?v?(\d+\.\d+\.\d+)',
                    r'起動(?:ログ|バージョン)が\s*`?v?(\d+\.\d+\.\d+)',
                    r'同じv(\d+\.\d+\.\d+)のupdate',
                    r'プログラム一式をv(\d+\.\d+\.\d+)に',
                    r'STARTUPが\s*`v(\d+\.\d+\.\d+)',
                    r'MyDNS updater v(\d+\.\d+\.\d+) started']
        for pattern in patterns:
            for match in re.finditer(pattern, source):
                if match[1] != version:
                    errors.append(f'{path}: stale expectation {match[0]}')
    return errors

if __name__ == '__main__':
    version = re.search(r'^VERSION="([^"]+)"', (ROOT/'update.sh').read_text(), re.M)[1]
    paths = ['README.md', *(f'docs/{p}.md' for p in PAGES)]
    texts = {p: (ROOT/p).read_text(encoding='utf-8') for p in paths}
    errors = check(texts, version)
    # Ensure a future edit cannot silently disable either regression check.
    stale = dict(texts)
    stale['README.md'] += '\n検証中の版はまだmainにありません。'
    assert check(stale, version), 'missing stale-main detection'
    stale = dict(texts)
    stale['docs/docker.md'] += '\n起動ログがv0.0.0なら成功です。'
    assert check(stale, version), 'missing stale-startup detection'
    for error in errors:
        print(error)
    print(f'Current version {version}: checked {len(paths)} documents; errors={len(errors)}')
    raise SystemExit(bool(errors))

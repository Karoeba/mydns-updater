"""Exercise real built images with isolated mounts and mock HTTP; no real accounts."""
from pathlib import Path
import json
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]

def docker(*args):
    return subprocess.check_output(['docker', *map(str, args)], text=True).strip()

def wait_for(container, text):
    for _ in range(40):
        log = docker('logs', container)
        if text in log:
            return log
        time.sleep(1)
    raise AssertionError(f'{text} missing: {log}')

def main():
    tag = 'mydns-package-test:' + uuid.uuid4().hex
    containers = []
    try:
        with tempfile.TemporaryDirectory() as temporary:
            task = Path(temporary)
            context = task/'build'
            context.mkdir()
            for name in ['Dockerfile', '.dockerignore', 'update.sh']:
                shutil.copy2(ROOT/name, context/name)
            shutil.copytree(ROOT/'lib', context/'lib')
            canary = 'PRIVATE-FIXTURE-' + uuid.uuid4().hex
            for name in ['config/accounts.conf', 'state/state.conf', 'recovery/status',
                         '.env', 'accounts.conf.example', 'lib/private.txt', 'lib/private.sh', 'lib/nested/private.txt', 'tests/private.txt']:
                path = context/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(canary)
            docker('build', '-t', tag, context)
            info = json.loads(docker('image', 'inspect', tag))[0]['Config']
            assert info['Cmd'] == ['sh', '/app/update.sh']
            assert 'update.sh --healthcheck' in ' '.join(info['Healthcheck']['Test'])
            inspection = docker('create', tag)
            containers.append(inspection)
            exported = task/'image.tar'
            docker('export', '-o', exported, inspection)
            with tarfile.open(exported) as archive:
                for name in ['update.sh', *('lib/'+p.name for p in (ROOT/'lib').glob('*.sh'))]:
                    assert archive.extractfile('app/'+name).read() == (ROOT/name).read_bytes()
                for member in archive:
                    if member.isfile():
                        assert canary.encode() not in archive.extractfile(member).read(), member.name
            print('PASS: image contains exact common code, default startup and healthcheck; private fixtures excluded')

            config, state, mock, legacy = (task/x for x in ['config', 'state', 'bin', 'legacy'])
            for directory in [config, state, mock, legacy]:
                directory.mkdir()
            (config/'mydns.conf').write_text('DEBUG=1\nCHECK_INTERVAL=300\nFORCE_UPDATE_INTERVAL=86400\n')
            (config/'accounts.conf').write_text('[1]\nID=dummy\nPASSWORD=dummy\nDOMAIN=test.example\n')
            state_file = state/'state.conf'
            state_file.write_text(f'LAST_IPV4=203.0.113.10\n\n[1]\nLAST_IPV4=203.0.113.10\nLAST_UPDATE={int(time.time())}\n')
            original_state = state_file.read_bytes()
            original_config = {p.name: p.read_bytes() for p in config.iterdir()}
            curl = mock/'curl'
            curl.write_text('''#!/bin/sh
output=''
while [ "$#" -gt 0 ]; do
    case "$1" in --output) output="$2"; shift ;; https://*) url="$1" ;; esac
    shift
done
case "$url" in
    */login.html) echo 'Login and IP address notify OK.' > "$output" ;;
    *) echo 203.0.113.10 > "$output" ;;
esac
printf 200
''')
            curl.chmod(0o755)
            version = re.search(r'^VERSION="([^"]+)"', (ROOT/'update.sh').read_text(), re.M)[1]
            (legacy/'update.sh').write_text((ROOT/'update.sh').read_text().replace(f'VERSION="{version}"', 'VERSION="1.10.1"'))
            shutil.copytree(ROOT/'lib', legacy/'lib')

            def start(old=False):
                args = ['run', '-d', '--network', 'none', '--health-interval=1s', '--health-start-period=1s',
                        '-v', f'{config}:/config:ro', '-v', f'{state}:/state', '-v', f'{mock}:/mock:ro',
                        '-e', 'PATH=/mock:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin']
                if old:
                    args += ['-v', f'{legacy}/update.sh:/app/update.sh:ro', '-v', f'{legacy}/lib:/app/lib:ro']
                container = docker(*args, tag)  # Test image CMD, no explicit replacement command.
                containers.append(container)
                log = wait_for(container, 'force update not due')
                assert f'v{"1.10.1" if old else version} started' in log
                assert 'MyDNS update: OK' not in log
                for _ in range(30):
                    if docker('inspect', '-f', '{{.State.Health.Status}}', container) == 'healthy':
                        break
                    time.sleep(1)
                else:
                    raise AssertionError('healthcheck did not become healthy')
                # Production writes state with root-only permissions. Read through
                # the container instead of weakening the file for the host test user.
                assert subprocess.check_output(['docker', 'exec', container, 'cat', '/state/state.conf']) == original_state
                assert {p.name: p.read_bytes() for p in config.iterdir()} == original_config
                return container

            old = start(old=True)
            docker('stop', '-t', '5', old)
            new = start()
            mounts = json.loads(docker('inspect', new))[0]['Mounts']
            assert not any(m['Destination'].startswith('/app') for m in mounts)
            docker('stop', '-t', '5', new)
            # Roll back to the old bind layout without reverting successful state.
            rollback = start(old=True)
            docker('stop', '-t', '5', rollback)
            print('PASS: legacy bind layout -> packaged startup -> rollback preserves config/state and avoids duplicate notification')

            compose = json.loads(docker('compose', '-f', ROOT/'compose.yaml', 'config', '--format', 'json'))
            destinations = {v['target'] for v in compose['services']['mydns-updater']['volumes']}
            assert destinations == {'/config', '/state'}, destinations
            print('PASS: production Compose exposes only configuration and state mounts')
    finally:
        for container in containers:
            subprocess.run(['docker', 'rm', '-f', container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['docker', 'image', 'rm', tag], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if __name__ == '__main__':
    main()

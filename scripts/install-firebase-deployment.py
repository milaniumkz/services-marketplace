#!/usr/bin/env python3
"""Run as root over the existing verified SSH deployment channel."""
import json
import os
from pathlib import Path
import sys


def install(source, root=Path('/etc/joba')):
    source, root = Path(source), Path(root)
    account = json.loads((source / 'service-account.json').read_text())
    config = json.loads((source / 'client-config.json').read_text())
    if account.get('project_id') != 'joba-832c7' or config.get('platforms', {}).get('web', {}).get('projectId') != 'joba-832c7':
        raise ValueError('Project mismatch')
    # The bind mount exposes only this directory, never the production.env file.
    target = root / 'firebase'
    target.mkdir(mode=0o700, exist_ok=True)
    if target.is_symlink():
        raise ValueError('Unexpected configuration directory')
    os.chown(target, 1000, 1000)
    os.chmod(target, 0o700)
    for name in ['service-account.json', 'client-config.json']:
        temporary = target / ('.' + name + '.new')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write((source / name).read_bytes())
                stream.flush()
                os.fsync(stream.fileno())
            os.chown(temporary, 1000, 1000)
            os.replace(temporary, target / name)
        finally:
            temporary.unlink(missing_ok=True)
    environment = root / 'production.env'
    lines = [line for line in environment.read_text().splitlines() if not line.startswith('JOBA_FIREBASE_ENABLED=')]
    temporary = root / '.production.env.firebase.new'
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write('\n'.join(lines + ['JOBA_FIREBASE_ENABLED=1', '']))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, environment)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        install(sys.argv[1])
        print('Firebase configuration installed; deployment will recreate API')
    except Exception:
        print('Firebase installation failed; inspect file permissions without exposing credentials', file=sys.stderr)
        sys.exit(1)

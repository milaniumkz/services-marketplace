#!/usr/bin/env python3
"""Materialize explicit Firebase Actions secrets into private ephemeral files.
Never prints values; an empty configuration preserves the current server setup.
"""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys

NAMES = ('JOBA_FIREBASE_SERVICE_ACCOUNT_JSON', 'JOBA_FIREBASE_WEB_CONFIG', 'JOBA_FIREBASE_VAPID_KEY')
PROJECT = 'joba-832c7'


def prepare(env, destination):
    values = [env.get(name, '').strip() for name in NAMES]
    if values[0] or values[2]:
        values[1] = values[1] or json.dumps(json.loads((Path(__file__).resolve().parent.parent / 'services/api/firebase-client-config.json').read_text())['web'])
    if not any(values):
        return False
    if not all(values):
        raise ValueError('Set all three Firebase secrets: ' + ', '.join(NAMES))
    account = json.loads(values[0])
    web = json.loads(values[1])
    vapid = values[2]
    if account.get('type') != 'service_account' or account.get('project_id') != PROJECT or not account.get('client_email', '').endswith('.iam.gserviceaccount.com'):
        raise ValueError('Invalid Firebase service account project or type')
    if account.get('token_uri') != 'https://oauth2.googleapis.com/token':
        raise ValueError('Unexpected Google token endpoint')
    key = account.get('private_key', '')
    checked = subprocess.run(['openssl', 'pkey', '-check', '-noout'], input=key.encode(), capture_output=True)
    if checked.returncode:
        raise ValueError('Invalid Firebase service-account private key')
    if web.get('projectId') != PROJECT or web.get('messagingSenderId') != '105743015687' or ':web:' not in web.get('appId', '') or not web.get('apiKey'):
        raise ValueError('Invalid Firebase Web configuration for JOBA')
    if any(c not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_' for c in vapid):
        raise ValueError('Invalid public VAPID key')
    decoded = base64.urlsafe_b64decode(vapid + '=' * (-len(vapid) % 4))
    if len(decoded) != 65 or decoded[0] != 4:
        raise ValueError('Invalid public VAPID key')
    allowed = ('apiKey', 'appId', 'messagingSenderId', 'projectId', 'authDomain', 'storageBucket')
    public = {'platforms': {'web': {k: web[k] for k in allowed if isinstance(web.get(k), str)}}, 'vapid_key': vapid}
    destination = Path(destination)
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    for name, value in [('service-account.json', account), ('client-config.json', public)]:
        fd = os.open(destination / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
    return True


if __name__ == '__main__':
    try:
        changed = prepare(os.environ, sys.argv[1])
        print('Firebase configuration staged securely' if changed else 'No Firebase secrets supplied; existing server configuration retained')
    except Exception:
        # Parser errors may quote inputs; only fixed text is safe in CI logs.
        print('Firebase configuration rejected. Check the three named secrets and the JOBA project.', file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Optional single-job encrypted BCC handoff when Actions Secrets cannot be written."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def context(request):
    return json.dumps({k: request[k] for k in ['run_id', 'commit', 'nonce', 'purpose']}, sort_keys=True, separators=(',', ':'))


def decrypt(private, request, envelope):
    aad = context(request)
    if envelope.get('aad') != aad:
        raise ValueError('Envelope belongs to another BCC setup job')
    result = subprocess.run(['node', str(Path(__file__).with_name('firebase-envelope.cjs'))], input=json.dumps({'mode': 'decrypt', 'private_path': str(private), 'aad': aad, 'envelope': envelope}).encode(), capture_output=True)
    if result.returncode:
        raise ValueError('BCC envelope cryptography failed')
    return json.loads(result.stdout)


def validate(payload, mode='sandbox'):
    if mode not in ('sandbox','production-pending','production') or payload.get('environment') != ('sandbox' if mode=='sandbox' else 'production'):
        raise ValueError('Bank environment differs from the explicitly selected handoff mode')
    if mode=='production-pending' and payload.get('callback_registered') is not False:
        raise ValueError('Pending configuration must not claim registered callbacks')
    with tempfile.TemporaryDirectory(prefix='joba-bcc-validation-') as directory:
        path = module('prepare-bcc-deployment').prepare(json.dumps(payload), directory, allow_pending_registration=mode=='production-pending')
        return json.loads(path.read_text())


def acquire():
    if os.environ.get('JOBA_BCC_HANDOFF') != '1':
        return
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('BCC handoff requires an Actions job')
    run_id = os.environ['GITHUB_RUN_ID'] + '-' + os.environ['GITHUB_RUN_ATTEMPT']
    repository = os.environ['GITHUB_REPOSITORY']
    headers = {'Authorization': 'Bearer ' + os.environ['GITHUB_TOKEN'], 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'joba-bcc-setup'}
    with tempfile.TemporaryDirectory(prefix='joba-bcc-recipient-') as directory:
        private, request = module('acquire-deployment-credential').challenge(Path(directory), run_id, os.environ['GITHUB_SHA'])
        request['purpose'] = 'bcc-config-v1'
        publication = {'name': 'bcc-key-' + run_id, 'head_sha': request['commit'], 'status': 'completed', 'conclusion': 'neutral', 'output': {'title': 'One-time BCC configuration public key', 'summary': json.dumps(request, separators=(',', ':'))}}
        http = urllib.request.Request('https://api.github.com/repos/' + repository + '/check-runs', method='POST', data=json.dumps(publication).encode(), headers=headers)
        with urllib.request.urlopen(http, timeout=20) as response:
            published = json.load(response)
        print('BCC public setup challenge published: ' + str(published['id']), flush=True)
        endpoint = 'https://api.github.com/repos/' + repository + '/contents/envelope.json?ref=deploy/bcc-credential-' + run_id
        deadline = time.monotonic() + 600
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(urllib.request.Request(endpoint, headers=headers), timeout=20) as response:
                    record = json.load(response)
                payload = decrypt(private, request, json.loads(base64.b64decode(record['content'])))
                mode=os.environ.get('JOBA_BCC_SETUP_MODE','sandbox')
                payload = validate(payload,mode)
                destination = Path(os.environ['RUNNER_TEMP']) / ('joba-bcc-' + os.environ['GITHUB_SHA'] + '.json')
                destination.write_text(json.dumps(payload))
                destination.chmod(0o600)
                with open(os.environ['GITHUB_ENV'], 'a') as stream:
                    stream.write('JOBA_BCC_PREPARED_FILE=' + str(destination) + '\n')
                    stream.write('JOBA_BCC_STAGE_ONLY=' + ('1' if mode=='production-pending' else '0') + '\n')
                print('BCC configuration received securely for this job', flush=True)
                return
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    raise ValueError('BCC envelope mailbox unavailable') from None
            time.sleep(5)
        raise ValueError('BCC setup envelope not supplied within 10 minutes')


if __name__ == '__main__':
    try:
        acquire()
    except Exception:
        print('Protected BCC setup failed; no credential values were logged', flush=True)
        raise SystemExit(1)

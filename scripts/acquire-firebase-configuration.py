#!/usr/bin/env python3
"""Optional single-job encrypted Firebase handoff when Actions Secrets cannot be written."""
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
        raise ValueError('Envelope belongs to another Firebase setup job')
    result = subprocess.run(['node', str(Path(__file__).with_name('firebase-envelope.cjs'))], input=json.dumps({'mode': 'decrypt', 'private_path': str(private), 'aad': aad, 'envelope': envelope}).encode(), capture_output=True)
    if result.returncode:
        raise ValueError('Firebase envelope cryptography failed')
    return json.loads(result.stdout)


def acquire():
    if os.environ.get('JOBA_FIREBASE_HANDOFF') != '1':
        return
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise ValueError('Firebase handoff requires an Actions job')
    run_id = os.environ['GITHUB_RUN_ID'] + '-' + os.environ['GITHUB_RUN_ATTEMPT']
    repository = os.environ['GITHUB_REPOSITORY']
    headers = {'Authorization': 'Bearer ' + os.environ['GITHUB_TOKEN'], 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'joba-firebase-setup'}
    with tempfile.TemporaryDirectory(prefix='joba-firebase-recipient-') as directory:
        private, request = module('acquire-deployment-credential').challenge(Path(directory), run_id, os.environ['GITHUB_SHA'])
        request['purpose'] = 'firebase-config-v1'
        publication = {'name': 'firebase-key-' + run_id, 'head_sha': request['commit'], 'status': 'completed', 'conclusion': 'neutral', 'output': {'title': 'One-time Firebase configuration public key', 'summary': json.dumps(request, separators=(',', ':'))}}
        http = urllib.request.Request('https://api.github.com/repos/' + repository + '/check-runs', method='POST', data=json.dumps(publication).encode(), headers=headers)
        with urllib.request.urlopen(http, timeout=20) as response:
            published = json.load(response)
        print('Firebase public setup challenge published: ' + str(published['id']), flush=True)
        endpoint = 'https://api.github.com/repos/' + repository + '/contents/envelope.json?ref=deploy/firebase-credential-' + run_id
        deadline = time.monotonic() + 600
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(urllib.request.Request(endpoint, headers=headers), timeout=20) as response:
                    record = json.load(response)
                payload = decrypt(private, request, json.loads(base64.b64decode(record['content'])))
                destination = Path(os.environ['RUNNER_TEMP']) / ('joba-firebase-' + os.environ['GITHUB_SHA'])
                module('prepare-firebase-deployment').prepare({'JOBA_FIREBASE_SERVICE_ACCOUNT_JSON': json.dumps(payload)}, destination)
                with open(os.environ['GITHUB_ENV'], 'a') as stream:
                    stream.write('JOBA_FIREBASE_PREPARED_DIR=' + str(destination) + '\n')
                print('Firebase configuration received securely for this job', flush=True)
                return
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    raise ValueError('Firebase envelope mailbox unavailable') from None
            time.sleep(5)
        raise ValueError('Firebase setup envelope not supplied within 10 minutes')


if __name__ == '__main__':
    try:
        acquire()
    except Exception:
        print('Protected Firebase setup failed; no credential values were logged', flush=True)
        raise SystemExit(1)

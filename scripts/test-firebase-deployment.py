import base64
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


prepare = module('prepare-firebase-deployment').prepare
install = module('install-firebase-deployment').install


class FirebaseDeployment(unittest.TestCase):
    def test_empty_preserves_existing_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'stage'
            self.assertFalse(prepare({}, target))
            self.assertFalse(target.exists())

    def test_partial_is_rejected_before_any_files_are_written(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'stage'
            with self.assertRaises(ValueError):
                prepare({'JOBA_FIREBASE_SERVICE_ACCOUNT_JSON': '{}'}, target)
            self.assertFalse(target.exists())

    def test_secure_stage_and_install_keep_private_key_out_of_public_config(self):
        key = subprocess.run(['openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048'], capture_output=True, check=True).stdout.decode()
        account = {'type': 'service_account', 'project_id': 'joba-832c7', 'client_email': 'isolated@joba-832c7.iam.gserviceaccount.com', 'private_key': key, 'token_uri': 'https://oauth2.googleapis.com/token'}
        vapid = base64.urlsafe_b64encode(b'\x04' + b'a' * 64).decode().rstrip('=')
        env = {'JOBA_FIREBASE_SERVICE_ACCOUNT_JSON': json.dumps(account), 'JOBA_FIREBASE_VAPID_KEY': vapid}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage = root / 'stage'
            self.assertTrue(prepare(env, stage))
            self.assertEqual(stat.S_IMODE(stage.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((stage / 'service-account.json').stat().st_mode), 0o600)
            public = (stage / 'client-config.json').read_text()
            self.assertNotIn('private_key', public)
            self.assertNotIn('BEGIN PRIVATE KEY', public)
            self.assertEqual(json.loads(public)['platforms']['web']['projectId'], 'joba-832c7')
            server = root / 'server'
            server.mkdir()
            (server / 'production.env').write_text('EXISTING_SETTING=keep\nJOBA_FIREBASE_ENABLED=0\n')
            with patch('os.chown'):
                install(stage, server)
            self.assertEqual((server / 'production.env').read_text(), 'EXISTING_SETTING=keep\nJOBA_FIREBASE_ENABLED=1\n')
            self.assertEqual(stat.S_IMODE((server / 'firebase/service-account.json').stat().st_mode), 0o400)
            self.assertEqual(stat.S_IMODE((server / 'production.env').stat().st_mode), 0o600)
            self.assertEqual(json.loads((server / 'firebase/service-account.json').read_text()), account)
            with patch('os.chown'):
                install(stage, server)
            self.assertEqual((server / 'production.env').read_text().count('JOBA_FIREBASE_ENABLED='), 1)

    def test_foreign_project_and_token_endpoint_are_rejected(self):
        for account in [{'type': 'service_account', 'project_id': 'foreign'}, {'type': 'service_account', 'project_id': 'joba-832c7', 'client_email': 'test@joba-832c7.iam.gserviceaccount.com', 'token_uri': 'https://evil.example'}]:
            with tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / 'stage'
                with self.assertRaises(ValueError):
                    prepare({'JOBA_FIREBASE_SERVICE_ACCOUNT_JSON': json.dumps(account), 'JOBA_FIREBASE_VAPID_KEY': 'placeholder'}, target)
                self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()

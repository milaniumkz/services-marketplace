"""Build a signed Play bundle using private, local upload credentials."""
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
credentials = Path(os.environ.get('JOBA_SIGNING_CONFIG', str(Path.home() / '.joba-publication/android-signing.json')))
config = json.loads(credentials.read_text())
env = dict(os.environ, JOBA_UPLOAD_KEYSTORE=config['keystore'],
           JOBA_UPLOAD_STORE_PASSWORD=config['store_password'],
           JOBA_UPLOAD_KEY_ALIAS=config['alias'], JOBA_UPLOAD_KEY_PASSWORD=config['key_password'])
flutter = Path(os.environ.get('FLUTTER_ROOT', str(Path.home() / 'flutter-sdk/flutter'))) / 'bin/flutter'
subprocess.run([str(flutter), 'build', 'appbundle', '--release', '--no-pub',
                '--dart-define=JOBA_FREE_MOBILE=false',
                '--dart-define=JOBA_API_URL=https://joba.com.kz'],
               cwd=root / 'apps/mobile', env=env, check=True)

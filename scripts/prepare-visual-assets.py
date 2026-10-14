"""Rasterize supplied prototype illustrations for isolated UI tests only."""
import argparse
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(root / 'docs/design/packages/JOBA_Mobile_Prototype.zip') as package:
    for name in ['interior', 'kitchen']:
        entry = next(p for p in package.namelist() if p.endswith('/mobile/assets/' + name + '.svg'))
        source = args.output / ('reference-' + name + '.svg')
        target = args.output / ('joba-visual-' + name + '.png')
        source.write_bytes(package.read(entry))
        subprocess.run(['node', '-e', "require('sharp')(process.argv[1]).resize(520,300).png().toFile(process.argv[2]).catch(error=>{console.error(error.message);process.exitCode=1;});", str(source.resolve()), str(target.resolve())], cwd=root, check=True)
print('Prepared original prototype illustrations for isolated visual fixtures.')

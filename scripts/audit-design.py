"""Inventory original design controls; absence of an audit never means acceptance."""
import json
import re
import zipfile
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Controls(HTMLParser):
    def __init__(self):
        super().__init__()
        self.controls = []
        self.stack = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for item in self.stack:
            item['depth'] += 1
        if tag in ('button', 'a', 'input', 'select', 'textarea'):
            item = {'tag': tag, 'attributes': {
                key: value for key, value in attrs.items()
                if key in ('type', 'name', 'id', 'href', 'data-action',
                           'placeholder', 'required', 'disabled', 'aria-label')
            }, 'label': '', 'depth': 0}
            self.controls.append(item)
            if tag != 'input':
                self.stack.append(item)
        if tag in ('input', 'img', 'br', 'hr', 'meta', 'link'):
            for item in self.stack:
                item['depth'] -= 1

    def handle_endtag(self, tag):
        self.stack = [item for item in self.stack
                      if not (item['tag'] == tag and item['depth'] == 0)]
        for item in self.stack:
            item['depth'] -= 1

    def handle_data(self, data):
        if data.strip():
            for item in self.stack:
                item['label'] += ' ' + data.strip()


mobile = (ROOT / 'apps/mobile/lib/screens/marketplace.dart').read_text()
routes = set(re.findall(r"case '([^']+)':", mobile))
aliases = {'executor-home': 'home'}
catalogue = []
for package in ('JOBA_Mobile_Prototype', 'JOBA_Admin_Web_Prototype'):
    with zipfile.ZipFile(ROOT / 'docs/design/packages' / (package + '.zip')) as archive:
        manifest_name = next(name for name in archive.namelist()
                             if name.endswith('/screen_manifest.json'))
        prefix = manifest_name.removesuffix('screen_manifest.json')
        manifest = json.loads(archive.read(manifest_name))
        roots = {item['route_key']: item['id'] for item in manifest['roots']}
        for frame in manifest['frames']:
            parser = Controls()
            parser.feed(archive.read(prefix + frame['html']).decode())
            controls = []
            for control in parser.controls:
                control.pop('depth')
                control['label'] = ' '.join(control['label'].split())
                controls.append(control)
            key = frame['route_key']
            route = aliases.get(key, key) if frame['surface'] == 'mobile' else None
            catalogue.append({
                'id': frame['id'], 'surface': frame['surface'],
                'title': frame['title'], 'design_route': key,
                'root': key in roots,
                'reference_html': frame['html'], 'reference_png': frame['png'],
                'viewport': frame['viewport'],
                'native_route': route if route in routes else None,
                'controls': controls,
                'visual_acceptance': 'pending',
                'functional_acceptance': 'pending',
            })
result = {
    'source': 'Original repository design ZIP packages',
    'scope': '42 mobile + 22 admin + 5 public roots, including packaged states',
    'rule': 'Route detection is inventory only; it does not prove appearance or functionality.',
    'frames': catalogue,
}
target = ROOT / 'docs/design/screen-audit.json'
target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(f'Inventoried {len(catalogue)} frames, '
      f'{sum(len(frame["controls"]) for frame in catalogue)} controls. '
      'All acceptance results remain pending until verified.')

"""Compare captured UI with original packaged references; never infer acceptance."""
import argparse
import json
import re
import zipfile
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--captures', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--surface', choices=['mobile', 'admin', 'public'], default='mobile')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
frames = json.loads((ROOT / 'docs/design/screen-audit.json').read_text())['frames']
inventory_path = args.captures / 'inventory.json'
captures = json.loads(inventory_path.read_text())['frames'] if inventory_path.exists() else []
lookup = {(f['id'], f['route']): f for f in captures}
packages = [zipfile.ZipFile(p) for p in (ROOT / 'docs/design/packages').glob('*.zip')]
results = []
sheets = []
try:
    for frame in sorted((f for f in frames if f['surface'] == args.surface), key=lambda f: (f['id'], f['design_route'])):
        captured = lookup.get((frame['id'], frame['design_route']))
        record = {'id': frame['id'], 'route': frame['design_route'], 'reference': frame['reference_png'], 'visual_acceptance': 'pending', 'status': 'not_captured'}
        if captured is None:
            results.append(record)
            continue
        path = args.captures / captured['capture']
        if not path.is_file():
            record['status'] = 'capture_missing'
            results.append(record)
            continue
        slug = re.sub(r'[^a-zA-Z0-9._-]', '-', frame['id'] + '-' + frame['design_route'])
        original = None
        for package in packages:
            names = [n for n in package.namelist() if n.endswith('/' + frame['reference_png'])]
            if names:
                reference = args.output / (slug + '-reference.png')
                reference.write_bytes(package.read(names[0]))
                original = Image.open(reference).convert('RGB')
                break
        if original is None:
            record['status'] = 'reference_missing'
            results.append(record)
            continue
        actual = Image.open(path).convert('RGB')
        record.update({'status': 'review_required', 'capture': str(path), 'actual_route': captured.get('actual_route', captured['route']), 'errors': captured.get('errors', []), 'reference_size': original.size, 'capture_size': actual.size})
        if original.size != actual.size:
            record['status'] = 'dimension_mismatch'
            results.append(record)
            continue
        # Native system status/gesture areas are drawn by the OS, not by the app.
        top, bottom = (86, 44) if args.surface == 'mobile' else (0, 0)
        bounds = (0, top, original.width, original.height - bottom)
        diff = ImageChops.difference(original.crop(bounds), actual.crop(bounds))
        pixels = diff.get_flattened_data() if hasattr(diff, 'get_flattened_data') else diff.getdata()
        mismatch = sum(max(pixel) > 16 for pixel in pixels)
        record['different_pixels_ratio'] = round(mismatch / (diff.width * diff.height), 6)
        record['excluded_system_rows'] = {'top': top, 'bottom': bottom}
        record['note'] = 'Dynamic text/data and rasterization also affect this metric; no automatic pass.'
        # These are analysis figures. Original and captured PNGs remain unchanged.
        chart = Image.new('RGB', (original.width * 3, original.height + 42), 'white')
        chart.paste(original, (0, 42)); chart.paste(actual, (original.width, 42))
        chart.paste(diff, (original.width * 2, 42 + top))
        draw = ImageDraw.Draw(chart)
        draw.text((8, 10), slug + ' / ORIGINAL', fill='black')
        draw.text((original.width + 8, 10), 'CAPTURE / pending review', fill='black')
        draw.text((original.width * 2 + 8, 10), 'ABSOLUTE PIXEL DIFFERENCE', fill='black')
        chart_path = args.output / (slug + '-comparison.png')
        chart.save(chart_path)
        sheets.append((chart_path, chart.size))
        chart.close()
        results.append(record)
    report = {'surface': args.surface, 'rule': 'All frames remain pending until visual and functional review. Missing captures are not matches.', 'frames': results}
    (args.output / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    for index in range(0, len(sheets), 4):
        batch = sheets[index:index + 4]
        width = max(size[0] for _, size in batch) // 2
        height = sum(size[1] // 2 for _, size in batch)
        contact = Image.new('RGB', (width, height), 'white')
        offset = 0
        for chart_path, size in batch:
            with Image.open(chart_path) as chart:
                thumb = chart.resize((size[0] // 2, size[1] // 2))
                contact.paste(thumb, (0, offset)); offset += thumb.height
                thumb.close()
        contact.save(args.output / ('contact-%02d.png' % (index // 4 + 1)))
        contact.close()
    print(json.dumps({'frames': len(results), 'captured': len(sheets), 'missing': sum(r['status'] == 'not_captured' for r in results), 'acceptance': 'pending'}))
finally:
    for package in packages:
        package.close()

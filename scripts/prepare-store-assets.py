"""Compose store artwork from actual Flutter captures; never fabricate app UI."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'store-assets'
FONTS = ROOT / 'apps/mobile/assets'
BLUE, NAVY, YELLOW = '#245BDC', '#192D50', '#FFDC5C'
SCREENS = [
    ('01-find', 'S06-home', ['Хорошие мастера.', 'Ваши задачи.'], 'Услуги для дома, работы и жизни'),
    ('02-search', 'store-search', ['Найдите своего', 'специалиста'], 'Категории, город и удобный поиск'),
    ('03-orders', 'store-orders', ['Задачи под', 'контролем'], 'Ваши заказы и их текущий статус'),
    ('04-work', 'S09-executor-home', ['Ваш следующий', 'заказ — в JOBA'], 'Находите задачи по своим услугам'),
    ('05-profile', 'S11-account', ['Две роли.', 'Один аккаунт.'], 'Заказывайте услуги и предлагайте свои'),
]


def font(size, bold=False):
    return ImageFont.truetype(str(FONTS / ('NotoSans-Bold.ttf' if bold else 'NotoSans-Regular.ttf')), size)


def card(width, height, screen, headlines, subtitle, index):
    scale = width / 1320
    def n(value): return round(value * scale)
    canvas = Image.new('RGB', (width, height), '#F2F5FF')
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((n(920), n(-230), n(1570), n(420)), fill=YELLOW)
    draw.text((n(90), n(80)), 'JOBA', font=font(n(72), True), fill=BLUE)
    draw.ellipse((n(300), n(134), n(316), n(150)), fill=YELLOW)
    draw.text((width - n(155), n(103)), f'{index:02d}', font=font(n(31), True), fill=NAVY)
    y = n(230)
    for line in headlines:
        draw.text((n(90), y), line, font=font(n(88), True), fill=NAVY)
        y += n(118)
    draw.text((n(94), y + n(28)), subtitle, font=font(n(37)), fill='#526786')
    raw = Image.open(OUT / 'raw' / (screen + '.png')).convert('RGB')
    # Preserve the complete captured screen, its proportions and readable UI.
    phone_width = n(1050)
    top = n(640)
    phone_height = round(phone_width * raw.height / raw.width)
    available = height - top - n(90)
    if phone_height > available:
        phone_height = available
        phone_width = round(phone_height * raw.width / raw.height)
    x = (width - phone_width) // 2
    shadow = Image.new('RGBA', canvas.size)
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x-n(16), top+n(12), x+phone_width+n(16), top+phone_height+n(32)), radius=n(58), fill=(23,43,83,65))
    canvas = Image.alpha_composite(canvas.convert('RGBA'), shadow.filter(ImageFilter.GaussianBlur(n(28))))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x-n(10), top-n(10), x+phone_width+n(10), top+phone_height+n(10)), radius=n(50), fill=NAVY)
    mask = Image.new('L', (phone_width, phone_height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,phone_width,phone_height), radius=n(40), fill=255)
    canvas.paste(raw.resize((phone_width,phone_height), Image.Resampling.LANCZOS), (x,top), mask)
    return canvas.convert('RGB')


def main():
    metadata = json.loads((OUT / 'metadata/ru-RU.json').read_text())
    for key, limit in {'name':30,'subtitle':30,'short_description':80,'promotional_text':170,'keywords':100,'description':4000}.items():
        assert len(metadata[key]) <= limit, (key, len(metadata[key]), limit)
    files = []
    for folder, dimensions in [('apple-iphone-6.9', (1320,2868)), ('apple-iphone-6.3', (1206,2622)), ('google-phone', (1080,1920))]:
        target = OUT / 'screenshots' / folder
        target.mkdir(parents=True, exist_ok=True)
        for index, (name, screen, headline, subtitle) in enumerate(SCREENS, 1):
            path = target / (name + '.png')
            card(*dimensions, screen, headline, subtitle, index).save(path, optimize=True)
            files.append(path)
    graphics = OUT / 'graphics'
    graphics.mkdir(exist_ok=True)
    feature = Image.new('RGB', (1024,500), BLUE)
    draw = ImageDraw.Draw(feature)
    draw.ellipse((765,-150,1180,265), fill=YELLOW)
    draw.text((64,45), 'JOBA', font=font(82,True), fill='white')
    draw.text((64,190), 'Хорошие мастера.', font=font(58,True), fill='white')
    draw.text((64,265), 'Ваши задачи.', font=font(58,True), fill='white')
    draw.text((67,389), 'Услуги · специалисты · заказы', font=font(30), fill='white')
    feature.save(graphics / 'google-feature-1024x500.png')
    for name in ['app-store-1024.png','google-play-512.png']:
        Image.open(ROOT / 'branding' / name).convert('RGB').save(graphics / name)
    ipad = OUT / 'raw-ipad'
    if ipad.exists():
        target = OUT / 'screenshots/apple-ipad-13'
        target.mkdir(parents=True, exist_ok=True)
        for name, screen, _, _ in SCREENS:
            image = Image.open(ipad / (screen + '.png')).convert('RGB')
            assert image.size == (2064,2752), image.size
            path = target / (name + '.png')
            image.save(path,optimize=True)
            files.append(path)
    preview = Image.new('RGB', (330*5,717), 'white')
    for index, path in enumerate(files[:5]):
        preview.paste(Image.open(path).resize((330,717),Image.Resampling.LANCZOS),(330*index,0))
    preview.save(OUT / 'preview.jpg', quality=92)
    manifest = {str(p.relative_to(OUT)): {'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'dimensions':Image.open(p).size} for p in files+list(graphics.glob('*.png'))}
    (OUT / 'asset-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Verified metadata limits; exported', len(files), 'screenshots and', len(list(graphics.glob('*.png'))), 'graphics.')


if __name__ == '__main__':
    main()

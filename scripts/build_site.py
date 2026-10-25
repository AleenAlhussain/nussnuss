#!/usr/bin/env python3
"""Assemble the deployable website in ./site:
  site/index.html    landing page (from web/landing.src.html)
  site/privacy.html  privacy policy (from replica/launch/privacy.md)
  site/app/          the web app (from ./dist, exported with baseUrl /app)
Also writes web/landing.html (same page without the document wrapper, for previews; --app-url sets its app link).
Usage: npx expo export -p web && python3 scripts/build_site.py [--app-url URL]"""
import base64, html, io, os, re, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
app_url = './app/'
if '--app-url' in sys.argv:
    app_url = sys.argv[sys.argv.index('--app-url') + 1]

def webp(path, width=390):
    im = Image.open(path).convert('RGB')
    h = round(im.height * width / im.width)
    buf = io.BytesIO()
    im.resize((width, h), Image.LANCZOS).save(buf, 'WEBP', quality=82, method=6)
    return 'data:image/webp;base64,' + base64.b64encode(buf.getvalue()).decode()

raw = 'replica/launch/screenshots/raw'
imgs = {
    'IMG_EN_1': webp(f'{raw}/en-2.png'), 'IMG_EN_2': webp(f'{raw}/en-3.png'), 'IMG_EN_3': webp(f'{raw}/en-5.png'),
    'IMG_AR_1': webp(f'{raw}/ar-2.png'), 'IMG_AR_2': webp(f'{raw}/ar-3.png'), 'IMG_AR_3': webp(f'{raw}/ar-5.png'),
}
src = open('web/landing.src.html', encoding='utf-8').read()
for k, v in imgs.items():
    src = src.replace('{{%s}}' % k, v)
src = src.replace('{{PRIVACY_URL}}', 'privacy.html')
preview = src.replace('{{APP_URL}}', app_url)
src = src.replace('{{APP_URL}}', './app/')
open('web/landing.html', 'w', encoding='utf-8').write(preview)

def wrap(body, lang='en'):
    return ('<!doctype html>\n<html lang="%s">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            '<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}'
            'body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%%}[hidden]{display:none!important}</style>\n'
            '<meta property="og:title" content="NussNuss">\n<meta property="og:image" content="social.png">\n'
            '</head>\n<body>\n%s\n</body>\n</html>\n') % (lang, body)

# privacy.md -> minimal HTML
md = open('replica/launch/privacy.md', encoding='utf-8').read()
out, para = [], []
def flush():
    if para:
        t = html.escape(' '.join(para))
        t = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', t)
        t = re.sub(r'_(.+?)_', r'<em>\1</em>', t)
        t = re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)', r'<a href="\2">\1</a>', t)
        t = t.replace('`#`', '<code>#</code>')
        out.append('<p>%s</p>' % t)
        para.clear()
for line in md.splitlines():
    if line.startswith('# '):
        flush(); out.append('<h1>%s</h1>' % html.escape(line[2:]))
    elif line.startswith('## '):
        flush(); out.append('<h2>%s</h2>' % html.escape(line[3:]))
    elif line.strip() == '---':
        flush(); out.append('<hr>')
    elif not line.strip():
        flush()
    else:
        para.append(line.strip())
flush()
privacy_body = ('<title>NussNuss Privacy</title><style>body{background:#F7F6FB;color:#1B1730;line-height:1.65;font-size:16px}'
    'main{max-width:44rem;margin:0 auto;padding-block:32px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}'
    'h1{font-size:1.8rem}h2{font-size:1.2rem;margin-top:1.6em}a{color:#4F3BD6}hr{border:0;border-top:1px solid #E2DFEE;margin:2.5em 0}'
    '@media (prefers-color-scheme: dark){body{background:#0F0D1A;color:#F3F1FA}a{color:#8F7DFF}hr{border-color:#312C48}}</style>'
    '<main>%s</main>') % '\n'.join(out).replace('<h1>سياسة', '<h1 dir="rtl">سياسة')
# Arabic part right-to-left
parts = privacy_body.split('<hr>')
if len(parts) == 2:
    privacy_body = parts[0] + '<hr><div dir="rtl" lang="ar">' + parts[1].replace('</main>', '') + '</div></main>'

if os.path.exists('site'):
    shutil.rmtree('site')
os.makedirs('site')
open('site/index.html', 'w', encoding='utf-8').write(wrap(src))
open('site/privacy.html', 'w', encoding='utf-8').write(wrap(privacy_body))
shutil.copy('replica/launch/social.png', 'site/social.png')
shutil.copy('assets/favicon.png', 'site/favicon.png')
if os.path.isdir('dist'):
    shutil.copytree('dist', 'site/app')
print('site/ built: index.html, privacy.html, app/ (%s)' % ('ok' if os.path.isdir('site/app') else 'missing: run expo export'))

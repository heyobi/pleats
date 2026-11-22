"""GitHub Pages landing page (docs/index.html) for Pleats, from heyobi/querly scripts/landing-pages.py. Usage: python -X utf8 scripts/landing.py"""
import html, json

BADGE = 'app-store-badge.svg'

CSS = """
:root{--bg:#f7f2e9;--fg:#2a1410;--muted:#6e5a52;--card:#efe6d6;--line:#e0d2bb;--accent:#8a2131}
@media (prefers-color-scheme:dark){:root{--bg:#0d0608;--fg:#f6eee2;--muted:#b9a99c;--card:#1b1013;--line:#33201f;--accent:#dcb366}}
h1,h2{font-family:"New York","Iowan Old Style",Georgia,serif;font-weight:600}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:17px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:1040px;margin:0 auto;padding:40px 16px 64px}
header{text-align:center}header img.icon{width:112px;height:112px;border-radius:24px;box-shadow:0 10px 30px rgba(0,0,0,.18)}
h1{font-size:clamp(30px,5vw,46px);line-height:1.15;margin:18px 0 10px;letter-spacing:-.02em}
.lead{font-size:clamp(17px,2.2vw,20px);color:var(--muted);max-width:720px;margin:0 auto 22px}
.badge img{height:54px}
.shots{display:flex;gap:14px;overflow-x:auto;padding:28px 0 8px;scroll-snap-type:x mandatory}
.shots img{height:min(560px,70vh);border-radius:18px;scroll-snap-align:center;flex:none;box-shadow:0 8px 24px rgba(0,0,0,.15)}
h2{font-size:28px;margin:48px 0 12px;letter-spacing:-.01em}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px}
.card b{display:block;margin-bottom:4px}
details{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 18px;margin:10px 0}
summary{font-weight:600;cursor:pointer}
a{color:var(--accent)}code{font:15px ui-monospace,Menlo,monospace;background:var(--card);padding:1px 6px;border-radius:6px}
.wide img{width:100%;border-radius:18px;box-shadow:0 8px 24px rgba(0,0,0,.15)}
footer{color:var(--muted);font-size:14px;margin-top:56px;text-align:center}
"""


def page(app):
    faq_ld = {"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [
        {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in app['faq']]}
    app_ld = {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": app['name'],
              "operatingSystem": "iOS, iPadOS", "applicationCategory": app['category'],
              "description": app['description'], "url": app['store'], "downloadUrl": app['store'],
              "image": app['site'] + 'icon.png', "screenshot": [app['site'] + s for s, _ in app['shots']],
              "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
              "author": {"@type": "Person", "name": "heyobi", "url": "https://github.com/heyobi"}}
    e = html.escape
    shots = '\n'.join(f'    <img src="{s}" alt="{e(alt)}" loading="lazy">' for s, alt in app['shots'])
    feats = '\n'.join(f'    <div class="card"><b>{e(t)}</b>{e(d)}</div>' for t, d in app['features'])
    faq = '\n'.join(f'  <details><summary>{e(q)}</summary><p>{e(a)}</p></details>' for q, a in app['faq'])
    extra = app.get('extra', '')
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(app['title'])}</title>
<meta name="description" content="{e(app['description'])}">
<meta name="keywords" content="{e(app['keywords'])}">
<link rel="canonical" href="{app['site']}">
<link rel="icon" href="icon.png">
<meta name="apple-itunes-app" content="app-id={app['id']}">
<meta property="og:type" content="website">
<meta property="og:title" content="{e(app['title'])}">
<meta property="og:description" content="{e(app['description'])}">
<meta property="og:url" content="{app['site']}">
<meta property="og:image" content="{app['site']}{app['shots'][0][0]}">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">{json.dumps(app_ld, ensure_ascii=False)}</script>
<script type="application/ld+json">{json.dumps(faq_ld, ensure_ascii=False)}</script>
<style>{CSS}</style>
</head>
<body>
<main>
<header>
  <img class="icon" src="icon.png" alt="{e(app['name'])} app icon" width="112" height="112">
  <h1>{e(app['h1'])}</h1>
  <p class="lead">{e(app['lead'])}</p>
  <a class="badge" href="{app['store']}"><img src="{BADGE}" alt="Download {e(app['name'])} on the App Store"></a>
</header>
<div class="shots">
{shots}
</div>
<h2>{e(app['features_title'])}</h2>
<div class="grid">
{feats}
</div>
{extra}
<h2>Questions</h2>
{faq}
<footer>
  <p><a href="{app['store']}">{e(app['name'])} on the App Store</a> · <a href="{app['repo']}">Source code on GitHub</a> · {app['sibling']}</p>
  <p>{e(app['legal'])}</p>
</footer>
</main>
</body>
</html>
"""


pleats_app = dict(
    id='6837969248', name='Pleats', category='MusicApplication',
    store='https://apps.apple.com/app/id6837969248',
    site='https://heyobi.github.io/pleats/', repo='https://github.com/heyobi/pleats',
    title='Pleats: an accordion for iPhone Duo where the hinge is the bellows',
    h1='Play the accordion on iPhone Duo',
    lead='Pleats turns iPhone Duo into a real, playable accordion. Hold it like a book: the fold is the bellows. Open and close the hinge to pump air, press pearl buttons for melody, bass and chords, and learn songs one lit button at a time. On every iPhone and iPad, drag the bellows instead.',
    description='An accordion app made for iPhone Duo: open and close the hinge to pump the bellows. Chromatic and diatonic button boards, Stradella bass and chords, musette and bandoneon registers, song lessons and recording. Free, with an optional one-time Pro.',
    keywords='accordion app iPhone, iPhone Duo accordion, play accordion on iPhone, button accordion app, diatonic accordion app, bandoneon app, musette accordion, learn accordion songs, squeezebox app, iPhone Duo apps',
    shots=[('screens/duo-1-play.jpg', 'iPhone Duo open like a book: bass buttons on the left, treble buttons on the right, bellows across the fold'),
           ('screens/duo-2-lesson.jpg', 'Song lesson: the next button glows'),
           ('screens/duo-3-registers.jpg', 'Register switches in the ivory finish'),
           ('screens/iphone-1-play.jpg', 'Pleats on iPhone with the bellows strip in the middle'),
           ('screens/ipad-1-play.jpg', 'Pleats on iPad')],
    features_title='A real accordion, folded into your phone',
    features=[('The hinge is the bellows', 'Pressure follows how fast you open or close iPhone Duo. Both directions sound, like a real accordion.'),
              ('Melody, bass and chords', 'Treble buttons on one half, Stradella bass and chord buttons on the other, with full multi-touch.'),
              ('Chromatic or diatonic', 'A five-row C-system button board, or a G/C push–pull board where each button changes note with the bellows.'),
              ('Reeds, synthesized live', 'Detuned reeds, breath, a natural attack and a warm room. Clarinet, Bandoneon and Musette registers.'),
              ('Learn songs', 'The next button lights up and the song waits for you. Hear it first, earn three stars.'),
              ('Every iPhone and iPad', 'No hinge? Drag the bellows strip. Steady air plays without pumping.'),
              ('Record', 'Record a clip of your playing and listen back.'),
              ('Fair', 'Free with no ads or account. One optional purchase for more registers, voices and songs.')],
    faq=[('Can I play the accordion on iPhone Duo?', 'Yes. Pleats uses the iPhone Duo hinge as the bellows: hold the phone like a book, half open, and open and close it while pressing the buttons.'),
         ('Does Pleats work on other iPhones and iPad?', 'Yes. Without a hinge you drag the bellows strip in the middle of the screen back and forth, or turn on Steady air to play without pumping.'),
         ('Is it a button accordion or a piano accordion?', 'A button accordion: a chromatic five-row C-system board, or a diatonic G/C push–pull board, with Stradella bass and chord buttons.'),
         ('Can I learn songs with Pleats?', 'Yes. Pick a song and the next button lights up; play it with air and the song moves on at your pace. You can hear each song first.'),
         ('Does Pleats use samples?', 'No. Every note is synthesized on the device from several detuned reeds, so it responds to the bellows like a real instrument.'),
         ('What does Pleats Pro add?', 'Five more registers, three more voices, ten more songs and sharing of recordings, for one payment. No subscription.')],
    sibling='<a href="https://heyobi.github.io/querly/">Querly: CSV viewer for iPhone</a>',
    legal='iPhone and iPhone Duo are trademarks of Apple Inc. Melodies are public domain or original.',
)

import os
out = os.path.join(os.path.dirname(__file__), '..', 'docs', 'index.html')
open(out, 'w', encoding='utf-8').write(page(pleats_app))
print('ok')

"""Checks Pleats' song melodies against independent public-domain ABC transcriptions from abcnotation.com.

For each song it downloads a few transcriptions found by title, parses the ABC melody (enough of the format for
folk tunes: keys and modes, accidentals, octaves, lengths, ties, broken rhythm, triplets, chords) and compares the
interval sequence (transposition-free) and the relative note lengths of the opening with Pleats/Music/Songs.swift.
Writes the best reference's interval fingerprint per song to scripts/melody-reference.json, which the unit tests
use. Usage: python -X utf8 scripts/verify-melodies.py [song-id ...]
"""
import json, re, sys, urllib.error, urllib.parse, urllib.request
from fractions import Fraction as F
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUERIES = {
    'ode': ['Ode to Joy'], 'saints': ['When the Saints Go Marching In', 'When the Saints'],
    'grace': ['Amazing Grace'], 'susanna': ['Oh Susanna', 'O Susanna'], 'cucaracha': ['La Cucaracha', 'Cucaracha'],
    'sailor': ['Drunken Sailor'], 'uskudar': ['Uskudara', 'Uskudar'], 'jingle': ['Jingle Bells'],
    'cancan': ['Can Can', 'Galop Infernal'], 'lullaby': ['Brahms Lullaby', 'Wiegenlied', 'Cradle Song'],
    'greensleeves': ['Greensleeves'], 'auldlang': ['Auld Lang Syne'], 'elise': ['Fur Elise', 'Für Elise'],
    'entertainer': ['The Entertainer', 'Entertainer'], 'sarigelin': ['Sari Gelin'], 'yemen': ['Havada Bulut Yok'],
}
N = 20  # opening intervals compared

CACHE = Path(__import__('os').environ.get('ABC_CACHE', ROOT / 'build' / 'abc-cache'))

def get(url):
    """Cached, polite fetch (abcnotation answers 403 to quick bursts)."""
    import hashlib, time
    CACHE.mkdir(parents=True, exist_ok=True)
    f = CACHE / hashlib.sha1(url.encode()).hexdigest()
    if f.exists():
        return f.read_text(encoding='utf-8')
    for attempt in range(4):
        time.sleep(2.5 + attempt * 6)
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'melody-check/1.0'})
            t = urllib.request.urlopen(req, timeout=30).read().decode('utf-8', 'replace')
            f.write_text(t, encoding='utf-8')
            return t
        except urllib.error.HTTPError as e:
            if e.code not in (403, 429, 503): raise
    raise RuntimeError('rate limited: ' + url)

def candidates(title, limit=4):
    html = get('https://abcnotation.com/searchTunes?q=' + urllib.parse.quote('T:' + title))
    links = []
    for m in re.finditer(r'href="/tunePage\?a=([^"]+)"', html):
        if m.group(1) not in links:
            links.append(m.group(1))
    out = []
    for a in links[:limit]:
        page = get('https://abcnotation.com/tunePage?a=' + a)
        d = re.search(r'(/getResource/downloads/text_/[^"]+\.abc\?a=[^"]+)', page)
        if d:
            out.append(('https://abcnotation.com' + d.group(1).replace('&amp;', '&'), get('https://abcnotation.com' + d.group(1).replace('&amp;', '&'))))
    return out

SHARPS = 'FCGDAEB'
MODES = {'': 0, 'maj': 0, 'ion': 0, 'm': -3, 'min': -3, 'aeo': -3, 'dor': -2, 'mix': -1, 'phr': -4, 'lyd': 1, 'loc': -5}
FIFTHS = {'C': 0, 'G': 1, 'D': 2, 'A': 3, 'E': 4, 'B': 5, 'F#': 6, 'C#': 7, 'F': -1, 'Bb': -2, 'Eb': -3, 'Ab': -4, 'Db': -5, 'Gb': -6, 'Cb': -7}
BASE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}

def keysig(k):
    k = k.strip()
    m = re.match(r'([A-G][#b]?)\s*([A-Za-z]*)(.*)', k)
    sig = {}
    if not m:
        return sig
    tonic, mode, rest = m.group(1), m.group(2).lower()[:3], m.group(3)
    n = FIFTHS.get(tonic, 0) + MODES.get(mode, 0)
    if n > 0:
        for c in SHARPS[:n]: sig[c] = 1
    elif n < 0:
        for c in SHARPS[::-1][:-n]: sig[c] = -1
    for acc, letter in re.findall(r'(_\d/\d|\^\d/\d|\^\^|__|\^|_|=)([A-Ga-g])', rest):
        sign = 1 if acc.startswith('^') else (-1 if acc.startswith('_') else 0)
        fr = re.search(r'(\d)/(\d)', acc)
        # Makam microtones (comma53 files): round to the nearest equal-tempered note, as accordionists play them.
        if fr:
            sign = sign if int(fr.group(1)) / int(fr.group(2)) > 0.5 else 0
        sig[letter.upper()] = sign
    return sig

def parse(abc):
    """First tune of the file → list of (midi, beats) with quarter = 1 beat."""
    i = abc.find('X:')
    tune = abc[i:] if i >= 0 else abc
    j = tune.find('\nX:', 2)
    if j > 0:
        tune = tune[:j]
    L = F(1, 8)
    key = {}
    body = []
    for line in tune.splitlines():
        if re.match(r'^[A-Za-z]:', line):
            f, v = line[0], line[2:]
            if f == 'L':
                try: L = F(v.strip().split()[0])
                except Exception: pass
            elif f == 'K':
                key = keysig(v)
                body.append(None)
            elif f == 'M' and not body:
                pass
            continue
        if line.startswith('%'):
            continue
        if body or key is not None:
            body.append(line)
    text = ' '.join(l for l in body if l)
    text = re.sub(r'"[^"]*"', ' ', text)          # chord symbols, annotations
    text = re.sub(r'![^!]*!', ' ', text)          # decorations
    text = re.sub(r'\{[^}]*\}', ' ', text)        # grace notes
    text = re.sub(r'\[[A-Za-z]:[^\]]*\]', ' ', text)
    text = re.sub(r'%.*', ' ', text)
    notes = []
    bar = {}
    i = 0
    tup = None
    tie = False
    tok = re.compile(r"(\^\^|\^|__|_|=)?([A-Ga-gzxZ])([,']*)(\d*)(/*)(\d*)")
    while i < len(text):
        c = text[i]
        if c == '|' or c == ':':
            bar = {}; i += 1; continue
        if c == '(' and i + 1 < len(text) and text[i + 1].isdigit():
            tup = [F(2, int(text[i + 1])) if text[i + 1] == '3' else F(1), 3 if text[i + 1] == '3' else int(text[i + 1])]
            i += 2; continue
        if c == '-':
            tie = True; i += 1; continue
        if c in '<>' and notes:
            k = len(re.match(r'[<>]+', text[i:]).group(0))
            frac = 1 - F(1, 2 ** k)
            p, d = notes[-1]
            j = i + k
            m = tok.match(text, j)
            if m:
                notes[-1] = (p, d * (1 + frac) if c == '>' else d * (1 - frac))
                text = text[:j] + text[j:]  # next note shortened below
                broken = (1 - frac) if c == '>' else (1 + frac)
                i = j
                m2 = tok.match(text, i)
                acc, letter, octs, num, slashes, den = m2.groups()
                pending = broken
            else:
                i = j; continue
        else:
            pending = None
        if c == '[':
            # chord: keep the first note, skip the rest
            j = text.find(']', i)
            inner = text[i + 1:j] if j > 0 else ''
            m = tok.match(inner)
            rest = text[j + 1:] if j > 0 else ''
            lm = re.match(r'(\d*)(/*)(\d*)', rest)
            if m:
                acc, letter, octs = m.group(1), m.group(2), m.group(3)
                num, slashes, den = lm.groups()
                i = j + 1 + len(lm.group(0))
            else:
                i = (j + 1) if j > 0 else i + 1
                continue
        else:
            m = tok.match(text, i)
            if not m:
                i += 1; continue
            acc, letter, octs, num, slashes, den = m.groups()
            i = m.end()
        dur = F(int(num)) if num else F(1)
        if slashes:
            dur /= F(int(den)) if den else F(2 ** len(slashes))
        dur *= L * 4
        if pending is not None:
            dur *= pending
        if tup:
            dur *= tup[0]; tup[1] -= 1
            if tup[1] <= 0: tup = None
        if letter in 'zxZ':
            notes.append((None, dur)); tie = False; continue
        u = letter.upper()
        octave = 4 if letter.isupper() else 5
        octave += octs.count("'") - octs.count(',')
        if acc:
            a = {'^': 1, '^^': 2, '_': -1, '__': -2, '=': 0}[acc]
            bar[(u, octave)] = a
        else:
            a = bar.get((u, octave), key.get(u, 0))
        midi = (octave + 1) * 12 + BASE[u] + a
        if tie and notes and notes[-1][0] == midi:
            notes[-1] = (midi, notes[-1][1] + dur)
        else:
            notes.append((midi, dur))
        tie = False
    return [(p, float(d)) for p, d in notes if p is not None]

def songs():
    src = (ROOT / 'Pleats' / 'Music' / 'Songs.swift').read_text(encoding='utf-8')
    out = {}
    for m in re.finditer(r'Song\("(\w+)",.*?"""\n(.*?)"""', src, re.S):
        sid, text = m.group(1), m.group(2)
        seq = []
        for t in text.split():
            if t == '|' or t.startswith('['): continue
            name, _, beats = t.partition(':')
            b = float(beats) if beats else 1.0
            if name.upper() == 'R': continue
            mm = re.match(r'([A-G])([#b]*)(-?\d)', name)
            p = (int(mm.group(3)) + 1) * 12 + BASE[mm.group(1)] + mm.group(2).count('#') - mm.group(2).count('b')
            seq.append((p, b))
        out[sid] = seq
    return out

def intervals(seq):
    return [b[0] - a[0] for a, b in zip(seq, seq[1:])]

def score(mine, ref):
    """Best fraction of my first N intervals found in order in the reference opening (offsets for pickups)."""
    a = intervals(mine)[:N]
    b = intervals(ref)
    best = (0, 0)
    for off in range(0, max(1, len(b) - 4)):
        seg = b[off:off + len(a)]
        hits = sum(1 for x, y in zip(a, seg) if x == y)
        if hits > best[0]:
            best = (hits, off)
    return best[0] / max(1, len(a)), best[1]

def main():
    ids = sys.argv[1:] or list(QUERIES)
    mine = songs()
    refpath = ROOT / 'scripts' / 'melody-reference.json'
    refs = json.loads(refpath.read_text(encoding='utf-8')) if refpath.exists() else {}
    for sid in ids:
        best = None
        for q in QUERIES[sid]:
            try:
                for url, abc in candidates(q):
                    ref = parse(abc)
                    if len(ref) < 8: continue
                    s, off = score(mine[sid], ref)
                    if not best or s > best[0]:
                        best = (s, off, url, ref)
            except Exception as e:
                print(sid, 'error', e)
            if best and best[0] >= 0.95: break
        if not best:
            print(f'{sid:12s} no reference found'); continue
        s, off, url, ref = best
        a = intervals(mine[sid])[:N]
        b = intervals(ref)[off:off + len(a)]
        print(f'{sid:12s} {s:5.0%}  {url}')
        if s < 1:
            print('   mine:', a)
            print('   ref :', b)
        refs[sid] = {'source': url, 'intervals': b, 'match': round(s, 3)}
    refpath.write_text(json.dumps(refs, indent=1, ensure_ascii=False), encoding='utf-8')

if __name__ == '__main__':
    main()

"""Tokta 캐릭터 v6: 고를 수 있는 캐릭터 후보. 모든 캐릭터는 같은 규칙을 따른다.

규칙
1. 16x16, 평평한 색. 메뉴바에서 1픽셀 = 1pt.
2. 몸 안에 '게이지 칸'(지도에서 S)이 있고, 남은 한도만큼 빛(사용량 색)으로 찬다. 기본은 아래→위, 배터리는 왼→오.
3. 얼굴은 모든 캐릭터가 같은 이모티콘: 여유 ^_^ · 보통 •_• · 빠듯 >_< · 다 씀 -_- · 리셋 ^o^.
   얼굴 칸은 가로 8 × 세로 5. 캐릭터마다 얼굴 위치(face)만 정한다. 얼굴은 게이지 칸 안에 들어가야 한다.
4. 장식(땀방울·Z·반짝임)은 빈 칸에만 그린다. Z 위치(z)는 캐릭터마다 정한다.
5. 색은 공용 잉크만 쓴다: 테두리(O), 밝은 면(L), 게이지 칸(S), 강조(A, 캐릭터마다 한 색).
"""
import base64, importlib.util, os, sys, zlib, struct

N = 16
NAVY, WHITE = "#1E1B4B", "#FFFFFF"
LIGHT, SCREEN = "#E3E5FB", "#24214F"
SWEAT, SPARK, ZZZ = "#7DD3FC", "#F59E0B", "#8B8FF8"
TONE = {"plenty": "#6366F1", "moderate": "#A5A8F5", "low": "#F0803C", "critical": "#E5484D"}

STATES = [
    ("plenty", "여유", 0.92, "plenty", "happy"),
    ("moderate", "보통", 0.55, "moderate", "calm"),
    ("low", "빠듯", 0.2, "low", "squeeze"),
    ("empty", "다 씀", 0.0, "critical", "sleep"),
    ("reset", "리셋", 1.0, "plenty", "joy"),
]

# 얼굴: (lx, ey)가 왼눈 가운데·눈 윗줄. 오른눈은 lx+5, 입은 ey+3, 커서는 lx+8.
EYES = {
    "caret": lambda x, y: [(x - 1, y + 1), (x, y), (x + 1, y + 1)],
    "dot":   lambda x, y: [(x, y), (x, y + 1)],
    "line":  lambda x, y: [(x - 1, y + 1), (x, y + 1), (x + 1, y + 1)],
    "gt":    lambda x, y: [(x - 1, y), (x, y + 1), (x - 1, y + 2)],
    "lt":    lambda x, y: [(x + 1, y), (x, y + 1), (x + 1, y + 2)],
}
FACES = {"happy": ("caret", "caret", "under"), "calm": ("dot", "dot", "under"), "squeeze": ("gt", "lt", "under"),
         "sleep": ("line", "line", "small"), "joy": ("caret", "caret", "open")}

def mouth(kind, lx, my):
    c = lx + 3
    return {"under": [(c - 1, my), (c, my), (c + 1, my)], "small": [(c, my)],
            "open": [(c - 1, my - 1), (c, my - 1), (c + 1, my - 1), (c - 1, my), (c + 1, my), (c - 1, my + 1), (c, my + 1), (c + 1, my + 1)]}[kind]

Z = [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)]   # 3x3 z

# 캐릭터 지도. . 빈칸 · O 테두리 · L 밝은 면 · S 게이지 칸 · A 강조색
CHARACTERS = {
    "battery": dict(name="배터리", accent="#28C840", face=(4, 6), z=(13, 0), fill="right", blurb="충전량이 곧 남은 한도. 가장 바로 읽힌다.", map="""
................
................
OOOOOOOOOOOOOO..
OSSSSSSSSSSSSO..
OSSSSSSSSSSSSO..
OSSSSSSSSSSSSOO.
OSSSSSSSSSSSSOO.
OSSSSSSSSSSSSOO.
OSSSSSSSSSSSSOO.
OSSSSSSSSSSSSOO.
OSSSSSSSSSSSSO..
OSSSSSSSSSSSSO..
OOOOOOOOOOOOOO..
................
................
................"""),
    "chip": dict(name="칩", accent="#A7A9C9", face=(5, 6), z=(13, 0), blurb="AI 칩. 다리(핀)가 있어 작아도 실루엣이 또렷하다.", map="""
....A.A..A.A....
....A.A..A.A....
..OOOOOOOOOOOO..
..OLLLLLLLLLLO..
AAOLSSSSSSSSLOAA
..OLSSSSSSSSLO..
AAOLSSSSSSSSLOAA
..OLSSSSSSSSLO..
..OLSSSSSSSSLO..
AAOLSSSSSSSSLOAA
..OLSSSSSSSSLO..
AAOLSSSSSSSSLOAA
..OLLLLLLLLLLO..
..OOOOOOOOOOOO..
....A.A..A.A....
....A.A..A.A...."""),
    "mug": dict(name="머그컵", accent="#E3E5FB", face=(3, 6), z=(13, 1), blurb="개발자의 커피. 리셋되면 김이 오른다.", map="""
................
................
................
OOOOOOOOOOOO....
OSSSSSSSSSSO....
OSSSSSSSSSSOOO..
OSSSSSSSSSSO.OO.
OSSSSSSSSSSO..O.
OSSSSSSSSSSO..O.
OSSSSSSSSSSO.OO.
OSSSSSSSSSSOOO..
OSSSSSSSSSSO....
OSSSSSSSSSSO....
.OSSSSSSSSO.....
..OOOOOOOO......
................"""),
    "potion": dict(name="물약", accent="#C08A5B", face=(5, 7), z=(12, 1), blurb="게임의 마나 물약. 한도 = 마나.", map="""
.....AAAAAA.....
.....AAAAAA.....
......OSSO......
......OSSO......
....OOSSSSOO....
...OSSSSSSSSO...
..OSSSSSSSSSSO..
.OSLSSSSSSSSSSO.
.OSLSSSSSSSSSSO.
.OSSSSSSSSSSSSO.
.OSSSSSSSSSSSSO.
.OSSSSSSSSSSSSO.
..OSSSSSSSSSSO..
...OSSSSSSSSO...
....OOOOOOOO....
................"""),
    "slime": dict(name="슬라임", accent="#6366F1", face=(5, 7), z=(12, 1), blurb="말랑한 슬라임. 몸 전체가 게이지라 가장 귀엽다.", map="""
................
................
................
.......OO.......
.....OOSSOO.....
....OSSSSSSO....
...OSSSSSSSSO...
..OSSSSSSSSSSO..
.OSSSSSSSSSSSSO.
.OSSSSSSSSSSSSO.
OSSSSSSSSSSSSSSO
OSSSSSSSSSSSSSSO
OSSSSSSSSSSSSSSO
.OOOOOOOOOOOOOO.
................
................"""),
    "robot": dict(name="로봇", accent="#FF5F57", face=(5, 6), z=(12, 0), blurb="안테나 달린 로봇. 얼굴 화면이 게이지.", map="""
.......AA.......
........O.......
.OOOOOOOOOOOOOO.
.OLLLLLLLLLLLLO.
.OLSSSSSSSSSSLO.
.OLSSSSSSSSSSLO.
OOLSSSSSSSSSSLOO
OOLSSSSSSSSSSLOO
OOLSSSSSSSSSSLOO
OOLSSSSSSSSSSLOO
.OLSSSSSSSSSSLO.
.OLSSSSSSSSSSLO.
.OLLLLLLLLLLLLO.
.OOOOOOOOOOOOOO.
...OO......OO...
................"""),
}

def parse(m):
    rows = m.strip("\n").split("\n")
    assert len(rows) == N and all(len(r) == N for r in rows), [len(r) for r in rows]
    return rows

def lum(c):
    v = int(c[1:], 16)
    return 0.299 * (v >> 16) + 0.587 * ((v >> 8) & 255) + 0.114 * (v & 255)

def draw(key, state, blink=False, cursor=True, fill=None):
    ch = CHARACTERS[key]
    _, _, remaining, tone, kind = state
    remaining = remaining if fill is None else fill
    rows = parse(ch["map"])
    gauge = [(x, y) for y in range(N) for x in range(N) if rows[y][x] == "S"]
    px = {}
    for y in range(N):
        for x in range(N):
            c = rows[y][x]
            if c == "O": px[(x, y)] = NAVY
            elif c == "L": px[(x, y)] = LIGHT
            elif c == "A": px[(x, y)] = ch["accent"]
    # 게이지: 남은 만큼 빛
    if ch.get("fill") == "right":
        xs = sorted({x for x, _ in gauge}); lit = set(xs[:round(len(xs) * remaining)])
        on = lambda x, y: x in lit
    else:
        ys = sorted({y for _, y in gauge}); lit = set(ys[len(ys) - round(len(ys) * remaining):]) if remaining > 0 else set()
        on = lambda x, y: y in lit
    for x, y in gauge: px[(x, y)] = TONE[tone] if on(x, y) else SCREEN
    def ink(x, y): return WHITE if lum(px.get((x, y), WHITE)) < 170 else NAVY
    lx, ey = ch["face"]
    left, right, m = FACES[kind]
    if blink and kind != "sleep": left = right = "line"
    face = EYES[left](lx, ey) + EYES[right](lx + 5, ey) + mouth(m, lx, ey + 3)
    # 커서는 터미널 느낌이라 게이지 칸에 자리가 있을 때만
    if cursor and kind != "sleep" and rows[ey + 3][lx + 8] == "S": face.append((lx + 8, ey + 3))
    for x, y in face:
        assert rows[y][x] == "S", f"{key}: 얼굴 ({x},{y})가 게이지 칸 밖"
        px[(x, y)] = ink(x, y)
    def deco(points, c):
        for x, y in points:
            if 0 <= x < N and 0 <= y < N and (x, y) not in px: px[(x, y)] = c
    if kind == "squeeze": deco([(15, 0), (15, 1), (14, 0), (0, 0), (0, 1), (1, 0)][:3], SWEAT)
    if kind == "sleep": zx, zy = ch["z"]; deco([(zx + dx, zy + dy) for dx, dy in Z], ZZZ)
    if kind == "joy":
        if key == "mug": deco([(3, 0), (3, 1), (4, 2), (6, 0), (6, 1), (7, 2), (9, 0), (9, 1), (8, 2)], "#A5A8F5")   # 김
        deco([(0, 0), (15, 0), (0, 15), (15, 15)], SPARK)
    return px

def png(px, scale, path):
    w = h = N * scale; raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            c = px.get((x // scale, y // scale)); raw += bytes.fromhex(c[1:]) + b"\xff" if c else b"\x00\x00\x00\x00"
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))

def classic():
    """지금 앱의 맥 창 캐릭터(v5)를 비교용으로 불러온다."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pixel-character-v5", "sprites.py")
    spec = importlib.util.spec_from_file_location("v5", path); v5 = importlib.util.module_from_spec(spec); spec.loader.exec_module(v5)
    return v5

if __name__ == "__main__":
    out = sys.argv[1]; S = f"{out}/sprites"; os.makedirs(S, exist_ok=True)
    v5 = classic()
    keys = ["classic"] + list(CHARACTERS)
    names = {"classic": "맥 창 (지금)", **{k: v["name"] for k, v in CHARACTERS.items()}}
    blurbs = {"classic": "지금 앱에 들어 있는 캐릭터. 비교용.", **{k: v["blurb"] for k, v in CHARACTERS.items()}}
    def render(key, st, **kw):
        if key == "classic":
            kw2 = {k: v for k, v in kw.items()}
            return v5.draw(st, **kw2)
        return draw(key, st, **kw)
    for key in keys:
        for st in STATES:
            for suffix, kw in (("", {}), ("-blink", {"blink": True}), ("-nocursor", {"cursor": False})):
                png(render(key, st, **kw), 1, f"{S}/{key}-{st[0]}{suffix}@1x.png")
        for i, f in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
            png(render(key, STATES[4], fill=f), 1, f"{S}/{key}-reset-fill{i}@1x.png")
            png(render(key, STATES[1], fill=f), 1, f"{S}/{key}-level{i}@1x.png")

    def b64(p): return base64.b64encode(open(p, "rb").read()).decode()
    def img(name, size, cls=""): return f'<img class="{cls}" src="data:image/png;base64,{b64(f"{S}/{name}@1x.png")}" width="{size}" height="{size}" alt="">'
    def anim(name, size):
        return f'<div class="anim" style="width:{size}px;height:{size}px">{img(name, size, "f0")}{img(name + "-nocursor", size, "f2")}{img(name + "-blink", size, "f1")}</div>'
    faces = {"plenty": "^_^", "moderate": "•_•", "low": "&gt;_&lt;", "empty": "-_- z", "reset": "^o^"}
    sections = []
    for i, key in enumerate(keys):
        moods = "".join(f'<figure>{anim(f"{key}-{st[0]}", 80)}<figcaption>{st[1]} <code>{faces[st[0]]}</code></figcaption></figure>' for st in STATES)
        levels = "".join(img(f"{key}-level{j}", 48) for j in range(5))
        reset = f'<div class="reset">{"".join(img(f"{key}-reset-fill{j}", 80, f"r{j}") for j in range(5))}</div>'
        bars = "".join(f'<div class="menubar {d}"><span class="spacer"></span>{img(f"{key}-{s}", 16)}<span>{p}</span><span>10:24</span></div>'
                       for d in ("", "dark") for s, p in (("plenty", "92%"), ("low", "20%")))
        label = "후보 0" if key == "classic" else f"후보 {i}"
        sections.append(f'''<section><div class="head"><h2>{label} · {names[key]}</h2><span class="muted">{blurbs[key]}</span></div>
<div class="row"><div><div class="muted cap">표정</div><div class="row">{moods}</div></div>
<div><div class="muted cap">리셋</div>{reset}</div>
<div><div class="muted cap">남은 한도 0 · 25 · 50 · 75 · 100%</div><div class="row tight">{levels}</div></div>
<div><div class="muted cap">메뉴바 (실제 크기)</div>{bars}</div></div></section>''')
    lineup = "".join(f'<figure>{anim(f"{k}-plenty", 64)}<figcaption>{"0" if k == "classic" else i} · {names[k]}</figcaption></figure>' for i, k in enumerate(keys))
    css = """:root{--bg:#f6f6f8;--card:#fff;--text:#1d1d22;--muted:#6b6b76;--line:#e4e4ea}
@media (prefers-color-scheme:dark){:root{--bg:#1b1b1f;--card:#26262b;--text:#ececf1;--muted:#a0a0aa;--line:#36363d}}
body{margin:0;padding:20px 16px;background:var(--bg);color:var(--text);font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif}
h1{font-size:20px;font-weight:600;margin:0 0 4px} h2{font-size:15px;font-weight:600;margin:0} p.lead{color:var(--muted);margin:0 0 18px;max-width:760px}
section{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 16px;margin-bottom:14px}
.head{display:flex;flex-wrap:wrap;gap:10px;align-items:baseline;margin-bottom:12px}
.row{display:flex;flex-wrap:wrap;gap:18px;align-items:flex-start} .row.tight{gap:8px} figure{margin:0;text-align:center} figcaption{color:var(--muted);font-size:12px;margin-top:6px}
.cap{margin-bottom:6px} code{font:12px ui-monospace,Menlo,monospace;color:var(--text)} .muted{color:var(--muted);font-size:12px} img{image-rendering:pixelated;display:block}
.anim{position:relative} .anim img{position:absolute;inset:0} .anim .f1,.anim .f2{opacity:0}
.anim .f1{animation:blink 3.6s steps(1) infinite} .anim .f2{animation:cursor 1.1s steps(1) infinite}
@keyframes blink{0%,93%{opacity:0}94%,97%{opacity:1}98%,100%{opacity:0}} @keyframes cursor{0%,50%{opacity:0}51%,100%{opacity:1}}
.reset{position:relative;width:80px;height:80px} .reset img{position:absolute;inset:0;opacity:0;animation:fill 3s steps(1) infinite}
.reset .r1{animation-delay:.2s}.reset .r2{animation-delay:.4s}.reset .r3{animation-delay:.6s}.reset .r4{animation-delay:.8s}
@keyframes fill{0%{opacity:1}6.6%,100%{opacity:0}} .reset .r4{animation-name:hold} @keyframes hold{0%,73%{opacity:1}74%,100%{opacity:0}}
@media (prefers-reduced-motion:reduce){.anim .f1,.anim .f2,.reset img{animation:none}.reset .r4{opacity:1}}
.menubar{display:flex;gap:8px;align-items:center;width:150px;padding:3px 8px;border-radius:5px;background:#ececec;color:#111;font:12px -apple-system,sans-serif;margin-bottom:4px}
.menubar.dark{background:#2a2a2e;color:#eee} .menubar .spacer{flex:1}"""
    html = f'''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Tokta 캐릭터 v6</title><style>{css}</style></head><body>
<h1>Tokta 캐릭터 v6 — 고를 수 있는 캐릭터 후보</h1>
<p class="lead">모두 같은 규칙: 16×16, 몸 안 게이지 칸이 남은 한도만큼 빛으로 차고(배터리는 왼→오), 얼굴은 같은 다섯 표정. 그래서 어떤 캐릭터를 골라도 읽는 법이 같다. 색은 설정의 사용량 색 조합을 따른다.</p>
<section><h2 style="margin-bottom:12px">한눈에</h2><div class="row">{lineup}</div></section>
{"".join(sections)}
</body></html>'''
    open(f"{out}/sheet.html", "w").write(html)
    print("ok", len(keys), "characters")

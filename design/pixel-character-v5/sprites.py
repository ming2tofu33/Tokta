"""Tokta 캐릭터 v5: v4의 T4(맥 창 + 글자 얼굴)를 다듬은 최종 후보. 16x16, 평평한 색.
화면이 아래부터 빛으로 찬 높이 = 남은 한도. 얼굴은 이모티콘: 여유 ^_^ · 보통 •_• · 빠듯 >_< · 다 씀 -_- z · 리셋 ^o^"""
import base64, os, struct, sys, zlib

N = 16
NAVY, WHITE = "#1E1B4B", "#FFFFFF"
LIGHT, SCREEN = "#E3E5FB", "#24214F"
SWEAT, SPARK, ZZZ = "#7DD3FC", "#F59E0B", "#8B8FF8"
TRAFFIC = ("#FF5F57", "#FEBC2E", "#28C840")
TONE = {"plenty": "#6366F1", "moderate": "#A5A8F5", "low": "#F0803C", "critical": "#E5484D"}

STATES = [
    ("plenty", "여유", 0.92, "plenty", "happy"),
    ("moderate", "보통", 0.55, "moderate", "calm"),
    ("low", "빠듯", 0.2, "low", "squeeze"),
    ("empty", "다 씀", 0.0, "critical", "sleep"),
    ("reset", "리셋", 1.0, "plenty", "joy"),
]

# 얼굴 자리: 왼눈 x=5, 오른눈 x=10, 눈 윗줄 y=7, 입 y=10. 커서는 입 오른쪽 x=13.
L, R, EY, MY, CURSOR = 5, 10, 7, 10, 13
EYES = {
    "caret": lambda x: [(x - 1, EY + 1), (x, EY), (x + 1, EY + 1)],          # ^
    "dot":   lambda x: [(x, EY), (x, EY + 1)],                                # •
    "line":  lambda x: [(x - 1, EY + 1), (x, EY + 1), (x + 1, EY + 1)],       # -
    "gt":    lambda x: [(x - 1, EY), (x, EY + 1), (x - 1, EY + 2)],           # >
    "lt":    lambda x: [(x + 1, EY), (x, EY + 1), (x + 1, EY + 2)],           # <
}
MOUTH = {
    "under": [(7, MY), (8, MY), (9, MY)],                                     # _
    "small": [(8, MY)],
    "open":  [(7, MY - 1), (8, MY - 1), (9, MY - 1), (7, MY), (9, MY), (7, MY + 1), (8, MY + 1), (9, MY + 1)],  # o
}
FACES = {   # (왼눈, 오른눈, 입)
    "happy": ("caret", "caret", "under"),
    "calm": ("dot", "dot", "under"),
    "squeeze": ("gt", "lt", "under"),
    "sleep": ("line", "line", "small"),
    "joy": ("caret", "caret", "open"),
}

def lum(c):
    v = int(c[1:], 16)
    return 0.299 * (v >> 16) + 0.587 * ((v >> 8) & 255) + 0.114 * (v & 255)

def draw(state, blink=False, cursor=True, fill=None):
    """fill: 리셋 애니메이션처럼 남은 비율을 따로 줄 때."""
    key, _, remaining, tone, kind = state
    remaining = remaining if fill is None else fill
    px = {}
    def put(x, y, c):
        if 0 <= x < N and 0 <= y < N: px[(x, y)] = c
    # 창: 테두리, 제목 줄, 신호등
    for y in range(1, 15):
        for x in range(16): put(x, y, NAVY)
    for x in range(1, 15):
        put(x, 2, LIGHT); put(x, 3, LIGHT)
    for x, c in zip((2, 4, 6), TRAFFIC): put(x, 2, c); put(x, 3, c)
    for p in ((0, 1), (15, 1), (0, 14), (15, 14)): px.pop(p, None)
    # 화면: 아래부터 남은 만큼 빛
    top, bottom = 5, 13
    level = bottom + 1 - round((bottom - top + 1) * remaining)
    for y in range(top, bottom + 1):
        for x in range(1, 15): put(x, y, TONE[tone] if y >= level else SCREEN)
    def ink(x, y): return WHITE if lum(px.get((x, y), WHITE)) < 170 else NAVY
    left, right, mouth = FACES[kind]
    if blink and kind != "sleep": left = right = "line"
    for x, y in EYES[left](L) + EYES[right](R) + MOUTH[mouth]: put(x, y, ink(x, y))
    if cursor and kind != "sleep":
        put(CURSOR, MY, ink(CURSOR, MY))
    # 바깥 장식
    def deco(points, c):
        for x, y in points:
            if 0 <= x < N and 0 <= y < N and (x, y) not in px: put(x, y, c)
    if kind == "squeeze": deco([(15, 0), (15, 1), (14, 0)], SWEAT)
    if kind == "sleep":   # 잘 때는 커서 자리(화면 안 입 오른쪽)에 Z
        for dx, dy in [(0, 0), (1, 0), (2, 0), (3, 0), (2, 1), (1, 2), (0, 3), (1, 3), (2, 3), (3, 3)]:
            put(11 + dx, 9 + dy, ZZZ)
    if kind == "joy": deco([(0, 0), (15, 0), (0, 15), (15, 15)], SPARK)
    return px

def png(px, scale, path):
    w = h = N * scale; raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            c = px.get((x // scale, y // scale)); raw += bytes.fromhex(c[1:]) + b"\xff" if c else b"\x00\x00\x00\x00"
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))

if __name__ == "__main__":
    out = sys.argv[1]; S = f"{out}/sprites"; os.makedirs(S, exist_ok=True)
    for st in STATES:
        png(draw(st), 1, f"{S}/{st[0]}@1x.png"); png(draw(st), 2, f"{S}/{st[0]}@2x.png"); png(draw(st), 8, f"{S}/{st[0]}@8x.png")
        png(draw(st, blink=True), 1, f"{S}/{st[0]}-blink@1x.png"); png(draw(st, cursor=False), 1, f"{S}/{st[0]}-nocursor@1x.png")
    reset = STATES[4]
    for i, f in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):   # 리셋: 화면이 아래부터 차오른다
        png(draw(reset, fill=f), 1, f"{S}/reset-fill{i}@1x.png")

    def b64(p): return base64.b64encode(open(p, "rb").read()).decode()
    def img(name, size, cls=""): return f'<img class="{cls}" src="data:image/png;base64,{b64(f"{S}/{name}@1x.png")}" width="{size}" height="{size}" alt="">'
    def anim(key, size):
        return f'<div class="anim" style="width:{size}px;height:{size}px">{img(key, size, "f0")}{img(key + "-nocursor", size, "f2")}{img(key + "-blink", size, "f1")}</div>'
    faces = {"plenty": "^_^", "moderate": "•_•", "low": "&gt;_&lt;", "empty": "-_- z", "reset": "^o^"}
    states = "".join(f'<figure>{anim(st[0], 112)}<figcaption>{st[1]} <code>{faces[st[0]]}</code></figcaption></figure>' for st in STATES)
    reset_frames = "".join(img(f"reset-fill{i}", 112, f"r{i}") for i in range(5))
    sizes = img("plenty", 16) + img("plenty", 32) + img("plenty", 64)
    bar = lambda dark: f'<div class="menubar {"dark" if dark else ""}"><span class="apple"></span><span>파일</span><span class="spacer"></span>{img("plenty", 16)}<span>96%</span><span>10:24</span></div>'
    card = f'''<div class="card"><div class="hero">{anim("low", 64)}<div><div class="muted">Claude</div><div class="big">메인 <span class="warn">20%</span></div><div class="muted">이 속도면 38분 뒤 바닥</div></div></div>
<div class="next">{img("plenty", 32)}<div><div class="muted">다음은</div><b>서브2 · 70%</b></div><span class="btn">서브2로 열기</span></div></div>'''
    widget = f'<div class="widget"><div class="muted">Claude</div>{anim("plenty", 64)}<div><b>서브2</b> <span>70%</span></div><div class="muted">5개 중 3개 여유</div></div>'
    css = """:root{--bg:#f6f6f8;--card:#fff;--text:#1d1d22;--muted:#6b6b76;--line:#e4e4ea;--warn:#F0803C}
@media (prefers-color-scheme:dark){:root{--bg:#1b1b1f;--card:#26262b;--text:#ececf1;--muted:#a0a0aa;--line:#36363d;--warn:#F59152}}
body{margin:0;padding:20px 16px;background:var(--bg);color:var(--text);font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif}
h1{font-size:20px;font-weight:600;margin:0 0 4px} h2{font-size:15px;font-weight:600;margin:0 0 10px} p.lead{color:var(--muted);margin:0 0 18px;max-width:720px}
section{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 16px;margin-bottom:14px}
.row{display:flex;flex-wrap:wrap;gap:18px;align-items:flex-start} figure{margin:0;text-align:center} figcaption{color:var(--muted);font-size:12px;margin-top:6px}
code{font:12px ui-monospace,Menlo,monospace;color:var(--text)} .muted{color:var(--muted);font-size:12px} img{image-rendering:pixelated;display:block}
.anim{position:relative} .anim img{position:absolute;inset:0} .anim .f1,.anim .f2{opacity:0}
.anim .f1{animation:blink 3.6s steps(1) infinite} .anim .f2{animation:cursor 1.1s steps(1) infinite}
@keyframes blink{0%,93%{opacity:0}94%,97%{opacity:1}98%,100%{opacity:0}} @keyframes cursor{0%,50%{opacity:0}51%,100%{opacity:1}}
.reset{position:relative;width:112px;height:112px} .reset img{position:absolute;inset:0;opacity:0;animation:fill 3s steps(1) infinite}
.reset .r0{animation-delay:0s}.reset .r1{animation-delay:.2s}.reset .r2{animation-delay:.4s}.reset .r3{animation-delay:.6s}.reset .r4{animation-delay:.8s}
@keyframes fill{0%{opacity:1}6.6%,100%{opacity:0}} .reset .r4{animation-name:hold} @keyframes hold{0%{opacity:1}73%{opacity:1}74%,100%{opacity:0}}
@media (prefers-reduced-motion:reduce){.anim .f1,.anim .f2,.reset img{animation:none}.reset .r4{opacity:1}}
.menubar{display:flex;gap:10px;align-items:center;width:340px;max-width:100%;padding:4px 10px;border-radius:6px;background:#ececec;color:#111;font:13px -apple-system,sans-serif;margin-bottom:8px}
.menubar.dark{background:#2a2a2e;color:#eee} .menubar .spacer{flex:1}
.card{width:340px;max-width:100%;border:1px solid var(--line);border-radius:12px;padding:12px;background:var(--bg)}
.hero{display:flex;gap:12px;align-items:center} .big{font-size:20px;font-weight:600} .warn{color:var(--warn)}
.next{display:flex;gap:10px;align-items:center;margin-top:12px;padding-top:10px;border-top:1px solid var(--line)} .next>div{flex:1}
.btn{font-size:12px;padding:4px 10px;border-radius:6px;background:#6366F1;color:#fff}
.widget{width:150px;height:150px;border-radius:22px;background:var(--bg);border:1px solid var(--line);padding:14px;box-sizing:border-box;display:flex;flex-direction:column;gap:6px}"""
    html = f'''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Tokta 캐릭터 v5</title><style>{css}</style></head><body>
<h1>Tokta 캐릭터 v5 — 맥 창 + 글자 얼굴</h1><p class="lead">16×16, 평평한 색. 화면이 아래부터 빛으로 찬 높이 = 남은 한도. 얼굴은 이모티콘. 눈·커서 깜빡임, 리셋 때 화면이 아래부터 차오른다.</p>
<section><h2>표정</h2><div class="row">{states}</div></section>
<section><h2>리셋 순간</h2><div class="row"><div class="reset">{reset_frames}</div><div class="muted" style="max-width:280px">한도가 다시 채워지면 빈 화면이 아래부터 차오르고 ^o^ 얼굴이 된다.</div></div></section>
<section><h2>크기 (16 · 32 · 64px)</h2><div class="row" style="align-items:flex-end">{sizes}</div></section>
<section><h2>앱 안에서 (예시)</h2><div class="row"><div><div class="muted" style="margin-bottom:6px">메뉴바</div>{bar(False)}{bar(True)}</div><div><div class="muted" style="margin-bottom:6px">메뉴 맨 위 카드</div>{card}</div><div><div class="muted" style="margin-bottom:6px">작은 위젯</div>{widget}</div></div></section>
</body></html>'''
    open(f"{out}/sheet.html", "w").write(html)

"""Reference prototype of madeitpx `pixelart` preset. Integer-only, deterministic.
Mirrors src/pixelart.zig step by step."""
import numpy as np

EDGE_DIST = 9216          # 3,4,2 weighted distance ~ gray diff of 32
INK_MAX_LUMA = 150
INK_MIN_CONTRAST = 40
COV_STRONG = 20           # percent of the cell covered by the dark class
COV_WEAK = 12
MIN_ALIGNED_GAP = 2       # gap cells bridged without any evidence
MAX_EVIDENCE_GAP = 5      # gap cells bridged when every gap cell has weak evidence
INK_MERGE_DIST = 5184     # 9 * 24^2


def dist(a, b):
    d = a.astype(np.int64) - np.asarray(b, dtype=np.int64)
    return 3 * d[..., 0] ** 2 + 4 * d[..., 1] ** 2 + 2 * d[..., 2] ** 2


def luma(c):
    return (77 * int(c[0]) + 150 * int(c[1]) + 29 * int(c[2])) >> 8


def mean_of(px):
    n = len(px)
    return ((px.sum(0) + n // 2) // n).astype(np.int64)


# ---------------------------------------------------------------- stage 1
def reduce_cells(src, tw, th):
    sh, sw, _ = src.shape
    fill = np.zeros((th, tw, 3), np.int64)
    ink_col = np.zeros((th, tw, 3), np.int64)
    cov = np.zeros((th, tw), np.int64)
    for oy in range(th):
        y0 = oy * sh // th
        y1 = max((oy + 1) * sh // th, y0 + 1)
        y1 = min(y1, sh)
        for ox in range(tw):
            x0 = ox * sw // tw
            x1 = max((ox + 1) * sw // tw, x0 + 1)
            x1 = min(x1, sw)
            px = src[y0:y1, x0:x1].reshape(-1, 3).astype(np.int64)
            n = len(px)
            overall = mean_of(px)
            fill[oy, ox] = overall
            if n < 2:
                continue
            b = px[int(np.argmax(dist(px, px[0])))]
            c = px[int(np.argmax(dist(px, b)))]
            cls = dist(px, c) < dist(px, b)          # tie -> class 0 (b)
            ok = True
            for _ in range(2):
                n1 = int(cls.sum()); n0 = n - n1
                if n0 == 0 or n1 == 0:
                    ok = False
                    break
                m0 = mean_of(px[~cls]); m1 = mean_of(px[cls])
                cls = dist(px, m1) < dist(px, m0)
            n1 = int(cls.sum()); n0 = n - n1
            if not ok or n0 == 0 or n1 == 0:
                continue
            m0 = mean_of(px[~cls]); m1 = mean_of(px[cls])
            if int(dist(m0, m1)) < EDGE_DIST:
                continue
            l0, l1 = luma(m0), luma(m1)
            if l0 <= l1:
                dm, dn, lm, ln, lum_d, lum_l = m0, n0, m1, n1, l0, l1
            else:
                dm, dn, lm, ln, lum_d, lum_l = m1, n1, m0, n0, l1, l0
            # fill = majority class (tie -> lighter)
            fill[oy, ox] = dm if dn > ln else lm
            if lum_d <= INK_MAX_LUMA and lum_l - lum_d >= INK_MIN_CONTRAST:
                cv = dn * 100 // n
                if cv >= COV_WEAK:
                    cov[oy, ox] = cv
                    ink_col[oy, ox] = dm
    return fill, ink_col, cov


# ---------------------------------------------------------------- helpers
RING = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)]


def get(m, x, y):
    h, w = m.shape
    return 0 <= x < w and 0 <= y < h and bool(m[y, x])


def ring_components(fg):
    seen = [False] * 8
    comps = 0
    for s in range(8):
        if not fg[s] or seen[s]:
            continue
        comps += 1
        seen[s] = True
        stack = [s]
        while stack:
            cur = stack.pop()
            for o in range(8):
                if not fg[o] or seen[o]:
                    continue
                if abs(RING[cur][0] - RING[o][0]) <= 1 and abs(RING[cur][1] - RING[o][1]) <= 1:
                    seen[o] = True
                    stack.append(o)
    return comps


def is_simple(ink, x, y):
    fg = [get(ink, x + dx, y + dy) for dx, dy in RING]
    return ring_components(fg) == 1


def ink_neighbors8(ink, x, y):
    return sum(get(ink, x + dx, y + dy) for dx, dy in RING)


def label_components(ink):
    h, w = ink.shape
    comp = np.full((h, w), -1, np.int64)
    nxt = 0
    for y in range(h):
        for x in range(w):
            if not ink[y, x] or comp[y, x] >= 0:
                continue
            comp[y, x] = nxt
            stack = [(x, y)]
            while stack:
                cx, cy = stack.pop()
                for dx, dy in RING:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and ink[ny, nx] and comp[ny, nx] < 0:
                        comp[ny, nx] = nxt
                        stack.append((nx, ny))
            nxt += 1
    return comp


# ---------------------------------------------------------------- stage 2
def build_ink(cov, ink_col):
    h, w = cov.shape
    ink = cov >= COV_STRONG
    # thin: keep one cell across a band, never break local connectivity
    for y in range(h):
        for x in range(w):
            if not ink[y, x]:
                continue
            idx = y * w + x
            higher = False
            for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                nx, ny = x + dx, y + dy
                if not get(ink, nx, ny):
                    continue
                nidx = ny * w + nx
                if cov[ny, nx] > cov[y, x] or (cov[ny, nx] == cov[y, x] and nidx < idx):
                    higher = True
                    break
            if higher and ink_neighbors8(ink, x, y) >= 2 and is_simple(ink, x, y):
                ink[y, x] = False
    # drop isolated specks
    for y in range(h):
        for x in range(w):
            if ink[y, x] and ink_neighbors8(ink, x, y) == 0:
                ink[y, x] = False
    n_before_bridge = int(ink.sum())
    # bridge gaps from endpoints
    col = ink_col.copy()
    bridged = 0
    for y in range(h):
        for x in range(w):
            if not ink[y, x]:
                continue
            nbs = [(x + dx, y + dy) for dx, dy in RING if get(ink, x + dx, y + dy)]
            if len(nbs) == 0 or len(nbs) > 3 or not is_simple(ink, x, y):
                continue
            sx_ = sum(x - nx_ for nx_, _ in nbs)
            sy_ = sum(y - ny_ for _, ny_ in nbs)
            ddx = (sx_ > 0) - (sx_ < 0)
            ddy = (sy_ > 0) - (sy_ < 0)
            if ddx == 0 and ddy == 0:
                continue
            px_, py_ = -ddy, ddx
            best = None
            for gap in range(1, MAX_EVIDENCE_GAP + 1):
                for s in ((0, -1, 1) if gap <= 2 else (0, -1, 1, -2, 2)):
                    tx = x + (gap + 1) * ddx + s * px_
                    ty = y + (gap + 1) * ddy + s * py_
                    if not get(ink, tx, ty) or locally_connected(ink, x, y, tx, ty):
                        continue
                    path = bresenham(x, y, tx, ty)[1:-1]
                    if any(get(ink, cx, cy) for cx, cy in path):
                        continue
                    if gap > MIN_ALIGNED_GAP and any(cov[cy, cx] == 0 for cx, cy in path):
                        continue
                    best = (path, tx, ty)
                    break
                if best:
                    break
            if best:
                path, tx, ty = best
                for cx, cy in path:
                    ink[cy, cx] = True
                    if cov[cy, cx] == 0:
                        col[cy, cx] = col[y, x]
                bridged += len(path)
    return ink, col, bridged


LOCAL_DEPTH = 12


def locally_connected(ink, x0, y0, x1, y1):
    # breadth-first walk over ink cells, at most LOCAL_DEPTH steps from (x0,y0)
    seen = {(x0, y0)}
    frontier = [(x0, y0)]
    for _ in range(LOCAL_DEPTH):
        nxt = []
        for cx, cy in frontier:
            for dx, dy in RING:
                nx, ny = cx + dx, cy + dy
                if (nx, ny) in seen or not get(ink, nx, ny):
                    continue
                if nx == x1 and ny == y1:
                    return True
                seen.add((nx, ny))
                nxt.append((nx, ny))
        frontier = nxt
    return False


def bresenham(x0, y0, x1, y1):
    pts = []
    dx = abs(x1 - x0); dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    x, y = x0, y0
    while True:
        pts.append((x, y))
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x += sx
        if e2 <= dx:
            err += dx; y += sy
    return pts


# ---------------------------------------------------------------- stage 3
def median_cut(colors, limit):
    colors = [tuple(int(v) for v in c) for c in colors]
    uniq = []
    for c in colors:
        if c not in uniq:
            uniq.append(c)
            if len(uniq) > limit:
                break
    if len(uniq) <= limit:
        return uniq
    arr = np.array(colors, np.int64)
    buckets = [arr]
    while len(buckets) < limit:
        best, bs = None, 0
        for i, b in enumerate(buckets):
            if len(b) < 2:
                continue
            rng = (b.max(0) - b.min(0)).max()
            if rng == 0:
                continue
            sc = int(rng) * len(b)
            if sc > bs:
                best, bs = i, sc
        if best is None:
            break
        b = buckets[best]
        comp = int(np.argmax(b.max(0) - b.min(0)))
        order = np.argsort(b[:, comp], kind="stable")
        b = b[order]
        half = len(b) // 2
        buckets[best] = b[:half]
        buckets.append(b[half:])
    return [tuple(int(v) for v in mean_of(b)) for b in buckets if len(b)]


def nearest(color, pal):
    best, bd = 0, 1 << 60
    for i, p in enumerate(pal):
        d = int(dist(np.array(color), np.array(p)))
        if d < bd:
            best, bd = i, d
    return best


# ---------------------------------------------------------------- stage 4/5
def cleanup(label, ink, fill, pal, max_iter=16):
    h, w = label.shape
    for _ in range(max_iter):
        solid = np.zeros((h, w), bool)
        for y in range(h - 1):
            for x in range(w - 1):
                if ink[y, x] or ink[y, x + 1] or ink[y + 1, x] or ink[y + 1, x + 1]:
                    continue
                l = label[y, x]
                if label[y, x + 1] == l and label[y + 1, x] == l and label[y + 1, x + 1] == l:
                    solid[y:y + 2, x:x + 2] = True
        new = label.copy()
        changed = 0
        for y in range(h):
            for x in range(w):
                if ink[y, x] or solid[y, x]:
                    continue
                counts = {}
                for dx, dy in RING:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not ink[ny, nx] and solid[ny, nx] and label[ny, nx] != label[y, x]:
                        counts[label[ny, nx]] = counts.get(label[ny, nx], 0) + 1
                if not counts:
                    continue
                best = min(counts, key=lambda k: (int(dist(fill[y, x], pal[k])), -counts[k], k))
                if best != label[y, x]:
                    new[y, x] = best
                    changed += 1
        label = new
        if not changed:
            break
    return label


def convert(src, tw, th, limit=16, cleanup_on=True):
    fill, ink_col, cov = reduce_cells(src, tw, th)
    ink, col, bridged = build_ink(cov, ink_col)
    ink_cells = [col[y, x] for y in range(th) for x in range(tw) if ink[y, x]]
    cap = 2 if limit >= 8 else 1
    ink_pal = median_cut(ink_cells, cap) if ink_cells else []
    if len(ink_pal) == 2 and int(dist(np.array(ink_pal[0]), np.array(ink_pal[1]))) < INK_MERGE_DIST:
        ink_pal = [tuple(int(v) for v in mean_of(np.array(ink_cells)))]
    fill_cells = [fill[y, x] for y in range(th) for x in range(tw) if not ink[y, x]]
    fill_pal = median_cut(fill_cells, max(1, limit - len(ink_pal))) if fill_cells else []
    pal = list(ink_pal) + [c for c in fill_pal]
    label = np.zeros((th, tw), np.int64)
    for y in range(th):
        for x in range(tw):
            if ink[y, x]:
                label[y, x] = nearest(col[y, x], ink_pal)
            else:
                label[y, x] = nearest(fill[y, x], pal)
    if cleanup_on:
        label = cleanup(label, ink, fill, pal)
    out = np.zeros((th, tw, 3), np.uint8)
    for y in range(th):
        for x in range(tw):
            out[y, x] = pal[label[y, x]]
    return out, ink, label, pal, bridged


# ---------------------------------------------------------------- metrics
def metrics(out, ink=None):
    h, w, _ = out.shape
    iso = 0
    thin = 0
    key = (out[..., 0].astype(np.int64) << 16) | (out[..., 1].astype(np.int64) << 8) | out[..., 2]
    for y in range(h):
        for x in range(w):
            same8 = any(0 <= x + dx < w and 0 <= y + dy < h and key[y + dy, x + dx] == key[y, x] for dx, dy in RING)
            if not same8:
                iso += 1
    for y in range(h):
        for x in range(w):
            if ink is not None and ink[y, x]:
                continue
            ok = False
            for ox in (0, -1):
                for oy in (0, -1):
                    x0, y0 = x + ox, y + oy
                    if 0 <= x0 < w - 1 and 0 <= y0 < h - 1:
                        k = key[y0, x0]
                        if key[y0, x0 + 1] == k and key[y0 + 1, x0] == k and key[y0 + 1, x0 + 1] == k:
                            ok = True
            if not ok:
                thin += 1
    return iso, thin

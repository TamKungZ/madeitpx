import numpy as np, time
from PIL import Image, ImageDraw
import pxart

def make_art(S=512, ss=4):
    N = S*ss
    im = Image.new("RGB", (N, N), (150, 200, 230))
    d = ImageDraw.Draw(im)
    # smooth sky gradient background
    a = np.array(im, dtype=np.float32)
    yy = np.linspace(0, 1, N)[:, None]
    a[..., 0] = 120 + 60*yy; a[..., 1] = 170 + 50*yy; a[..., 2] = 235 - 30*yy
    # shaded sphere "character body" with smooth radial light
    cx, cy, r = N*0.5, N*0.55, N*0.30
    Y, X = np.mgrid[0:N, 0:N]
    rr = np.hypot(X-cx, Y-cy)
    nx, ny = (X-cx)/r, (Y-cy)/r
    lit = np.clip(0.5 - 0.45*(nx*0.5+ny*0.7)*1.0 + 0.2*(1-rr/r), 0, 1)
    base = np.stack([230*lit+40, 160*lit+30, 120*lit+40], -1)
    m = rr < r
    a[m] = base[m]
    im = Image.fromarray(a.clip(0,255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    ow = int(N*0.012)
    # outline ring with a deliberate GAP (top-right) -> must be bridged
    d.arc([cx-r, cy-r, cx+r, cy+r], start=-62, end=292, fill=(25, 20, 35), width=ow)
    # hair strand thin lines (curvy), 1.2% -> ~6 px source
    for k in range(5):
        d.arc([cx-r*0.9+k*N*0.03, cy-r*1.35, cx+r*0.9-k*N*0.03, cy-r*0.2], start=200, end=340, fill=(25,20,35), width=int(N*0.006))
    # eyes: dark 2x2-cell blobs + 1px highlight
    for ex in (cx-r*0.35, cx+r*0.35):
        d.ellipse([ex-N*0.03, cy-N*0.05, ex+N*0.03, cy+N*0.03], fill=(30,25,45))
        d.ellipse([ex-N*0.012, cy-N*0.04, ex+N*0.004, cy-N*0.024], fill=(250,250,255))
    # mouth thin line
    d.arc([cx-r*0.3, cy+r*0.1, cx+r*0.3, cy+r*0.5], start=20, end=160, fill=(60,25,30), width=int(N*0.005))
    im = im.resize((S, S), Image.LANCZOS)
    a = np.array(im).astype(np.float32)
    rng = np.random.RandomState(1)
    a += rng.normal(0, 3, a.shape)   # sensor/paint noise
    return Image.fromarray(a.clip(0,255).astype(np.uint8))

def baseline(img, tw, th, k=16):
    small = img.resize((tw, th), Image.BOX)
    q = small.quantize(colors=k, method=Image.MEDIANCUT, dither=Image.NONE)
    return np.array(q.convert("RGB"))

if __name__ == "__main__":
    src = make_art()
    src.save("src.png")
    tw = th = 64
    t = time.time()
    out, ink, label, pal, bridged = pxart.convert(np.array(src), tw, th, 16)
    print("time", round(time.time()-t,2), "palette", len(pal), "bridged cells", bridged)
    base = baseline(src, tw, th, 16)
    nocl, _, _, _, _ = pxart.convert(np.array(src), tw, th, 16, cleanup_on=False)
    for name, o, i in (("baseline BOX+PIL median-cut", base, None), ("pixelart, cleanup OFF", nocl, ink), ("pixelart (full)", out, ink)):
        iso, thin = pxart.metrics(o, i)
        print(f"{name:32s} isolated px={iso:4d}  thin(non-2x2, non-ink) px={thin:4d}  colors={len(set(map(tuple,o.reshape(-1,3))))}")
    comp = pxart.label_components(ink)
    print("ink cells", int(ink.sum()), "ink components", int(comp.max())+1)
    def up(a, k=8): return Image.fromarray(a).resize((a.shape[1]*k, a.shape[0]*k), Image.NEAREST)
    W = 512
    canvas = Image.new("RGB", (W*4, W), (255,255,255))
    canvas.paste(src, (0,0)); canvas.paste(up(base), (W,0)); canvas.paste(up(nocl), (W*2,0)); canvas.paste(up(out), (W*3,0))
    canvas.save("compare.png")
    m = np.zeros((th,tw,3),np.uint8); m[ink]=(255,0,0); m[~ink]=(40,40,40)
    up(m).save("inkmask.png")

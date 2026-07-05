"""
make_leather_skin.py -- worn oiled-leather bullwhip skin, pure stdlib (zlib+struct, no PIL/numpy).

Replaces the old write_whip_skin() diamond-plait lattice that read as a WICKER BASKET (a max of two
crossing sines sharpened into hard crowns with deep grooves == a woven crosshatch). This instead builds
ORGANIC leather: multi-octave value noise (grain + mottling) at LOW contrast over a saddle-brown base,
seamless around the tube (U wraps), with a darker oiled handle zone and a paler dusty tip. No lattice,
no hard grooves -> reads as leather, not basketweave.

Run:  python make_leather_skin.py [out.png]   (default: XRWhipLeather.png beside this file)
"""
import sys, os, math, struct, zlib

OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else \
      os.path.join(os.path.dirname(os.path.abspath(__file__)), "XRWhipLeather.png")
W, H = 256, 1024
HANDLE_FRAC = 0.16

# ---- palette (linear-ish sRGB values, kept close together = LOW contrast leather) ----
BASE   = (0.40, 0.255, 0.145)   # saddle brown body
DARK   = (0.30, 0.185, 0.100)   # grain shadow (only a little darker than base)
LIGHT  = (0.49, 0.335, 0.210)   # worn highlight (only a little lighter)
HANDLE = (0.235, 0.135, 0.075)  # hand-oiled darker grip
DUSTY  = (0.55, 0.43, 0.31)     # paler dusty fall/tip


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _hash(ix, iy):
    # deterministic pseudo-random in [0,1) from integer grid coords (no Math.random needed)
    h = (ix * 374761393 + iy * 668265263) & 0xffffffff
    h = (h ^ (h >> 13)) * 1274126177 & 0xffffffff
    return ((h ^ (h >> 16)) & 0xffff) / 65535.0


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def value_noise(u, v, gw, gh):
    """Bilinear value noise on a gw x gh grid; WRAPS in u (period gw) for a seamless tube seam."""
    x = u * gw
    y = v * gh
    ix, iy = int(math.floor(x)), int(math.floor(y))
    fx, fy = _smooth(x - ix), _smooth(y - iy)
    def g(a, b):
        return _hash(a % gw, b)   # u wraps (mod gw); v does not
    v00 = g(ix, iy);     v10 = g(ix + 1, iy)
    v01 = g(ix, iy + 1); v11 = g(ix + 1, iy + 1)
    return (v00 * (1 - fx) + v10 * fx) * (1 - fy) + (v01 * (1 - fx) + v11 * fx) * fy


def fbm(u, v):
    """Fractal (multi-octave) noise -> organic leather grain. All octaves wrap in u."""
    n = 0.0
    n += 0.55 * value_noise(u, v, 6, 24)     # broad mottling
    n += 0.28 * value_noise(u, v, 16, 64)    # medium grain
    n += 0.13 * value_noise(u, v, 40, 160)   # fine grain
    n += 0.06 * value_noise(u, v, 96, 384)   # pore speckle
    return n  # ~[0,1], mean ~0.5


def s255(c):
    return bytes(max(0, min(255, int(round(x * 255.0)))) for x in c)


raw = bytearray()
for y in range(H):
    v = y / H
    raw.append(0)  # PNG filter byte (None) per scanline
    for x in range(W):
        u = x / W
        n = fbm(u, v)
        # map grain around the base: LOW contrast (grain only nudges toward dark/light)
        if n < 0.5:
            col = lerp(BASE, DARK, (0.5 - n) * 2.0 * 0.7)
        else:
            col = lerp(BASE, LIGHT, (n - 0.5) * 2.0 * 0.7)
        # a very faint single-direction fiber sheen (NOT a crossing lattice) -- hints at leather grain
        fiber = 0.03 * math.sin(2.0 * math.pi * (v * 40.0 + u * 2.0))
        col = tuple(c + fiber for c in col)
        # zone tint: oiled darker handle at the butt, paler dusty toward the tip
        if v < HANDLE_FRAC:
            z = _smooth(max(0.0, min(1.0, (HANDLE_FRAC - v) / HANDLE_FRAC)))
            col = lerp(col, HANDLE, 0.5 * z)
        elif v > 0.86:
            z = _smooth(max(0.0, min(1.0, (v - 0.86) / 0.14)))
            col = lerp(col, DUSTY, 0.4 * z)
        raw.extend(s255(col))


def chunk(typ, data):
    return struct.pack(">I", len(data)) + typ + data + \
           struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)


with open(OUT, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n")
    f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)))  # 8-bit truecolor
    f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    f.write(chunk(b"IEND", b""))
print("wrote", OUT, os.path.getsize(OUT), "bytes")

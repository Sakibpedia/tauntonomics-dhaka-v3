#!/usr/bin/env python3
"""
generate_textures.py — procedural, seamless PBR texture sets for the Dhaka overhaul (Godot 4.6).

Every map tiles perfectly. Noise comes from spectral (FFT) synthesis and periodic cellular
noise, so there are no seams at the edges.

Materials
  brick_weathered      weathered red brick: running bond, chipped arrises, salt bloom, soot streaks, moss in joints
  asphalt_cracked      cracked asphalt: aggregate, alligator and long cracks, tar sealant, pothole puddle, oil stains
  tin_galvanized       corrugated galvanised roofing: spangle, dents, lap seam, screws with rust drips
  tin_painted_green    the same sheet painted green (as on the Sontek rooftops), chalky fade and peeling
  concrete_mossy       board-formed concrete: lift lines, tie holes, pores, cracks, water streaks, moss and lichen
  awning_stripes_red   market awning, red/cream canvas stripes
  awning_stripes_blue  market awning, blue/yellow stripes
  awning_blockprint    green cotton with block-printed medallions
  awning_tarp_blue     woven HDPE tarpaulin with repair patches

Outputs, per material, in <out>/<name>/
  <name>_albedo.png     sRGB colour
  <name>_normal.png     tangent-space normal, OpenGL convention (+Y up), the format Godot uses
  <name>_roughness.png  linear roughness
  <name>_ao.png         ambient occlusion
  <name>_height.png     16-bit height (white = high) for Godot's heightmap / parallax
  <name>_metallic.png   for the tin materials only
  <name>_orm.png        packed R = AO, G = roughness, B = metallic (for ORMMaterial3D)
  <name>.tres           Godot StandardMaterial3D, world-space triplanar (for procedural boxes)
  <name>_uv.tres        the same with UV mapping and deep parallax (for modelled meshes)
Optional: <out>/_preview.png, a lit 2x2-tiled contact sheet that shows tiling and normals.

Requires numpy and Pillow:  pip install numpy pillow
Usage:
  python generate_textures.py --out ../assets/textures --size 2048
  python generate_textures.py --only brick_weathered,asphalt_cracked --size 1024 --preview
  python generate_textures.py --res-prefix res://assets/textures --seed 11
"""
from __future__ import annotations

import argparse
import os
import time

import numpy as np
from PIL import Image, ImageDraw

# ============================================================================ core utilities
_GRID: dict[int, tuple[np.ndarray, np.ndarray]] = {}


def grid(n: int) -> tuple[np.ndarray, np.ndarray]:
    if n not in _GRID:
        y, x = np.mgrid[0:n, 0:n].astype(np.float32)
        _GRID[n] = (x, y)
    return _GRID[n]


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    if isinstance(t, np.ndarray) and t.ndim == 2 and (np.ndim(a) in (1, 3) or np.ndim(b) in (1, 3)):
        t = t[..., None]
    return a + (b - a) * t


def norm01(a: np.ndarray) -> np.ndarray:
    a = a - a.min()
    return a / (a.max() + 1e-9)


def hexcol(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


def fill(n: int, c: np.ndarray) -> np.ndarray:
    return np.broadcast_to(c, (n, n, 3)).astype(np.float32).copy()


def noise(n: int, seed: int, beta: float = 2.0, fmin: float = 1.0, fmax: float | None = None,
          aniso: tuple[float, float] = (1.0, 1.0)) -> np.ndarray:
    """Seamless fractal noise by spectral synthesis. beta is the 1/f^beta power exponent.
    fmin/fmax are cycles per tile. aniso=(1, 8) gives vertical streaks."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n)).astype(np.float32)
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(n)[:, None] * n
    kx = np.fft.fftfreq(n)[None, :] * n
    k = np.sqrt((kx * aniso[0]) ** 2 + (ky * aniso[1]) ** 2)
    kr = np.sqrt(kx ** 2 + ky ** 2)
    k[0, 0] = 1.0
    amp = 1.0 / np.power(k, beta * 0.5)
    amp[0, 0] = 0.0
    amp *= kr >= fmin
    if fmax is not None:
        amp *= kr <= fmax
    out = np.real(np.fft.ifft2(f * amp)).astype(np.float32)
    return norm01(out)


def blur(img: np.ndarray, sigma: float) -> np.ndarray:
    """Periodic (wrap-around) Gaussian blur via FFT."""
    if sigma <= 0:
        return img
    h, w = img.shape[:2]
    ky = np.fft.fftfreq(h)[:, None]
    kx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (kx ** 2 + ky ** 2))
    if img.ndim == 3:
        return np.stack([np.real(np.fft.ifft2(np.fft.fft2(img[..., c]) * g)) for c in range(img.shape[2])], -1).astype(np.float32)
    return np.real(np.fft.ifft2(np.fft.fft2(img) * g)).astype(np.float32)


def blur_aniso(img: np.ndarray, sx: float, sy: float, shift_down: int = 0) -> np.ndarray:
    """Periodic anisotropic Gaussian blur; optional downward shift makes stains run with gravity."""
    h, w = img.shape
    ky = np.fft.fftfreq(h)[:, None]
    kx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * ((sx * kx) ** 2 + (sy * ky) ** 2))
    out = np.real(np.fft.ifft2(np.fft.fft2(img) * g)).astype(np.float32)
    return np.roll(out, shift_down, axis=0) if shift_down else out


def cellular(n: int, cells: int, seed: int, x: np.ndarray | None = None, y: np.ndarray | None = None):
    """Periodic jittered-grid Worley noise. Returns F1, F2 (in cell units) and the cell id."""
    rng = np.random.default_rng(seed)
    jit = rng.random((cells, cells, 2)).astype(np.float32)
    cs = n / cells
    if x is None or y is None:
        x, y = grid(n)
    gx = np.floor(x / cs).astype(np.int64)
    gy = np.floor(y / cs).astype(np.int64)
    f1 = np.full(x.shape, np.inf, np.float32)
    f2 = np.full(x.shape, np.inf, np.float32)
    ids = np.zeros(x.shape, np.int64)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx = gx + ox
            cy = gy + oy
            cxw = cx % cells
            cyw = cy % cells
            px = (cx + jit[cyw, cxw, 0]) * cs
            py = (cy + jit[cyw, cxw, 1]) * cs
            d = np.hypot(x - px, y - py).astype(np.float32)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            ids = np.where(closer, cyw * cells + cxw, ids)
            f1 = np.where(closer, d, f1)
    return f1 / cs, f2 / cs, ids


def warp(n: int, seed: int, amount: float, fmax: float = 12.0, beta: float = 2.4):
    x, y = grid(n)
    wx = (noise(n, seed, beta, fmax=fmax) - 0.5) * 2.0 * amount
    wy = (noise(n, seed + 1, beta, fmax=fmax) - 0.5) * 2.0 * amount
    return x + wx, y + wy


def wrap_dist(a: np.ndarray, b: float, period: float) -> np.ndarray:
    d = np.abs(a - b) % period
    return np.minimum(d, period - d)


def normal_from_height(h: np.ndarray, strength: float) -> np.ndarray:
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength          # image rows grow downward; OpenGL normal maps want +Y up
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], -1)


def cavity_ao(h: np.ndarray, scale: float, gain: float = 6.0) -> np.ndarray:
    ao = np.zeros_like(h)
    for r, wgt in ((2.0, 0.45), (7.0, 0.35), (22.0, 0.2)):
        ao += wgt * np.maximum(blur(h, r * scale) - h, 0.0)
    return np.clip(1.0 - ao * gain, 0.0, 1.0) ** 1.2


def desaturate(c: np.ndarray, t) -> np.ndarray:
    g = (c[..., 0] * 0.3 + c[..., 1] * 0.59 + c[..., 2] * 0.11)[..., None]
    return lerp(c, np.repeat(g, 3, -1), t)


# ============================================================================ materials
def mat_brick(n: int, seed: int) -> dict:
    s = n / 1024.0
    rng = np.random.default_rng(seed)
    rows, bpr = 16, 5
    rh, bw = n / rows, n / bpr
    x, y = warp(n, seed + 1, 1.6 * s, fmax=10)
    row = np.floor(y / rh).astype(np.int64) % rows
    row_off = (np.arange(rows) % 2) * bw * 0.5 + rng.uniform(-0.08, 0.08, rows) * bw
    xb = x + row_off[row]
    col = np.floor(xb / bw).astype(np.int64) % bpr
    bid = row * bpr + col
    lx = np.mod(xb, bw)
    ly = np.mod(y, rh)
    dx = np.minimum(lx, bw - lx)
    dy = np.minimum(ly, rh - ly)
    mortar_half = rh * 0.075
    chip_n = noise(n, seed + 2, 1.4, fmin=24)
    d = np.minimum(dx, dy) + (chip_n - 0.5) * rh * 0.16
    brick = smoothstep(mortar_half, mortar_half + 1.6 * s, d)
    bevel = smoothstep(mortar_half, mortar_half + rh * 0.2, d)

    pal = np.stack([hexcol(h) for h in ("#8e3b2b", "#a04630", "#7a3326", "#b45d3d", "#6b2e24", "#94553b", "#5b2a22", "#a8573a")])
    pal_idx = rng.integers(0, len(pal), rows * bpr)
    shade = rng.uniform(0.82, 1.12, rows * bpr).astype(np.float32)
    protrude = rng.uniform(-0.05, 0.05, rows * bpr).astype(np.float32)
    base = pal[pal_idx[bid]] * shade[bid][..., None] * 0.9

    blotch = noise(n, seed + 3, 2.2, fmax=40)
    grain = noise(n, seed + 4, 0.8, fmin=120)
    pits = noise(n, seed + 5, 1.0, fmin=90)
    pit_mask = smoothstep(0.78, 0.86, pits)
    alb_b = base * (0.8 + 0.34 * blotch)[..., None] * (0.92 + 0.16 * grain)[..., None]
    alb_b = lerp(alb_b, alb_b * 0.55, pit_mask * 0.8)
    speck = smoothstep(0.86, 0.9, noise(n, seed + 6, 0.6, fmin=200))
    alb_b = lerp(alb_b, hexcol("#d8b9a0"), speck * 0.35)
    chips = (smoothstep(0.6, 0.66, noise(n, seed + 7, 1.6, fmin=10)) * (1.0 - bevel) * brick)
    alb_b = lerp(alb_b, hexcol("#c26a45"), chips * 0.75)

    mortar_n = noise(n, seed + 8, 1.2, fmin=60)
    alb_m = fill(n, hexcol("#77716a")) * (0.7 + 0.36 * mortar_n)[..., None]
    alb = lerp(alb_m, alb_b, brick)

    # salt bloom (efflorescence) sits low on bricks and in damp zones
    damp = noise(n, seed + 9, 2.6, fmax=8)
    effl = smoothstep(0.62, 0.8, noise(n, seed + 10, 2.0, fmax=30) * 0.6 + damp * 0.5) * (0.4 + 0.6 * (ly / rh))
    alb = lerp(alb, hexcol("#ddd6c8"), effl * 0.55)
    # soot / rain streaks
    streak = noise(n, seed + 11, 2.2, aniso=(1.0, 9.0), fmin=2, fmax=48)
    soot = smoothstep(0.5, 0.85, streak) * (0.45 + 0.55 * damp)
    alb = alb * (1.0 - soot[..., None] * 0.5)
    grime = noise(n, seed + 14, 2.0, fmax=16)
    alb = alb * (0.85 + 0.2 * grime)[..., None]
    # moss only in damp joints
    moss = smoothstep(0.7, 0.86, noise(n, seed + 12, 2.4, fmax=14) * 0.6 + damp * 0.55) * (1.0 - brick)
    moss *= smoothstep(0.3, 0.7, noise(n, seed + 13, 1.0, fmin=60))
    moss_col = lerp(hexcol("#2f3a19"), hexcol("#56602a"), noise(n, seed + 13, 1.0, fmin=80))
    alb = lerp(alb, moss_col, moss * 0.8)
    wet = smoothstep(0.7, 0.85, damp)
    alb = alb * (1.0 - wet[..., None] * 0.18)

    h_b = 0.62 + 0.28 * bevel + protrude[bid] - 0.12 * pit_mask - 0.25 * chips + 0.04 * (grain - 0.5)
    h_m = 0.12 + 0.08 * mortar_n + 0.08 * moss
    height = lerp(h_m, h_b, brick)

    rough = lerp(0.95, 0.82 + 0.1 * grain, brick)
    rough = rough - 0.32 * wet + 0.05 * effl
    ao_extra = lerp(0.7, 1.0, brick)
    return {"albedo": alb, "height": height, "roughness": rough, "ao_extra": ao_extra, "normal_strength": 12.0, "parallax": 0.05}


def mat_asphalt(n: int, seed: int) -> dict:
    s = n / 1024.0
    tone = noise(n, seed + 1, 2.0, fmax=24)
    alb = fill(n, hexcol("#2c2c2d")) * (0.75 + 0.5 * tone)[..., None]
    # aggregate
    xw, yw = warp(n, seed + 2, 3.0 * s, fmax=60)
    cells_a = 190
    f1, f2, ids = cellular(n, cells_a, seed + 3, xw, yw)
    rng = np.random.default_rng(seed + 4)
    stone_shade = rng.uniform(0.0, 1.0, cells_a * cells_a).astype(np.float32)
    stone_size = rng.uniform(0.18, 0.42, cells_a * cells_a).astype(np.float32)
    stones = smoothstep(stone_size[ids], stone_size[ids] - 0.14, f1) * (stone_shade[ids] > 0.25)
    stone_col = lerp(hexcol("#3f3c39"), hexcol("#7b766f"), stone_shade[ids] ** 1.6)
    stone_col = lerp(stone_col, hexcol("#9a8b76"), (stone_shade[ids] > 0.97).astype(np.float32) * 0.6)
    worn = smoothstep(0.3, 0.75, noise(n, seed + 14, 2.0, fmax=20))
    alb = lerp(alb, stone_col * (0.85 + 0.3 * tone)[..., None], stones * (0.25 + 0.4 * worn))
    grit = noise(n, seed + 5, 0.4, fmin=260)
    alb = alb * (0.86 + 0.28 * grit)[..., None]
    # cracks: alligator patches + long cracks
    xc, yc = warp(n, seed + 6, 18.0 * s, fmax=20)
    c1, c2, _ = cellular(n, 12, seed + 7, xc, yc)
    gator_zone = smoothstep(0.5, 0.62, noise(n, seed + 8, 2.6, fmax=6))
    gator = (1.0 - smoothstep(0.0, 0.05, c2 - c1)) * gator_zone
    xl, yl = warp(n, seed + 9, 40.0 * s, fmax=10)
    l1, l2, _ = cellular(n, 3, seed + 10, xl, yl)
    longc = 1.0 - smoothstep(0.0, 0.012, l2 - l1)
    cracks = np.clip(gator + longc, 0.0, 1.0)
    sealant = smoothstep(0.08, 0.2, blur(longc, 6.0 * s)) * (1.0 - longc)
    alb = lerp(alb, hexcol("#141414"), sealant * 0.8)
    dust = smoothstep(0.05, 0.3, blur(cracks, 4.0 * s))
    alb = lerp(alb, hexcol("#5b4f40"), dust * 0.35)
    alb = lerp(alb, hexcol("#070707"), cracks)
    # pothole with gravel and a puddle
    pot = smoothstep(0.84, 0.9, noise(n, seed + 11, 3.2, fmax=4))
    puddle = smoothstep(0.9, 0.95, noise(n, seed + 11, 3.2, fmax=4))
    alb = lerp(alb, hexcol("#3d3a35") * (0.8 + 0.5 * grit)[..., None], pot * 0.8)
    alb = lerp(alb, hexcol("#15181a"), puddle * 0.8)
    # oil drips and tyre polish
    oil = smoothstep(0.74, 0.82, noise(n, seed + 12, 2.4, fmax=18))
    alb = lerp(alb, hexcol("#101010"), oil * 0.55)
    polish = smoothstep(0.55, 0.8, noise(n, seed + 13, 2.0, aniso=(8.0, 1.0), fmax=40))
    alb = lerp(alb, alb * 1.25, polish * 0.4)

    height = 0.5 + 0.12 * tone + 0.16 * stones * (0.4 + 0.6 * worn) + 0.06 * (grit - 0.5) - 0.45 * cracks - 0.3 * pot + 0.05 * sealant
    rough = 0.88 - 0.08 * stones + 0.08 * cracks - 0.4 * sealant - 0.5 * oil * 0.8 - 0.15 * polish
    rough = lerp(rough, 0.04, puddle)
    return {"albedo": alb, "height": np.clip(height, 0, 1), "roughness": rough, "ao_extra": 1.0 - 0.3 * cracks,
            "normal_strength": 7.0, "parallax": 0.02}


def mat_tin(n: int, seed: int, painted: str | None = None) -> dict:
    s = n / 1024.0
    x, y = grid(n)
    period = n / 16.0
    wob = (noise(n, seed + 1, 3.0, fmax=5) - 0.5) * period * 0.12
    xs = x + wob
    corr = 0.5 + 0.5 * np.cos(2.0 * np.pi * xs / period)
    trough = 1.0 - corr
    dents = noise(n, seed + 2, 3.2, fmax=10)
    # horizontal lap seam: upper sheet overlaps the lower one
    lap_y = n * 0.5
    lap = n * 0.025
    yy = np.mod(y - lap_y, n)
    over = (yy > n - lap).astype(np.float32)
    edge_shadow = smoothstep(14.0 * s, 0.0, yy) * 0.6
    # screws on crests, two rows per sheet
    screw = np.zeros((n, n), np.float32)
    halo = np.zeros((n, n), np.float32)
    drips = np.zeros((n, n), np.float32)
    rng = np.random.default_rng(seed + 3)
    for ry in (n * 0.07, n * 0.57):
        for k in range(0, 16, 2):
            sx = k * period
            dxs = wrap_dist(x, sx, n)
            dys = wrap_dist(y, ry, n)
            r = np.hypot(dxs, dys)
            screw = np.maximum(screw, smoothstep(5.0 * s, 3.5 * s, r))
            halo = np.maximum(halo, smoothstep(18.0 * s, 4.0 * s, r) * rng.uniform(0.3, 1.0))
            length = rng.uniform(60, 260) * s
            below = np.mod(y - ry, n)
            drip = smoothstep(3.5 * s, 0.5 * s, dxs) * smoothstep(length, 0.0, below) * (below > 0)
            drips = np.maximum(drips, drip * rng.uniform(0.4, 1.0))
    rust_field = noise(n, seed + 4, 2.6, fmax=30) * 0.72 + noise(n, seed + 14, 1.1, fmin=40) * 0.28
    drive = rust_field + 0.16 * trough + 0.2 * over + 0.32 * halo + 0.18 * edge_shadow
    rust = smoothstep(0.7 if painted else 0.66, 0.84 if painted else 0.8, drive)
    rust = np.clip(rust + drips * 0.7, 0.0, 1.0)
    rust_runs = np.clip(blur_aniso(rust, 1.2 * s, 34.0 * s, int(30 * s)) * 1.6 - rust, 0.0, 1.0) * (0.5 + 0.5 * trough)
    stain = np.clip(blur(rust, 7.0 * s) * 1.6 - rust, 0.0, 1.0)
    rn = noise(n, seed + 5, 1.6, fmin=20)
    rust_col = lerp(hexcol("#3a190b"), hexcol("#743614"), rn)
    rust_col = lerp(rust_col, hexcol("#a5541f"), smoothstep(0.72, 0.9, rn) * 0.4)
    rust_col = lerp(rust_col, hexcol("#2a140a"), smoothstep(0.6, 0.9, noise(n, seed + 6, 1.2, fmin=60)) * 0.5)

    _, _, spid = cellular(n, 36, seed + 7)
    sp_shade = np.random.default_rng(seed + 8).uniform(0.82, 1.08, 36 * 36).astype(np.float32)
    galv = fill(n, hexcol("#9ea4a6")) * sp_shade[spid][..., None]
    galv = galv * (0.88 + 0.14 * noise(n, seed + 9, 1.2, fmin=80))[..., None]
    white_rust = smoothstep(0.62, 0.85, noise(n, seed + 15, 2.2, fmax=20)) * 0.3
    galv = lerp(galv, hexcol("#c9cdca"), white_rust)
    metal = 0.85 * np.ones((n, n), np.float32)
    rough = 0.34 + 0.12 * (1.0 - sp_shade[spid])
    alb = galv
    if painted:
        paint = fill(n, hexcol(painted))
        chalk = noise(n, seed + 10, 2.0, fmax=24)
        paint = lerp(paint, desaturate(paint, 1.0) * 1.35, chalk * 0.45)
        peel = np.maximum(smoothstep(0.64, 0.67, drive), smoothstep(0.8, 0.83, noise(n, seed + 11, 1.8, fmin=6)))
        peel *= smoothstep(0.35, 0.6, noise(n, seed + 16, 1.4, fmin=40))
        alb = lerp(paint, galv, peel)
        metal = lerp(0.12, 0.85, peel)
        rough = lerp(0.62 + 0.15 * chalk, rough, peel)
    streak = smoothstep(0.5, 0.85, noise(n, seed + 12, 2.2, aniso=(1.0, 10.0), fmin=3, fmax=60)) * (0.4 + 0.6 * trough)
    alb = alb * (1.0 - streak[..., None] * 0.3)
    alb = alb * (1.0 - 0.28 * trough)[..., None]
    alb = lerp(alb, hexcol("#5a3f2a"), np.clip(stain * 0.6 + rust_runs * 0.75, 0.0, 0.85))
    alb = lerp(alb, rust_col, rust)
    alb = alb * (1.0 - edge_shadow[..., None] * 0.5)
    alb = lerp(alb, hexcol("#7c8285"), screw)
    metal = lerp(metal, 0.0, rust)
    rough = lerp(rough, 0.93, rust)
    rough = lerp(rough, 0.75, np.clip(rust_runs + stain * 0.5, 0.0, 1.0))
    height = 0.15 + 0.7 * corr + 0.06 * (dents - 0.5) + 0.08 * over + 0.06 * screw + 0.03 * rust * noise(n, seed + 13, 0.8, fmin=100)
    return {"albedo": alb, "height": height, "roughness": rough, "metallic": metal,
            "ao_extra": 1.0 - 0.35 * trough - 0.4 * edge_shadow, "normal_strength": 5.0, "parallax": 0.03}


def mat_concrete(n: int, seed: int) -> dict:
    s = n / 1024.0
    x, y = grid(n)
    blot = noise(n, seed + 1, 2.4, fmax=20)
    fine = noise(n, seed + 2, 0.9, fmin=150)
    alb = fill(n, hexcol("#8b8a85")) * (0.78 + 0.32 * blot)[..., None] * (0.9 + 0.2 * fine)[..., None]
    # board-formed pours: lift lines every quarter tile, each pour a slightly different tone
    lift = n / 4.0
    band = np.floor(y / lift).astype(np.int64) % 4
    band_tone = np.array([1.0, 0.94, 1.04, 0.97], np.float32)
    alb = alb * band_tone[band][..., None]
    ly = np.mod(y, lift)
    line = smoothstep(3.0 * s, 0.0, np.minimum(ly, lift - ly))
    boards = (np.floor(y / (lift / 6.0)).astype(np.int64) % 2).astype(np.float32)
    alb = alb * (1.0 - 0.03 * boards)[..., None]
    # tie holes
    ties = np.zeros((n, n), np.float32)
    rust_runs = np.zeros((n, n), np.float32)
    rng = np.random.default_rng(seed + 3)
    for b in range(4):
        cy = b * lift + lift * 0.5
        for k in range(4):
            cx = k * n / 4.0 + (n / 8.0 if b % 2 else 0.0)
            r = np.hypot(wrap_dist(x, cx, n), wrap_dist(y, cy, n))
            ties = np.maximum(ties, smoothstep(9.0 * s, 6.0 * s, r))
            if rng.random() < 0.6:
                below = np.mod(y - cy, n)
                run = smoothstep(6.0 * s, 1.0 * s, wrap_dist(x, cx, n)) * smoothstep(rng.uniform(80, 220) * s, 0.0, below)
                rust_runs = np.maximum(rust_runs, run * (below > 0))
    pores = smoothstep(0.86, 0.92, noise(n, seed + 4, 0.7, fmin=180))
    xc, yc = warp(n, seed + 5, 30.0 * s, fmax=14)
    c1, c2, _ = cellular(n, 4, seed + 6, xc, yc)
    cracks = (1.0 - smoothstep(0.0, 0.01, c2 - c1)) * smoothstep(0.45, 0.6, noise(n, seed + 7, 2.2, fmax=6))
    # water streaks hang below lift lines
    streak_n = noise(n, seed + 8, 2.2, aniso=(1.0, 12.0), fmin=3, fmax=64)
    hang = smoothstep(lift * 0.9, 0.0, ly)
    streaks = smoothstep(0.5, 0.82, streak_n) * (0.35 + 0.65 * hang)
    alb = alb * (1.0 - streaks[..., None] * 0.32)
    alb = lerp(alb, hexcol("#7a4a2a"), rust_runs * 0.55)
    alb = lerp(alb, hexcol("#3b3a37"), pores * 0.8)
    alb = lerp(alb, hexcol("#1d1c1a"), cracks)
    alb = lerp(alb, alb * 0.7, line * 0.6)
    # moss and lichen
    moss_field = noise(n, seed + 9, 2.4, fmax=10)
    moss_detail = noise(n, seed + 10, 1.0, fmin=70)
    breakup = noise(n, seed + 16, 1.3, fmin=30)
    moss_drive = moss_field * 0.75 + breakup * 0.25 + 0.35 * np.clip(blur(cracks, 8.0 * s) * 4.0, 0, 1) + 0.18 * streaks + 0.1 * line
    moss = smoothstep(0.6, 0.82, moss_drive)
    damp_halo = np.clip(blur(moss, 12.0 * s) * 1.4 - moss * 0.6, 0.0, 1.0)
    alb = alb * (1.0 - 0.28 * damp_halo)[..., None]
    grime = noise(n, seed + 17, 2.0, fmax=18)
    alb = alb * (0.84 + 0.22 * grime)[..., None]
    moss_col = lerp(hexcol("#252f15"), hexcol("#4d5a22"), moss_detail)
    moss_col = lerp(moss_col, hexcol("#6c7530"), smoothstep(0.78, 0.92, moss_detail) * 0.5)
    alb = lerp(alb, moss_col, moss * (0.65 + 0.35 * moss_detail))
    l1, _, lid = cellular(n, 64, seed + 11)
    lich_on = np.random.default_rng(seed + 12).random(64 * 64) > 0.93
    lichen = smoothstep(0.24, 0.14, l1) * lich_on[lid] * smoothstep(0.45, 0.7, moss_field)
    lich_col = np.where((lid % 3 == 0)[..., None], hexcol("#a89a6c"), hexcol("#b9b8ad"))
    alb = lerp(alb, lich_col, lichen * 0.45)

    height = 0.5 + 0.06 * (blot - 0.5) + 0.05 * (fine - 0.5) - 0.25 * pores - 0.4 * cracks - 0.35 * ties + 0.06 * line \
        + 0.18 * moss * moss_detail + 0.04 * lichen
    rough = 0.86 + 0.06 * fine - 0.25 * streaks + 0.08 * moss - 0.1 * rust_runs
    return {"albedo": alb, "height": np.clip(height, 0, 1), "roughness": rough,
            "ao_extra": 1.0 - 0.5 * ties - 0.3 * cracks, "normal_strength": 6.0, "parallax": 0.02}


def _weave(n: int, pitch: float):
    x, y = grid(n)
    a = np.sin(np.pi * np.mod(x, pitch) / pitch)
    b = np.sin(np.pi * np.mod(y, pitch) / pitch)
    checker = (np.floor(x / pitch) + np.floor(y / pitch)) % 2
    return np.where(checker > 0, a, b).astype(np.float32)


def mat_fabric(n: int, seed: int, variant: str) -> dict:
    s = n / 1024.0
    x, y = grid(n)
    xw, yw = warp(n, seed + 1, 6.0 * s, fmax=10)
    folds = noise(n, seed + 2, 2.6, aniso=(1.0, 10.0), fmax=14)
    sag = noise(n, seed + 3, 3.0, fmax=5)
    fade = noise(n, seed + 4, 2.2, fmax=10)
    dirt = smoothstep(0.55, 0.85, noise(n, seed + 5, 2.0, fmax=24))
    weave_pitch = max(n / 256.0, 3.0)
    rough_base = 0.9
    if variant == "stripes_red":
        stripe = (np.floor(xw / (n / 8.0)) % 2).astype(np.float32)
        alb = lerp(fill(n, hexcol("#e6dcc6")), fill(n, hexcol("#a8232a")), stripe)
    elif variant == "stripes_blue":
        stripe = (np.floor(xw / (n / 16.0)) % 2).astype(np.float32)
        alb = lerp(fill(n, hexcol("#e0b22c")), fill(n, hexcol("#1d4f93")), stripe)
    elif variant == "blockprint":
        cell = n / 4.0
        lx = np.mod(xw + np.where(np.floor(yw / cell) % 2 > 0, cell * 0.5, 0.0), cell) - cell * 0.5
        lyc = np.mod(yw, cell) - cell * 0.5
        r = np.hypot(lx, lyc) / cell
        th = np.arctan2(lyc, lx)
        petals = r < 0.18 + 0.12 * np.abs(np.cos(th * 4.0))
        ring = np.abs(r - 0.38) < 0.02
        dots = (np.abs(r - 0.45) < 0.025) & (np.cos(th * 16.0) > 0.6)
        core = r < 0.06
        ink_fade = smoothstep(0.25, 0.7, noise(n, seed + 6, 1.4, fmin=20))
        alb = fill(n, hexcol("#2c6a46"))
        alb = lerp(alb, hexcol("#e9dcc0"), (petals | ring | dots).astype(np.float32) * ink_fade)
        alb = lerp(alb, hexcol("#7a1f2a"), core.astype(np.float32) * ink_fade)
        border = np.abs(np.mod(y, n / 2.0) - n / 4.0) < 6.0 * s
        alb = lerp(alb, hexcol("#7a1f2a"), border.astype(np.float32) * 0.8)
    elif variant == "tarp_blue":
        weave_pitch = n / 96.0
        alb = fill(n, hexcol("#1f63b4"))
        band = np.abs(np.mod(y, n / 2.0) - n * 0.06) < n * 0.012
        alb = lerp(alb, hexcol("#e9eef2"), band.astype(np.float32))
        patch = np.zeros((n, n), np.float32)
        rng = np.random.default_rng(seed + 9)
        for _ in range(3):
            cx, cy = rng.uniform(0, n, 2)
            w, h = rng.uniform(170, 330, 2) * s
            inside = (wrap_dist(x, cx, n) < w * 0.5) & (wrap_dist(y, cy, n) < h * 0.5)
            patch = np.maximum(patch, inside.astype(np.float32))
        patch = blur(patch, 1.0 * s)
        tape = np.clip(blur(patch, 4.0 * s) * 2.0 - patch * 1.6, 0.0, 1.0)
        alb = lerp(alb, hexcol("#c9642a"), smoothstep(0.4, 0.6, patch))
        alb = lerp(alb, hexcol("#bdb9ad"), tape * 0.8)
        kx, ky = warp(n, seed + 13, 40.0 * s, fmax=16)
        k1, k2, _ = cellular(n, 9, seed + 12, kx, ky)
        crinkle = (1.0 - smoothstep(0.0, 0.025, k2 - k1)) * smoothstep(0.35, 0.65, noise(n, seed + 14, 1.5, fmin=8))
        rough_base = 0.5
    else:
        alb = fill(n, hexcol("#9c7a4a"))
    weave = _weave(n, weave_pitch)
    alb = lerp(alb, desaturate(alb, 1.0) * 1.25 + 0.06, fade * 0.38)
    alb = alb * (0.86 + 0.14 * weave)[..., None]
    alb = alb * (0.8 + 0.25 * folds)[..., None]
    alb = lerp(alb, hexcol("#4a3b28"), dirt * 0.35)
    l1, _, _ = cellular(n, 6, seed + 10)
    watermark = smoothstep(0.03, 0.0, np.abs(l1 - 0.35)) * smoothstep(0.5, 0.7, noise(n, seed + 11, 2.0, fmax=8))
    alb = lerp(alb, alb * 0.75, watermark * 0.6)
    height = 0.35 * folds + 0.25 * sag + 0.12 * weave
    if variant == "tarp_blue":
        height = height + 0.12 * crinkle
        alb = alb * (1.0 - 0.06 * crinkle)[..., None]
    rough = rough_base + 0.05 * dirt - 0.05 * weave
    return {"albedo": np.clip(alb, 0, 1), "height": height, "roughness": rough, "ao_extra": 0.85 + 0.15 * weave,
            "normal_strength": 10.0, "parallax": 0.0}


def mat_plaster(n: int, seed: int) -> dict:
    """Painted cement plaster as on the Sontek/Kajla walk-ups. Kept near-white so per-building
    vertex colours tint it pastel pink, cream, mint or sky blue. Rain streaks hang from the top
    of the tile (under each sill when tiled per storey), rising damp sits at the bottom, and there are
    hairline map cracks, repaint patches and flaking."""
    s = n / 1024.0
    x, y = grid(n)
    base = noise(n, seed + 1, 2.2, fmax=24)
    fine = noise(n, seed + 2, 0.8, fmin=200)
    trowel = noise(n, seed + 3, 2.6, aniso=(3.0, 1.0), fmax=30)
    alb = fill(n, hexcol("#efebe2")) * (0.9 + 0.12 * base)[..., None] * (0.96 + 0.06 * fine)[..., None]
    # repainted patches: slightly different white, sharp-ish edge
    patch = smoothstep(0.6, 0.7, noise(n, seed + 4, 2.8, fmax=8))
    alb = lerp(alb, alb * np.array([1.02, 1.0, 0.97], np.float32), patch * 0.6)
    # rain streaks from the top of the tile (under sills) and grime
    streak_n = noise(n, seed + 5, 2.2, aniso=(1.0, 14.0), fmin=4, fmax=90)
    top = smoothstep(n * 0.75, 0.0, y)
    streaks = smoothstep(0.48, 0.8, streak_n) * top
    alb = alb * (1.0 - 0.38 * streaks[..., None] * np.array([1.0, 1.02, 1.08], np.float32))
    # rising damp and splash band
    damp = smoothstep(n * 0.78, n, y) * (0.55 + 0.45 * noise(n, seed + 6, 2.0, fmax=20))
    alb = lerp(alb, hexcol("#6f6a58"), np.clip(damp, 0, 1) * 0.5)
    # mould dots in the damp band
    mould = smoothstep(0.78, 0.9, noise(n, seed + 7, 1.2, fmin=40)) * damp
    alb = lerp(alb, hexcol("#3c4232"), mould * 0.45)
    # map cracks and flaking
    xc, yc = warp(n, seed + 8, 20.0 * s, fmax=14)
    c1, c2, _ = cellular(n, 7, seed + 9, xc, yc)
    cracks = (1.0 - smoothstep(0.0, 0.008, c2 - c1)) * smoothstep(0.5, 0.65, noise(n, seed + 10, 2.0, fmax=6))
    flake = smoothstep(0.8, 0.83, noise(n, seed + 11, 1.6, fmin=8, fmax=48))
    alb = lerp(alb, hexcol("#b3ada2"), flake * 0.7)
    alb = lerp(alb, hexcol("#4a463f"), cracks * 0.85)
    height = 0.5 + 0.08 * (trowel - 0.5) + 0.04 * (fine - 0.5) - 0.2 * flake - 0.3 * cracks + 0.03 * patch
    rough = 0.82 + 0.08 * fine - 0.1 * streaks + 0.08 * damp
    return {"albedo": np.clip(alb, 0, 1), "height": np.clip(height, 0, 1), "roughness": rough,
            "ao_extra": 1.0 - 0.3 * cracks - 0.15 * flake, "normal_strength": 4.0, "parallax": 0.01}


def mat_pavers(n: int, seed: int, variant: str) -> dict:
    """checker: the black/white 'parking checker' tiles from the photos. footpath: grey interlocking
    concrete pavers, chipped and stained."""
    s = n / 1024.0
    x, y = grid(n)
    tiles = 8 if variant == "checker" else 6
    p = n / tiles
    tx, ty = np.floor(x / p), np.floor(y / p)
    lx, ly = np.mod(x, p), np.mod(y, p)
    edge = np.minimum(np.minimum(lx, p - lx), np.minimum(ly, p - ly))
    joint = smoothstep(4.0 * s, 1.0 * s, edge)
    bevel = smoothstep(0.0, 10.0 * s, edge)
    rng = np.random.default_rng(seed)
    tone = rng.uniform(0.9, 1.08, (tiles, tiles)).astype(np.float32)
    t = tone[ty.astype(np.int64) % tiles, tx.astype(np.int64) % tiles]
    grime = noise(n, seed + 1, 2.0, fmax=20)
    fine = noise(n, seed + 2, 0.8, fmin=180)
    if variant == "checker":
        chk = ((tx + ty) % 2).astype(np.float32)
        alb = lerp(fill(n, hexcol("#d9d6cf")), fill(n, hexcol("#26272a")), chk)
        rough = 0.35 + 0.35 * grime + 0.1 * fine
    else:
        alb = fill(n, hexcol("#8f8c86"))
        rough = 0.82 + 0.1 * fine
    alb = alb * t[..., None] * (0.86 + 0.18 * grime)[..., None] * (0.95 + 0.08 * fine)[..., None]
    scuff = smoothstep(0.6, 0.85, noise(n, seed + 3, 1.6, aniso=(4.0, 1.0), fmin=6, fmax=80))
    alb = lerp(alb, hexcol("#5b5852"), scuff * 0.35)
    chips = smoothstep(0.8, 0.86, noise(n, seed + 4, 1.4, fmin=30)) * smoothstep(14.0 * s, 2.0 * s, edge)
    stains = smoothstep(0.66, 0.8, noise(n, seed + 5, 2.4, fmax=10))
    alb = lerp(alb, hexcol("#2d2a25"), stains * 0.35)
    alb = lerp(alb, hexcol("#4a4741"), joint * 0.85)
    alb = lerp(alb, hexcol("#6b6760"), chips * 0.8)
    height = 0.3 + 0.5 * bevel - 0.4 * joint - 0.25 * chips + 0.03 * fine
    return {"albedo": np.clip(alb, 0, 1), "height": np.clip(height, 0, 1), "roughness": np.clip(rough + 0.3 * joint, 0, 1),
            "ao_extra": 1.0 - 0.45 * joint, "normal_strength": 5.0, "parallax": 0.015}


def mat_cloth(n: int, seed: int, variant: str) -> dict:
    """Clothing. Neutral variants are near-white and are tinted per character with albedo_color
    (plain, check, stripe, print). Coloured variants keep their own palette (lungi, gamchha, denim)."""
    s = n / 1024.0
    x, y = grid(n)
    folds = noise(n, seed + 1, 2.6, aniso=(1.0, 6.0), fmax=10)
    wrinkle = noise(n, seed + 2, 2.0, aniso=(1.0, 3.0), fmin=6, fmax=40)
    fine = noise(n, seed + 3, 0.8, fmin=200)
    pitch = max(n / 320.0, 2.0)
    weave = _weave(n, pitch)
    white = fill(n, hexcol("#f2f0ec"))
    rough = 0.88
    if variant == "plain":
        alb = white
    elif variant == "check":
        a = (np.floor(x / (n / 8.0)) % 2).astype(np.float32)
        b = (np.floor(y / (n / 8.0)) % 2).astype(np.float32)
        fine_l = ((np.mod(x, n / 8.0) < 4 * s) | (np.mod(y, n / 8.0) < 4 * s)).astype(np.float32)
        alb = white * (1.0 - 0.28 * a - 0.28 * b)[..., None]
        alb = lerp(alb, hexcol("#3a3a3a"), fine_l * 0.4)
    elif variant == "stripe":
        st = (np.mod(x, n / 12.0) < n / 48.0).astype(np.float32)
        alb = lerp(white, white * 0.55, st)
    elif variant == "print":
        cell = n / 6.0
        lx = np.mod(x + np.where(np.floor(y / cell) % 2 > 0, cell * 0.5, 0.0), cell) - cell * 0.5
        lyc = np.mod(y, cell) - cell * 0.5
        r = np.hypot(lx, lyc) / cell
        th = np.arctan2(lyc, lx)
        petals = (r < 0.2 + 0.1 * np.cos(th * 5.0)).astype(np.float32)
        leaf = ((np.abs(r - 0.36) < 0.03) & (np.cos(th * 3.0) > 0.3)).astype(np.float32)
        border = (np.abs(np.mod(y, n) - n * 0.92) < n * 0.04).astype(np.float32)
        alb = white * (1.0 - 0.45 * petals - 0.3 * leaf)[..., None]
        alb = lerp(alb, hexcol("#c9a227"), border * 0.9)
    elif variant == "lungi":
        cx = np.mod(x, n / 4.0) / (n / 4.0)
        cy = np.mod(y, n / 4.0) / (n / 4.0)
        alb = fill(n, hexcol("#1e3f7a"))
        alb = lerp(alb, hexcol("#2d6bb3"), ((cx > 0.5) ^ (cy > 0.5)).astype(np.float32) * 0.6)
        lines = ((np.abs(cx - 0.25) < 0.02) | (np.abs(cy - 0.25) < 0.02)).astype(np.float32)
        alb = lerp(alb, hexcol("#e9e4d6"), lines * 0.9)
        red = ((np.abs(cx - 0.75) < 0.012) | (np.abs(cy - 0.75) < 0.012)).astype(np.float32)
        alb = lerp(alb, hexcol("#b3262c"), red)
    elif variant == "gamchha":
        cx = np.mod(x, n / 6.0) / (n / 6.0)
        cy = np.mod(y, n / 6.0) / (n / 6.0)
        alb = fill(n, hexcol("#c0262d"))
        alb = lerp(alb, hexcol("#efe8da"), (((cx > 0.55) & (cx < 0.8)) | ((cy > 0.55) & (cy < 0.8))).astype(np.float32) * 0.85)
        alb = lerp(alb, hexcol("#1f6a3a"), ((np.abs(cx - 0.3) < 0.03) | (np.abs(cy - 0.3) < 0.03)).astype(np.float32))
    elif variant == "denim":
        twill = np.sin((x + y) * np.pi / pitch * 1.0) * 0.5 + 0.5
        alb = lerp(fill(n, hexcol("#1c2c4a")), fill(n, hexcol("#5a77a3")), (0.3 * twill + 0.7 * fine * 0.5).astype(np.float32))
        fadep = smoothstep(0.4, 0.8, folds)
        alb = lerp(alb, hexcol("#8aa1c4"), fadep * 0.35)
        weave = twill.astype(np.float32)
        rough = 0.92
    elif variant == "wool":
        alb = white * (0.94 + 0.06 * fine)[..., None]
        rough = 0.75
    else:
        alb = white
    alb = alb * (0.88 + 0.12 * weave)[..., None] * (0.86 + 0.2 * folds)[..., None] * (0.95 + 0.07 * wrinkle)[..., None]
    height = 0.4 * folds + 0.25 * wrinkle + 0.15 * weave + 0.05 * fine
    return {"albedo": np.clip(alb, 0, 1), "height": height, "roughness": rough - 0.05 * weave,
            "ao_extra": 0.88 + 0.12 * weave, "normal_strength": 7.0, "parallax": 0.0}


def mat_skin(n: int, seed: int) -> dict:
    """Neutral skin micro-detail (pores, fine lines, subsurface mottling). Near-white; each character
    tints it with albedo_color, so one texture serves every complexion."""
    fine = noise(n, seed + 1, 0.6, fmin=220)
    pores = smoothstep(0.7, 0.82, noise(n, seed + 2, 0.5, fmin=260))
    mottle = noise(n, seed + 3, 2.0, fmax=24)
    lines = smoothstep(0.62, 0.7, noise(n, seed + 4, 1.4, aniso=(5.0, 1.0), fmin=20, fmax=120))
    alb = fill(n, hexcol("#f4ece6")) * (0.94 + 0.08 * mottle)[..., None]
    alb = alb * np.array([1.0, 0.985, 0.98], np.float32) * (1.0 - 0.05 * pores)[..., None]
    height = 0.5 + 0.04 * fine - 0.12 * pores - 0.05 * lines
    return {"albedo": np.clip(alb, 0, 1), "height": height, "roughness": 0.55 + 0.1 * fine + 0.1 * pores,
            "ao_extra": 1.0, "normal_strength": 2.0, "parallax": 0.0}


def mat_paper(n: int, seed: int) -> dict:
    """Aged poster paper: wheat-paste wrinkles, torn-off older layers, tape and rain fade."""
    s = n / 1024.0
    x, y = grid(n)
    fib = noise(n, seed + 1, 0.9, fmin=160)
    wr = noise(n, seed + 2, 2.4, fmax=20)
    stain = smoothstep(0.55, 0.85, noise(n, seed + 3, 2.4, fmax=10))
    alb = fill(n, hexcol("#efe6cf")) * (0.92 + 0.1 * fib)[..., None]
    alb = lerp(alb, hexcol("#b9a676"), stain * 0.45)
    edge = np.minimum(np.minimum(x, n - x), np.minimum(y, n - y))
    burn = smoothstep(60.0 * s, 0.0, edge)
    alb = lerp(alb, hexcol("#8a7449"), burn * 0.5)
    height = 0.4 * wr + 0.1 * fib
    return {"albedo": np.clip(alb, 0, 1), "height": height, "roughness": 0.9 - 0.15 * stain,
            "ao_extra": 1.0, "normal_strength": 5.0, "parallax": 0.0}


MATERIALS = {
    "plaster_white": lambda n, sd: mat_plaster(n, sd + 900),
    "pavers_checker": lambda n, sd: mat_pavers(n, sd + 1000, "checker"),
    "pavers_footpath": lambda n, sd: mat_pavers(n, sd + 1100, "footpath"),
    "cloth_plain": lambda n, sd: mat_cloth(n, sd + 1200, "plain"),
    "cloth_check": lambda n, sd: mat_cloth(n, sd + 1300, "check"),
    "cloth_stripe": lambda n, sd: mat_cloth(n, sd + 1400, "stripe"),
    "cloth_print": lambda n, sd: mat_cloth(n, sd + 1500, "print"),
    "cloth_lungi": lambda n, sd: mat_cloth(n, sd + 1600, "lungi"),
    "cloth_gamchha": lambda n, sd: mat_cloth(n, sd + 1700, "gamchha"),
    "cloth_denim": lambda n, sd: mat_cloth(n, sd + 1800, "denim"),
    "cloth_wool": lambda n, sd: mat_cloth(n, sd + 1900, "wool"),
    "skin_detail": lambda n, sd: mat_skin(n, sd + 2000),
    "paper_aged": lambda n, sd: mat_paper(n, sd + 2100),
    "brick_weathered": lambda n, sd: mat_brick(n, sd),
    "asphalt_cracked": lambda n, sd: mat_asphalt(n, sd + 100),
    "tin_galvanized": lambda n, sd: mat_tin(n, sd + 200, None),
    "tin_painted_green": lambda n, sd: mat_tin(n, sd + 300, "#2f6b4f"),
    "concrete_mossy": lambda n, sd: mat_concrete(n, sd + 400),
    "awning_stripes_red": lambda n, sd: mat_fabric(n, sd + 500, "stripes_red"),
    "awning_stripes_blue": lambda n, sd: mat_fabric(n, sd + 600, "stripes_blue"),
    "awning_blockprint": lambda n, sd: mat_fabric(n, sd + 700, "blockprint"),
    "awning_tarp_blue": lambda n, sd: mat_fabric(n, sd + 800, "tarp_blue"),
}


# ============================================================================ output
def to8(a: np.ndarray) -> np.ndarray:
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def save_rgb(a: np.ndarray, path: str) -> None:
    Image.fromarray(to8(a), "RGB").save(path, optimize=True)


def save_gray(a: np.ndarray, path: str) -> None:
    Image.fromarray(to8(a), "L").save(path, optimize=True)


def save_gray16(a: np.ndarray, path: str) -> None:
    v = (np.clip(a, 0.0, 1.0) * 65535.0 + 0.5).astype(np.uint16)
    Image.fromarray(v).save(path)


def write_tres(path: str, name: str, res_dir: str, maps: dict, has_metal: bool, triplanar: bool) -> None:
    """triplanar=True  -> world-space triplanar, for procedural boxes (no parallax: Godot can't combine them).
    triplanar=False -> regular UV1 mapping with deep parallax from the height map, for modelled meshes."""
    use_height = (not triplanar) and maps.get("parallax", 0) > 0
    ids = [("alb", "albedo"), ("nrm", "normal"), ("rgh", "roughness"), ("ao", "ao")]
    if has_metal:
        ids.append(("met", "metallic"))
    if use_height:
        ids.append(("hgt", "height"))
    lines = [f'[gd_resource type="StandardMaterial3D" load_steps={len(ids) + 1} format=3]', ""]
    for i, (key, suffix) in enumerate(ids):
        lines.append(f'[ext_resource type="Texture2D" path="{res_dir}/{name}/{name}_{suffix}.png" id="{i + 1}_{key}"]')
    ref = {key: f'ExtResource("{i + 1}_{key}")' for i, (key, _) in enumerate(ids)}
    lines += ["", "[resource]", f'resource_name = "{name}{"" if triplanar else "_uv"}"', "texture_filter = 5",
              f"albedo_texture = {ref['alb']}"]
    if has_metal:
        lines += ["metallic = 1.0", f"metallic_texture = {ref['met']}"]
    lines += ["roughness = 1.0", f"roughness_texture = {ref['rgh']}",
              "normal_enabled = true", "normal_scale = 1.0", f"normal_texture = {ref['nrm']}",
              "ao_enabled = true", "ao_light_affect = 0.35", f"ao_texture = {ref['ao']}"]
    if use_height:
        lines += ["heightmap_enabled = true", f"heightmap_scale = {maps['parallax'] * 100.0:.2f}",
                  "heightmap_deep_parallax = true", "heightmap_min_layers = 8", "heightmap_max_layers = 32",
                  f"heightmap_texture = {ref['hgt']}"]
    if triplanar:
        lines += ["uv1_triplanar = true", "uv1_triplanar_sharpness = 4.0", "uv1_world_triplanar = true",
                  "uv1_scale = Vector3(0.5, 0.5, 0.5)"]
    lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def lit_preview(alb: np.ndarray, nrm: np.ndarray, rough: np.ndarray, ao: np.ndarray, metal: np.ndarray, size: int = 384) -> Image.Image:
    l = np.array([-0.55, 0.55, 0.63], np.float32)
    l /= np.linalg.norm(l)
    v = np.array([0.0, 0.0, 1.0], np.float32)
    hv = (l + v) / np.linalg.norm(l + v)
    ndl = np.clip((nrm * l).sum(-1), 0.0, 1.0)
    ndh = np.clip((nrm * hv).sum(-1), 0.0, 1.0)
    shin = 2.0 / np.maximum(rough ** 4, 1e-3)
    spec = ((1.0 - rough) ** 2) * np.power(ndh, np.clip(shin, 1, 512)) * (0.04 + 0.6 * metal)
    diffuse = alb * (1.0 - metal[..., None] * 0.6)
    col = diffuse * (0.18 * ao[..., None] + 0.95 * ndl[..., None]) + spec[..., None] * (lerp(np.ones(3, np.float32), alb, metal) if np.ndim(metal) else 1.0)
    col = col / (1.0 + col)
    col = np.power(np.clip(col * 1.6, 0, 1), 1.0)
    img = Image.fromarray(to8(col), "RGB").resize((size // 2, size // 2), Image.LANCZOS)
    tiled = Image.new("RGB", (size, size))
    for i in range(2):
        for j in range(2):
            tiled.paste(img, (i * size // 2, j * size // 2))
    return tiled


def generate(name: str, n: int, seed: int, out: str, res_dir: str) -> tuple:
    t0 = time.time()
    m = MATERIALS[name](n, seed)
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    s = n / 1024.0
    h = norm01(m["height"].astype(np.float32))
    alb = np.clip(m["albedo"], 0.0, 1.0)
    nrm = normal_from_height(h, m["normal_strength"] * s)
    ao = cavity_ao(h, s) * np.clip(np.broadcast_to(m.get("ao_extra", 1.0), h.shape), 0.0, 1.0)
    rough = np.clip(np.broadcast_to(m["roughness"], h.shape), 0.03, 1.0).astype(np.float32)
    has_metal = "metallic" in m
    metal = np.clip(np.broadcast_to(m.get("metallic", 0.0), h.shape), 0.0, 1.0).astype(np.float32)
    save_rgb(alb, os.path.join(d, f"{name}_albedo.png"))
    save_rgb(nrm * 0.5 + 0.5, os.path.join(d, f"{name}_normal.png"))
    save_gray(rough, os.path.join(d, f"{name}_roughness.png"))
    save_gray(ao, os.path.join(d, f"{name}_ao.png"))
    save_gray16(h, os.path.join(d, f"{name}_height.png"))
    if has_metal:
        save_gray(metal, os.path.join(d, f"{name}_metallic.png"))
    save_rgb(np.stack([ao, rough, metal], -1), os.path.join(d, f"{name}_orm.png"))
    write_tres(os.path.join(d, f"{name}.tres"), name, res_dir, m, has_metal, True)
    write_tres(os.path.join(d, f"{name}_uv.tres"), name, res_dir, m, has_metal, False)
    print(f"  {name:22s} {n}px  {time.time() - t0:5.1f}s")
    return alb, nrm, rough, ao, metal


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate seamless PBR texture sets for Godot 4.6.")
    ap.add_argument("--out", default="textures", help="output folder")
    ap.add_argument("--size", type=int, default=1024, help="texture size in px (512, 1024, 2048, 4096)")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--only", default="", help="comma-separated material names")
    ap.add_argument("--res-prefix", default="res://assets/textures", help="Godot path the --out folder maps to")
    ap.add_argument("--preview", action="store_true", help="write _preview.png contact sheet")
    a = ap.parse_args()
    names = [x.strip() for x in a.only.split(",") if x.strip()] or list(MATERIALS)
    for nme in names:
        if nme not in MATERIALS:
            raise SystemExit(f"unknown material {nme}; choose from {', '.join(MATERIALS)}")
    os.makedirs(a.out, exist_ok=True)
    print(f"Generating {len(names)} materials at {a.size}px into {a.out}")
    previews = []
    for nme in names:
        maps = generate(nme, a.size, a.seed, a.out, a.res_prefix)
        if a.preview:
            previews.append((nme, lit_preview(*maps)))
    if previews:
        cols = 3
        w = 384
        rows = (len(previews) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * w, rows * (w + 26)), (18, 16, 14))
        dr = ImageDraw.Draw(sheet)
        for i, (nme, im) in enumerate(previews):
            cx, cy = (i % cols) * w, (i // cols) * (w + 26)
            sheet.paste(im, (cx, cy + 26))
            dr.text((cx + 8, cy + 6), nme + "  (2x2 tiled, lit)", fill=(235, 200, 120))
        sheet.save(os.path.join(a.out, "_preview.png"))
        print("  preview ->", os.path.join(a.out, "_preview.png"))


if __name__ == "__main__":
    main()

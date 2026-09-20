#!/usr/bin/env python3
"""
Etubu App Store screenshot compositor.

Reads full-bleed iPhone captures from `raw/`, insets each into a realistic
device bezel, adds localized title/subtitle in the top negative space, and
writes Apple-compliant 24-bit PNG sets (Display P3, ≥72 DPI, no watermark).

Usage:
    python3 tools/appstore-screenshots/generate_screenshots.py
    python3 tools/appstore-screenshots/generate_screenshots.py --devices iphone69,ipadpro129
    python3 tools/appstore-screenshots/generate_screenshots.py --langs TR

Requires: Pillow (pip install Pillow)
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageCms

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

HERE = Path(__file__).resolve().parent
DEFAULT_RAW = HERE / "raw"
DEFAULT_OUT = HERE / "out"

# macOS system ICC + fonts. Fall back to Arial if Helvetica Neue is missing.
P3_ICC = Path("/System/Library/ColorSync/Profiles/Display P3.icc")
HELVETICA_NEUE = Path("/System/Library/Fonts/HelveticaNeue.ttc")
ARIAL_BOLD = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
ARIAL = Path("/System/Library/Fonts/Supplemental/Arial.ttf")

# Helvetica Neue .ttc face indices (macOS)
HN_BOLD = 1
HN_REGULAR = 0
HN_MEDIUM = 10

# ---------------------------------------------------------------------------
# Text (approved copy)
# ---------------------------------------------------------------------------

COPY: dict[str, list[tuple[str, str]]] = {
    "TR": [
        (
            "Aracınızın Yeni Gösterge Paneli",
            "Hız, güç, batarya ve menzil bilgilerini anlık olarak tek ekranda takip edin.",
        ),
        (
            "Tesla'ya Doğrudan Bağlantı",
            "Lastik basıncı, anlık tüketim ve iklim durumu gibi kritik araç verilerine anında erişin.",
        ),
        (
            "Yola ve Rotaya Hakim Olun",
            "Radar, hız koridoru, tünel ve viraj uyarılarıyla sürüş güvenliğinizi artırın.",
        ),
        (
            "Aracınızı Uzaktan Yönetin",
            "İklimlendirme, şarj başlatma ve kilit kontrolleri her an parmaklarınızın ucunda.",
        ),
        (
            "Odaklanmış Sürüş Deneyimi",
            "Dikkatinizi dağıtmayan, sade ve net HUD tasarımıyla sadece yola odaklanın.",
        ),
        (
            "Akıllı Rota Planlama",
            "Hedefinizi seçin; kalan mesafe, varış süresi ve hava durumu bilgilerini önceden görün.",
        ),
    ],
    "EN": [
        (
            "Your Vehicle's New Dashboard",
            "Monitor speed, power, battery, and range in real-time on a single screen.",
        ),
        (
            "Direct Connection to Your Tesla",
            "Instantly access critical vehicle data like tire pressure, live consumption, and climate status.",
        ),
        (
            "Master Your Route and the Road",
            "Enhance your driving safety with radar, speed zone, tunnel, and curve alerts.",
        ),
        (
            "Remote Vehicle Management",
            "Climate, charging, and lock controls are always right at your fingertips.",
        ),
        (
            "Focused Driving Experience",
            "Keep your eyes on the road with a clean, distraction-free HUD design.",
        ),
        (
            "Smart Route Planning",
            "Set your destination to foresee remaining distance, arrival time, and weather conditions.",
        ),
    ],
}

# Filename stem → 1-based slot. Order must match COPY lists above.
RAW_FILES = [
    "01-dashboard.png",
    "02-connection.png",
    "03-route-road.png",
    "04-remote.png",
    "05-hud.png",
    "06-planning.png",
]

# Soft ambient glow behind the device, sampled from each capture's theme.
SHOT_GLOW = [
    (0, 180, 200),    # 1 ice
    (232, 120, 32),   # 2 amber landscape
    (210, 110, 28),   # 3 amber
    (20, 160, 130),   # 4 remote teal
    (40, 150, 90),    # 5 forest HUD
    (30, 170, 160),   # 6 route teal
]

# ---------------------------------------------------------------------------
# Typography + layout knobs (tweak here)
# ---------------------------------------------------------------------------

TITLE_COLOR = (255, 255, 255)
SUBTITLE_COLOR = (198, 208, 216)
BG_COLOR = (5, 7, 10)

# Fractions of canvas width / height — independent of device pixel size.
TITLE_SIZE_FRAC = 0.048          # ~62 px on a 1290-wide canvas
SUBTITLE_SIZE_FRAC = 0.026       # ~34 px
TEXT_MAX_WIDTH_FRAC = 0.86
TEXT_TOP_FRAC = 0.048
TITLE_SUB_GAP_FRAC = 0.014
TEXT_DEVICE_GAP_FRAC = 0.028
BOTTOM_MARGIN_FRAC = 0.035
DEVICE_MAX_WIDTH_FRAC = 0.86     # portrait phone
LANDSCAPE_MAX_WIDTH_FRAC = 0.92


# ---------------------------------------------------------------------------
# Device slots (App Store Connect exact pixel sizes)
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DeviceSpec:
    """One App Store screenshot slot."""

    key: str
    folder: str
    # Portrait marketing canvas — Apple requires a single orientation per slot.
    canvas: tuple[int, int]
    kind: str  # "iphone" | "ipad"
    # Physical-looking bezel in *points* at the device's native 3x scale, then
    # scaled with the mockup. Values match iPhone 15/16 Pro Max / iPad Pro 12.9".
    bezel_pt: float = 12.0
    corner_pt: float = 55.0
    island: bool = True


DEVICES: dict[str, DeviceSpec] = {
    # Current required iPhone 6.9" slot (iPhone 16 Pro Max / 15 Pro Max 6.9").
    "iphone69": DeviceSpec(
        key="iphone69",
        folder="iPhone69",
        canvas=(1320, 2868),
        kind="iphone",
        bezel_pt=12.2,
        corner_pt=62.0,
        island=True,
    ),
    # iPhone 15 Pro Max 6.7" (1290×2796 portrait / 2796×1290 landscape).
    "iphone15promax": DeviceSpec(
        key="iphone15promax",
        folder="iPhone15ProMax",
        canvas=(1290, 2796),
        kind="iphone",
        bezel_pt=12.0,
        corner_pt=55.0,
        island=True,
    ),
    # iPad Pro 12.9" 6th gen. iPhone UI is shown in an iPhone frame on this canvas
    # (the app is iPhone-first; stretching to 4:3 would distort the HUD).
    "ipadpro129": DeviceSpec(
        key="ipadpro129",
        folder="iPadPro129",
        canvas=(2048, 2732),
        kind="ipad",
        bezel_pt=12.0,
        corner_pt=55.0,
        island=True,
    ),
}

# Titanium finishes (outer shell RGB).
DEVICE_COLORS: dict[str, tuple[int, int, int]] = {
    "black": (28, 28, 30),
    "natural": (176, 166, 149),
    "white": (228, 226, 222),
    "blue": (42, 56, 72),
}


# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------

def _font(size: int, *, bold: bool) -> ImageFont.FreeTypeFont:
    size = max(10, int(size))
    if HELVETICA_NEUE.is_file():
        idx = HN_BOLD if bold else HN_MEDIUM
        try:
            return ImageFont.truetype(str(HELVETICA_NEUE), size, index=idx)
        except OSError:
            return ImageFont.truetype(str(HELVETICA_NEUE), size, index=HN_REGULAR if not bold else HN_BOLD)
    path = ARIAL_BOLD if bold else ARIAL
    if path.is_file():
        return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


# ---------------------------------------------------------------------------
# Text layout
# ---------------------------------------------------------------------------

def _wrap(text: str, font: ImageFont.ImageFont, max_width: int) -> list[str]:
    words = text.split()
    if not words:
        return [""]
    dummy = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    lines: list[str] = []
    current = words[0]
    for word in words[1:]:
        trial = f"{current} {word}"
        if dummy.textlength(trial, font=font) <= max_width:
            current = trial
        else:
            lines.append(current)
            current = word
    lines.append(current)
    return lines


def render_text_block(
    title: str,
    subtitle: str,
    canvas_w: int,
    canvas_h: int,
) -> Image.Image:
    """Transparent RGBA strip with centered title + wrapped subtitle."""
    max_w = int(canvas_w * TEXT_MAX_WIDTH_FRAC)
    title_size = canvas_w * TITLE_SIZE_FRAC
    sub_size = canvas_w * SUBTITLE_SIZE_FRAC

    # Shrink until title fits in at most 2 lines and subtitle in 3.
    for _ in range(12):
        tf = _font(int(title_size), bold=True)
        sf = _font(int(sub_size), bold=False)
        t_lines = _wrap(title, tf, max_w)
        s_lines = _wrap(subtitle, sf, max_w)
        if len(t_lines) <= 2 and len(s_lines) <= 3:
            break
        title_size *= 0.94
        sub_size *= 0.94

    dummy = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    line_gap_t = int(title_size * 0.18)
    line_gap_s = int(sub_size * 0.28)
    gap = int(canvas_h * TITLE_SUB_GAP_FRAC)

    def block_h(lines: list[str], font: ImageFont.ImageFont, gap_y: int) -> int:
        h = 0
        for i, line in enumerate(lines):
            bbox = dummy.textbbox((0, 0), line, font=font)
            h += bbox[3] - bbox[1]
            if i < len(lines) - 1:
                h += gap_y
        return h

    th = block_h(t_lines, tf, line_gap_t)
    sh = block_h(s_lines, sf, line_gap_s)
    total_h = th + gap + sh + 8
    img = Image.new("RGBA", (canvas_w, total_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    y = 0
    for i, line in enumerate(t_lines):
        bbox = draw.textbbox((0, 0), line, font=tf)
        tw = bbox[2] - bbox[0]
        draw.text(((canvas_w - tw) / 2, y), line, font=tf, fill=TITLE_COLOR + (255,))
        y += (bbox[3] - bbox[1]) + (line_gap_t if i < len(t_lines) - 1 else 0)
    y += gap
    for i, line in enumerate(s_lines):
        bbox = draw.textbbox((0, 0), line, font=sf)
        tw = bbox[2] - bbox[0]
        draw.text(((canvas_w - tw) / 2, y), line, font=sf, fill=SUBTITLE_COLOR + (255,))
        y += (bbox[3] - bbox[1]) + (line_gap_s if i < len(s_lines) - 1 else 0)
    return img


# ---------------------------------------------------------------------------
# Device chrome
# ---------------------------------------------------------------------------

def _rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def _scale_cover(src: Image.Image, box: tuple[int, int]) -> Image.Image:
    bw, bh = box
    if bw < 1 or bh < 1:
        return src.resize((max(1, bw), max(1, bh)), Image.Resampling.LANCZOS)
    scale = max(bw / src.width, bh / src.height)
    nw, nh = max(1, int(src.width * scale)), max(1, int(src.height * scale))
    fitted = src.resize((nw, nh), Image.Resampling.LANCZOS)
    left = (nw - bw) // 2
    top = (nh - bh) // 2
    return fitted.crop((left, top, left + bw, top + bh))


def render_iphone(
    screenshot: Image.Image,
    spec: DeviceSpec,
    shell_rgb: tuple[int, int, int],
    target_long_edge: int,
) -> Image.Image:
    """
    Build a photorealistic iPhone Pro Max (or landscape) mockup.

    `target_long_edge` is the desired pixel length of the longer body side
    (height for portrait, width for landscape) so the phone fits the canvas.
    """
    src = screenshot.convert("RGB")
    landscape = src.width > src.height

    # Native 3x logical screen of a Pro Max-class phone.
    # Portrait 430×932 pt @3x = 1290×2796; 6.9" is 440×956 @3x = 1320×2868.
    if landscape:
        # Canvas is stored portrait; landscape screen is swapped.
        native_w, native_h = (max(spec.canvas), min(spec.canvas))
    else:
        native_w, native_h = spec.canvas if spec.canvas[0] < spec.canvas[1] else (spec.canvas[1], spec.canvas[0])

    # Scale factor from native 3x pixels → mockup pixels.
    # Body is screen + bezel on all sides.
    bezel_native = spec.bezel_pt * 3.0
    native_body_w = native_w + 2 * bezel_native
    native_body_h = native_h + 2 * bezel_native
    native_body_long = max(native_body_w, native_body_h)
    scale = target_long_edge / native_body_long

    bezel = max(8, int(round(bezel_native * scale)))
    screen_w = max(2, int(round(native_w * scale)))
    screen_h = max(2, int(round(native_h * scale)))
    body_w = screen_w + 2 * bezel
    body_h = screen_h + 2 * bezel
    outer_r = max(12, int(round(spec.corner_pt * 3.0 * scale)))
    inner_r = max(8, int(round((spec.corner_pt - spec.bezel_pt) * 3.0 * scale)))

    # Shadow padding around the body.
    pad = max(24, int(target_long_edge * 0.06))
    canvas = Image.new("RGBA", (body_w + pad * 2, body_h + pad * 2), (0, 0, 0, 0))

    # Drop shadow
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (pad + 6, pad + int(pad * 0.35), pad + body_w + 6, pad + body_h + int(pad * 0.45)),
        radius=outer_r,
        fill=(0, 0, 0, 170),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(8, pad // 3)))
    canvas = Image.alpha_composite(canvas, shadow)

    body = Image.new("RGBA", (body_w, body_h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)

    # Outer titanium shell with a faint top highlight.
    bd.rounded_rectangle((0, 0, body_w - 1, body_h - 1), radius=outer_r, fill=shell_rgb + (255,))
    highlight = tuple(min(255, c + 28) for c in shell_rgb)
    bd.rounded_rectangle((2, 2, body_w - 3, int(body_h * 0.08)), radius=outer_r, fill=highlight + (255,))
    # Re-fill most of the body so only a hairline highlight remains at the top.
    inset = Image.new("RGBA", (body_w, body_h), (0, 0, 0, 0))
    ImageDraw.Draw(inset).rounded_rectangle(
        (0, int(body_h * 0.035), body_w - 1, body_h - 1),
        radius=outer_r,
        fill=shell_rgb + (255,),
    )
    body = Image.alpha_composite(body, inset)
    bd = ImageDraw.Draw(body)

    # Inner black glass surround
    bd.rounded_rectangle(
        (bezel - 2, bezel - 2, bezel + screen_w + 1, bezel + screen_h + 1),
        radius=inner_r + 2,
        fill=(8, 8, 10, 255),
    )

    # Screen content, clipped to rounded rect.
    screen = _scale_cover(src, (screen_w, screen_h)).convert("RGBA")
    smask = _rounded_mask((screen_w, screen_h), inner_r)
    screen.putalpha(smask)
    body.paste(screen, (bezel, bezel), screen)

    # Dynamic Island hardware overlay (covers the screenshot's software island).
    if spec.island:
        if landscape:
            # Physical top of the phone is the LEFT edge of a landscape capture.
            short = screen_h
            i_len = max(24, int(short * 0.295))
            i_th = max(10, int(short * 0.086))
            ix = bezel + max(6, int(short * 0.026))
            iy = bezel + (screen_h - i_len) // 2
            ir = i_th // 2
            bd.rounded_rectangle((ix, iy, ix + i_th, iy + i_len), radius=ir, fill=(6, 6, 8, 255))
            cam = max(4, i_th // 3)
            cx = ix + (i_th - cam) // 2
            cy = iy + i_len - i_th // 2 - cam // 2
            bd.ellipse((cx, cy, cx + cam, cy + cam), fill=(20, 28, 40, 255))
        else:
            iw = max(24, int(screen_w * 0.295))
            ih = max(10, int(screen_w * 0.086))
            ix = bezel + (screen_w - iw) // 2
            iy = bezel + max(6, int(screen_w * 0.026))
            ir = ih // 2
            bd.rounded_rectangle((ix, iy, ix + iw, iy + ih), radius=ir, fill=(6, 6, 8, 255))
            cam = max(4, ih // 3)
            cx = ix + iw - ih // 2 - cam // 2
            cy = iy + (ih - cam) // 2
            bd.ellipse((cx, cy, cx + cam, cy + cam), fill=(20, 28, 40, 255))
            bd.ellipse(
                (ix + ih // 2 - cam // 3, cy + cam // 6, ix + ih // 2 + cam // 3, cy + cam - cam // 6),
                fill=(18, 18, 20, 255),
            )

    # Side buttons (volume left, power right) — skip on landscape; they look odd.
    if not landscape:
        btn = max(3, int(bezel * 0.38))
        # Silent / volume
        bd.rounded_rectangle((0, int(body_h * 0.14), btn, int(body_h * 0.18)), radius=btn // 2, fill=highlight + (255,))
        bd.rounded_rectangle((0, int(body_h * 0.21), btn, int(body_h * 0.30)), radius=btn // 2, fill=highlight + (255,))
        bd.rounded_rectangle((0, int(body_h * 0.32), btn, int(body_h * 0.41)), radius=btn // 2, fill=highlight + (255,))
        # Power
        bd.rounded_rectangle(
            (body_w - btn - 1, int(body_h * 0.24), body_w - 1, int(body_h * 0.38)),
            radius=btn // 2,
            fill=highlight + (255,),
        )

    canvas.paste(body, (pad, pad), body)
    return canvas


def _fit_device(device: Image.Image, max_w: int, max_h: int) -> Image.Image:
    scale = min(max_w / device.width, max_h / device.height, 1.0)
    # Always scale down to fit; never upscale chrome past the budget.
    if scale < 0.999:
        nw = max(1, int(device.width * scale))
        nh = max(1, int(device.height * scale))
        return device.resize((nw, nh), Image.Resampling.LANCZOS)
    return device


# ---------------------------------------------------------------------------
# Canvas + P3 export
# ---------------------------------------------------------------------------

def _glow_layer(size: tuple[int, int], rgb: tuple[int, int, int], cy: float) -> Image.Image:
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rw, rh = int(w * 0.75), int(h * 0.42)
    x0 = (w - rw) // 2
    y0 = int(h * cy) - rh // 2
    d.ellipse((x0, y0, x0 + rw, y0 + rh), fill=rgb + (70,))
    return layer.filter(ImageFilter.GaussianBlur(radius=max(20, w // 10)))


def compose_shot(
    screenshot: Image.Image,
    title: str,
    subtitle: str,
    spec: DeviceSpec,
    shell_rgb: tuple[int, int, int],
    glow_rgb: tuple[int, int, int],
) -> Image.Image:
    cw, ch = spec.canvas
    canvas = Image.new("RGBA", (cw, ch), BG_COLOR + (255,))
    canvas = Image.alpha_composite(canvas, _glow_layer((cw, ch), glow_rgb, cy=0.62))

    text = render_text_block(title, subtitle, cw, ch)
    text_top = int(ch * TEXT_TOP_FRAC)
    canvas.paste(text, (0, text_top), text)

    bottom = int(ch * BOTTOM_MARGIN_FRAC)
    gap = int(ch * TEXT_DEVICE_GAP_FRAC)
    avail_top = text_top + text.height + gap
    avail_h = ch - avail_top - bottom
    landscape = screenshot.width > screenshot.height
    max_w = int(cw * (LANDSCAPE_MAX_WIDTH_FRAC if landscape else DEVICE_MAX_WIDTH_FRAC))

    # Build chrome at a generous size then fit into the remaining box.
    target_long = int(avail_h if not landscape else max_w)
    phone = render_iphone(screenshot, spec, shell_rgb, target_long_edge=target_long)
    phone = _fit_device(phone, max_w, avail_h)

    px = (cw - phone.width) // 2
    py = avail_top + (avail_h - phone.height) // 2
    canvas.paste(phone, (px, py), phone)

    return canvas.convert("RGB")


def save_appstore_png(img: Image.Image, path: Path) -> None:
    """24-bit PNG, Display P3 ICC, 72 DPI, no alpha, no watermark."""
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb = img.convert("RGB")
    extra: dict = {"dpi": (72, 72)}
    if P3_ICC.is_file():
        try:
            profile = ImageCms.getOpenProfile(str(P3_ICC))
            extra["icc_profile"] = profile.tobytes()
        except Exception:
            pass
    rgb.save(path, format="PNG", optimize=True, **extra)


# ---------------------------------------------------------------------------
# Batch
# ---------------------------------------------------------------------------

def load_raw(raw_dir: Path) -> list[Image.Image]:
    shots: list[Image.Image] = []
    missing: list[str] = []
    for name in RAW_FILES:
        p = raw_dir / name
        if not p.is_file():
            missing.append(name)
            continue
        shots.append(Image.open(p).convert("RGB"))
    if missing:
        raise FileNotFoundError(
            f"Missing raw captures in {raw_dir}: {', '.join(missing)}"
        )
    if len(shots) != 6:
        raise ValueError("Expected 6 raw screenshots")
    return shots


def generate(
    raw_dir: Path,
    out_dir: Path,
    device_keys: Iterable[str],
    langs: Iterable[str],
    color: str,
) -> list[Path]:
    shots = load_raw(raw_dir)
    shell = DEVICE_COLORS[color]
    written: list[Path] = []
    for lang in langs:
        copy = COPY[lang]
        for dkey in device_keys:
            spec = DEVICES[dkey]
            dest = out_dir / lang / spec.folder
            for i, src in enumerate(shots):
                title, subtitle = copy[i]
                frame = compose_shot(src, title, subtitle, spec, shell, SHOT_GLOW[i])
                if frame.size != spec.canvas:
                    raise RuntimeError(f"Canvas mismatch: {frame.size} != {spec.canvas}")
                out = dest / f"{Path(RAW_FILES[i]).stem}.png"
                save_appstore_png(frame, out)
                written.append(out)
                print(f"  {out.relative_to(out_dir)}  {frame.size[0]}×{frame.size[1]}")
    return written


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate Etubu App Store screenshot sets.")
    p.add_argument("--raw", type=Path, default=DEFAULT_RAW, help="Directory of 01–06 PNG captures")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Output root")
    p.add_argument(
        "--devices",
        default="iphone69,iphone15promax,ipadpro129",
        help="Comma-separated keys: " + ", ".join(DEVICES),
    )
    p.add_argument("--langs", default="TR,EN", help="Comma-separated: TR,EN")
    p.add_argument(
        "--color",
        default="black",
        choices=sorted(DEVICE_COLORS),
        help="Device shell finish",
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    devices = [k.strip() for k in args.devices.split(",") if k.strip()]
    langs = [k.strip().upper() for k in args.langs.split(",") if k.strip()]
    for k in devices:
        if k not in DEVICES:
            print(f"Unknown device '{k}'. Choose from: {', '.join(DEVICES)}", file=sys.stderr)
            return 2
    for k in langs:
        if k not in COPY:
            print(f"Unknown language '{k}'. Choose from: {', '.join(COPY)}", file=sys.stderr)
            return 2
    print(f"Raw: {args.raw}")
    print(f"Out: {args.out}")
    print(f"Devices: {devices}  langs: {langs}  color: {args.color}")
    generate(args.raw, args.out, devices, langs, args.color)
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

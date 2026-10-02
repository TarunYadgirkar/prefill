#!/usr/bin/env python3
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO / "design" / "icon"))
import build  # noqa: E402

build.HERE = HERE
GENERATED = HERE.parent
K = "#000"


def rect(x0, y0, x1, y1, r):
    return f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" rx="{r}" fill="{K}"/>'


def pill(x0, y0, x1, y1):
    return rect(x0, y0, x1, y1, (y1 - y0) / 2)


def circle(cx, cy, r):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{K}"/>'


def bust(cx, head_cy, head_r, shoulder_w, shoulder_top, base):
    half = shoulder_w / 2
    return circle(cx, head_cy, head_r) + (
        f'<path d="M{cx - half} {base}V{shoulder_top + half * 0.55}'
        f'A{half} {half * 0.62} 0 0 1 {cx + half} {shoulder_top + half * 0.55}V{base}Z" fill="{K}"/>'
    )


def rot(deg, cx, cy, body):
    return f'<g transform="rotate({deg} {cx} {cy})">{body}</g>'


def lifted_card():
    green, ink = "#30D158", "#1C2228"
    return {
        "title": "1  Lifted Row",
        "background": (["#E4E8ED", "#AEB7C2"], ["#3A424C", "#14181C"]),
        "groups": [
            {"translucency": 0.15, "shadow": "neutral", "shadow_opacity": 0.85, "layers": [
                {"name": "lift-text", "glass": False, "fill": (("#FFFFFF", 0.96), ("#FFFFFF", 0.96)),
                 "svg": circle(204, 512, 34) + pill(268, 494, 700, 530)},
                {"name": "lift", "fill": (green, green), "svg": pill(104, 436, 920, 588)},
            ]},
            {"translucency": 0.35, "shadow": "neutral", "shadow_opacity": 0.35, "layers": [
                {"name": "card-text", "glass": False, "fill": ((ink, 0.55), ("#FFFFFF", 0.55)),
                 "svg": bust(300, 300, 46, 150, 352, 400) + pill(392, 280, 700, 314) + pill(392, 340, 600, 366)
                 + pill(240, 646, 760, 676) + pill(240, 716, 640, 746)},
                {"name": "card", "fill": (("#FFFFFF", 0.92), ("#C9D2DC", 0.32)), "svg": rect(176, 196, 848, 816, 92)},
            ]},
        ],
    }


def named_field():
    orange, navy = "#FF9F0A", "#0A2A52"
    return {
        "title": "2  Named Field",
        "background": (["#45A6FF", "#0062D6"], ["#0C3D78", "#03142B"]),
        "groups": [
            {"translucency": 0.1, "shadow": "neutral", "shadow_opacity": 0.6, "layers": [
                {"name": "caret", "fill": (orange, orange), "svg": rect(560, 376, 600, 648, 20)},
            ]},
            {"translucency": 0.1, "shadow": "neutral", "shadow_opacity": 0.4, "layers": [
                {"name": "person", "fill": (navy, ("#FFFFFF", 0.95)),
                 "svg": bust(356, 436, 72, 252, 540, 672)},
            ]},
            {"translucency": 0.3, "shadow": "neutral", "shadow_opacity": 0.5, "layers": [
                {"name": "ghost", "glass": False, "fill": ((navy, 0.22), ("#FFFFFF", 0.3)),
                 "svg": pill(640, 494, 836, 530)},
                {"name": "field", "fill": (("#FFFFFF", 0.95), ("#7FB3EE", 0.3)), "svg": rect(120, 352, 904, 672, 160)},
            ]},
        ],
    }


def fanned_stack():
    berry, ink = "#E3245C", "#3A0A1C"
    pivot = (300, 600)
    back = rect(220, 520, 800, 680, 80)
    return {
        "title": "3  Fanned Stack",
        "background": (["#FF4F7E", "#B8123F"], ["#6E0A28", "#22030C"]),
        "groups": [
            {"translucency": 0.1, "shadow": "neutral", "shadow_opacity": 0.85, "layers": [
                {"name": "front-text", "glass": False, "fill": ((berry, 1.0), (berry, 1.0)),
                 "svg": rot(-24, *pivot, circle(300, 600, 40) + pill(370, 582, 712, 618))},
                {"name": "front", "fill": ("#FFFFFF", ("#FFFFFF", 0.96)), "svg": rot(-24, *pivot, back)},
            ]},
            {"translucency": 0.5, "shadow": "neutral", "shadow_opacity": 0.3, "layers": [
                {"name": "mid", "fill": (("#FFFFFF", 0.7), ("#FFB3C7", 0.42)), "svg": rot(-10, *pivot, back)},
            ]},
            {"translucency": 0.6, "shadow": "neutral", "shadow_opacity": 0.2, "layers": [
                {"name": "back", "fill": (("#FFFFFF", 0.45), ("#FFB3C7", 0.26)), "svg": rot(4, *pivot, back)},
            ]},
        ],
    }


def index_tabs():
    ink, sun = "#1E2A36", "#FFC21A"
    return {
        "title": "4  Index Tab",
        "background": (["#FFE27A", "#FFB300"], ["#4A3608", "#1A1203"]),
        "groups": [
            {"translucency": 0.1, "shadow": "neutral", "shadow_opacity": 0.75, "layers": [
                {"name": "pulled", "fill": (ink, sun), "svg": rect(640, 236, 916, 380, 52)},
            ]},
            {"translucency": 0.3, "shadow": "neutral", "shadow_opacity": 0.4, "layers": [
                {"name": "card-text", "glass": False, "fill": ((ink, 0.8), ("#FFFFFF", 0.85)),
                 "svg": bust(420, 452, 92, 300, 574, 700) + pill(250, 748, 590, 782)},
                {"name": "card", "fill": (("#FFFFFF", 0.95), ("#E8D9AE", 0.3)), "svg": rect(170, 168, 734, 856, 92)},
            ]},
            {"translucency": 0.5, "shadow": "neutral", "shadow_opacity": 0.2, "layers": [
                {"name": "tabs", "fill": (("#FFFFFF", 0.85), ("#E8D9AE", 0.4)),
                 "svg": rect(640, 420, 820, 548, 48) + rect(640, 588, 820, 716, 48)},
            ]},
        ],
    }


DIRECTIONS = {
    "lifted-row": lifted_card(),
    "named-field": named_field(),
    "fanned-stack": fanned_stack(),
    "index-tab": index_tabs(),
}

SIZES = (512, 180, 60)
MODES = {"light": "Default", "dark": "Dark"}
LABEL = {"light": ("#F2F2F4", "#1D1D1F"), "dark": ("#0B0B0D", "#F5F5F7")}
WALL = {"light": ("#C9D6E3", "#F0E6DA"), "dark": ("#141A24", "#2A2230")}


def vertical_gradient(size, top, bottom):
    w, h = size
    a, b = Image.new("RGB", (1, 1), top).getpixel((0, 0)), Image.new("RGB", (1, 1), bottom).getpixel((0, 0))
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3)))
    return grad.resize((w, h))


def paste(canvas, icon, size, x, y):
    scaled = icon.resize((size, size), Image.LANCZOS)
    canvas.paste(scaled, (x, y), scaled)


def home_mock(renders):
    cell, icon_px, pad = 260, 180, 80
    cols = len(renders)
    sheet = Image.new("RGB", (pad * 2 + cell * cols, (pad * 2 + cell) * 2))
    for row, mode in enumerate(MODES):
        top = row * (pad * 2 + cell)
        band = vertical_gradient((sheet.width, pad * 2 + cell), *WALL[mode])
        sheet.paste(band, (0, top))
        draw = ImageDraw.Draw(sheet)
        for col, (key, paths) in enumerate(renders.items()):
            x = pad + col * cell + (cell - icon_px) // 2
            paste(sheet, Image.open(paths[mode]).convert("RGBA"), icon_px, x, top + pad)
            name = DIRECTIONS[key]["title"].split("  ")[1]
            draw.text((x + icon_px // 2, top + pad + icon_px + 22), name, anchor="mt",
                      fill=LABEL["dark" if mode == "dark" else "light"][1], font=build.font(30))
    out = GENERATED / "icon-v2-home.png"
    sheet.save(out)
    return out


def sheet(renders):
    pad, gap, label_h = 56, 36, 64
    col_w = sum(SIZES) + gap * (len(SIZES) - 1)
    width = pad * 2 + col_w * 2 + pad * 2
    row_h = pad * 2 + label_h + SIZES[0]
    out_img = Image.new("RGB", (width, row_h * len(renders)))
    draw = ImageDraw.Draw(out_img)
    for row, (key, paths) in enumerate(renders.items()):
        top = row * row_h
        for col, mode in enumerate(MODES):
            left = col * (width // 2)
            bg, fg = LABEL[mode]
            draw.rectangle((left, top, left + width // 2, top + row_h), fill=bg)
            draw.text((left + pad, top + pad), f"{DIRECTIONS[key]['title']}  ({mode})", fill=fg, font=build.font(40))
            icon = Image.open(paths[mode]).convert("RGBA")
            x = left + pad
            for size in SIZES:
                paste(out_img, icon, size, x, top + pad + label_h + SIZES[0] - size)
                x += size + gap
    out = GENERATED / "icon-v2-sheet.png"
    out_img.save(out)
    return out


def main():
    renders = {}
    for key, spec in DIRECTIONS.items():
        bundle = build.write_bundle(key, spec)
        renders[key] = {}
        for mode, rendition in MODES.items():
            out = GENERATED / f"icon-v2-{key}-{mode}.png"
            build.render(bundle, rendition, out)
            renders[key][mode] = out
            print(out)
    print(home_mock(renders))
    print(sheet(renders))


if __name__ == "__main__":
    main()

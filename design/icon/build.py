#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from directions import DIRECTIONS

HERE = Path(__file__).resolve().parent
GENERATED = HERE.parents[1] / "assets" / "generated"
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
RENDITIONS = {"light": "Default", "dark": "Dark"}
FINAL_RENDITIONS = {"light": "Default", "dark": "Dark", "tinted": "TintedDark", "clear": "ClearLight"}
SHEET_SIZES = (1024, 180, 60)
FINAL_SHEET_SIZES = (512, 180, 60)
FINAL_KEY = "a-slot"
HARBOR_HUE = "0.58"
REPO = HERE.parents[1]
APP_ICON = REPO / "App" / "AppIcon.icon"
EXTENSION_IMAGES = REPO / "Extension" / "Resources" / "images"
MANIFEST_SIZES = (48, 96, 128, 256, 512)
TOOLBAR_SIZES = (16, 19, 32, 38, 48, 72)


def color(hex_value: str, alpha: float = 1.0) -> str:
    r, g, b = (int(hex_value[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"


def fill(spec) -> dict:
    if isinstance(spec, tuple) and isinstance(spec[0], tuple):
        return {"linear-gradient": [color(*stop) for stop in spec]}
    if isinstance(spec, tuple):
        return {"solid": color(*spec)}
    if isinstance(spec, list):
        return {"linear-gradient": [color(stop) for stop in spec]}
    return {"solid": color(spec)}


def specialized(light, dark, tinted=None) -> list:
    out = [{"value": fill(light)}, {"appearance": "dark", "value": fill(dark)}]
    if tinted is not None:
        out.append({"appearance": "tinted", "value": fill(tinted)})
    return out


def svg(body: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>\n'


def layer_json(layer: dict) -> dict:
    out = {"image-name": f"{layer['name']}.svg", "name": layer["name"], "glass": layer.get("glass", True)}
    if "opacity" in layer:
        out["opacity"] = layer["opacity"]
    if "fill" in layer:
        out["fill-specializations"] = specialized(*layer["fill"])
    return out


def group_json(group: dict) -> dict:
    return {
        "layers": [layer_json(layer) for layer in group["layers"]],
        "shadow": {"kind": group.get("shadow", "layer-color"), "opacity": group.get("shadow_opacity", 0.5)},
        "translucency": {"enabled": True, "value": group.get("translucency", 0.4)},
        "specular": group.get("specular", True),
        "blur-material": group.get("blur", 0.3),
        "lighting": group.get("lighting", "individual"),
    }


def write_bundle(key: str, spec: dict) -> Path:
    bundle = HERE / f"{key}.icon"
    shutil.rmtree(bundle, ignore_errors=True)
    (bundle / "Assets").mkdir(parents=True)
    for group in spec["groups"]:
        for layer in group["layers"]:
            (bundle / "Assets" / f"{layer['name']}.svg").write_text(svg(layer["svg"]))
    doc = {
        "fill-specializations": specialized(*spec["background"]),
        "groups": [group_json(g) for g in spec["groups"]],
        "supported-platforms": {"squares": ["iOS"]},
    }
    (bundle / "icon.json").write_text(json.dumps(doc, indent=2) + "\n")
    return bundle


def render(bundle: Path, rendition: str, out: Path) -> None:
    tint = ["--tint-color", HARBOR_HUE, "--tint-strength", "0.75"] if rendition.startswith("Tinted") else []
    subprocess.run(
        [ICTOOL, str(bundle), "--export-image", "--output-file", str(out), "--platform", "iOS",
         "--rendition", rendition, "--width", "1024", "--height", "1024", "--scale", "1", *tint],
        check=True, capture_output=True,
    )


def font(size: int):
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def contact_sheet(renders: dict) -> Path:
    pad, gap = 64, 48
    col_w = sum(SHEET_SIZES) + gap * (len(SHEET_SIZES) - 1)
    width = pad * 2 + col_w * len(renders) + pad * (len(renders) - 1)
    band_h = 1024 + pad * 2 + 72
    sheet = Image.new("RGB", (width, band_h * 2), "#F2F2F4")
    sheet.paste(Image.new("RGB", (width, band_h), "#0B0B0D"), (0, band_h))
    draw = ImageDraw.Draw(sheet)
    for row, (mode, bg_text) in enumerate((("light", "#1D1D1F"), ("dark", "#F5F5F7"))):
        top = row * band_h + pad
        for col, (key, paths) in enumerate(renders.items()):
            left = pad + col * (col_w + pad)
            draw.text((left, top), f"{DIRECTIONS[key]['title']} ({mode})", fill=bg_text, font=font(40))
            x = left
            icon = Image.open(paths[mode]).convert("RGBA")
            for size in SHEET_SIZES:
                scaled = icon.resize((size, size), Image.LANCZOS)
                sheet.paste(scaled, (x, top + 72 + 1024 - size), scaled)
                x += size + gap
    out = GENERATED / "icon-contact-sheet.png"
    sheet.save(out)
    return out


def final_sheet(renders: dict) -> Path:
    pad, gap, label_h = 64, 40, 72
    col_w = sum(FINAL_SHEET_SIZES) + gap * (len(FINAL_SHEET_SIZES) - 1)
    band_w = col_w + pad * 2
    band_h = pad * 2 + label_h + FINAL_SHEET_SIZES[0]
    sheet = Image.new("RGB", (band_w * 2, band_h * 2), "#F2F2F4")
    draw = ImageDraw.Draw(sheet)
    for i, (mode, path) in enumerate(renders.items()):
        is_dark = mode in ("dark", "tinted")
        left = (i % 2) * band_w
        top = (i // 2) * band_h
        draw.rectangle((left, top, left + band_w, top + band_h), fill="#0B0B0D" if is_dark else "#F2F2F4")
        draw.text((left + pad, top + pad), mode.capitalize(), fill="#F5F5F7" if is_dark else "#1D1D1F", font=font(40))
        icon = Image.open(path).convert("RGBA")
        x = left + pad
        for size in FINAL_SHEET_SIZES:
            scaled = icon.resize((size, size), Image.LANCZOS)
            sheet.paste(scaled, (x, top + pad + label_h + FINAL_SHEET_SIZES[0] - size), scaled)
            x += size + gap
    out = GENERATED / "icon-final-sheet.png"
    sheet.save(out)
    return out


def toolbar_glyph(size: int) -> Image.Image:
    unit = size * 8 / 32
    glyph = Image.new("RGBA", (size * 8, size * 8), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glyph)

    def box(x0, y0, x1, y1):
        return [round(v * unit) for v in (x0, y0, x1, y1)]

    draw.rounded_rectangle(box(1, 12, 31, 26), radius=round(7 * unit), fill=(47, 124, 135, 255))
    draw.rounded_rectangle(box(20, 17.75, 28, 20.25), radius=round(1.25 * unit), fill=(255, 255, 255, 255))
    draw.rounded_rectangle(box(0.5, 4.5, 20.5, 19.5), radius=round(7.5 * unit), fill=(0, 0, 0, 0))
    draw.rounded_rectangle(box(2, 6, 19, 18), radius=round(6 * unit), fill=(255, 180, 58, 255))
    draw.rounded_rectangle(box(6, 10.75, 15, 13.25), radius=round(1.25 * unit), fill=(13, 42, 48, 255))
    return glyph.resize((size, size), Image.LANCZOS)


def export_extension_icons(light: Path) -> None:
    icon = Image.open(light).convert("RGBA")
    for size in MANIFEST_SIZES:
        icon.resize((size, size), Image.LANCZOS).save(EXTENSION_IMAGES / f"icon-{size}.png")
    for size in TOOLBAR_SIZES:
        toolbar_glyph(size).save(EXTENSION_IMAGES / f"toolbar-icon-{size}.png")


def build_final() -> None:
    bundle = write_bundle(FINAL_KEY, DIRECTIONS[FINAL_KEY])
    renders = {}
    for mode, rendition in FINAL_RENDITIONS.items():
        renders[mode] = GENERATED / f"icon-final-{mode}.png"
        render(bundle, rendition, renders[mode])
        print(renders[mode])
    print(final_sheet(renders))
    shutil.rmtree(APP_ICON, ignore_errors=True)
    shutil.copytree(bundle, APP_ICON)
    export_extension_icons(renders["light"])


def main() -> None:
    GENERATED.mkdir(parents=True, exist_ok=True)
    if sys.argv[1:] == ["final"]:
        build_final()
        return
    renders = {}
    for key, spec in DIRECTIONS.items():
        bundle = write_bundle(key, spec)
        renders[key] = {}
        for mode, rendition in RENDITIONS.items():
            out = GENERATED / f"icon-{key}-{mode}.png"
            render(bundle, rendition, out)
            renders[key][mode] = out
            print(out)
    print(contact_sheet(renders))


if __name__ == "__main__":
    main()

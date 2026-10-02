#!/usr/bin/env python3
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from directions import DIRECTIONS

HERE = Path(__file__).resolve().parent
GENERATED = HERE.parents[1] / "assets" / "generated"
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
RENDITIONS = {"light": "Default", "dark": "Dark"}
SHEET_SIZES = (1024, 180, 60)


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


def specialized(light, dark) -> list:
    return [{"value": fill(light)}, {"appearance": "dark", "value": fill(dark)}]


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
    subprocess.run(
        [ICTOOL, str(bundle), "--export-image", "--output-file", str(out), "--platform", "iOS",
         "--rendition", rendition, "--width", "1024", "--height", "1024", "--scale", "1"],
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


def main() -> None:
    GENERATED.mkdir(parents=True, exist_ok=True)
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

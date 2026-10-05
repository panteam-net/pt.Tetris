#!/usr/bin/env python3
"""Compose opaque, native-size App Store screenshots from captured UIKit screens."""

import argparse
import html
import json
import math
from functools import lru_cache
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image, ImageDraw, ImageFilter, ImageFont
from export_snapshots import export_snapshots

ROOT = Path(__file__).resolve().parents[1]
SIZES = {"iphone-6.5": (1284, 2778), "ipad": (2064, 2752), "iphone": (1320, 2868)}
DISPLAY_LABELS = {"iphone-6.5": "iPhone · 6.5-inch · 1284 × 2778",
                  "ipad": "iPad · 13-inch · 2064 × 2752",
                  "iphone": "iPhone · 6.9-inch · 1320 × 2868"}
COLORS = {"mint": (92, 232, 196), "amber": (255, 177, 105)}
WHITE = (233, 240, 246)
MUTED = (151, 170, 184)
FONT = Path("/System/Library/Fonts/SFNS.ttf")


@lru_cache(maxsize=96)
def font(size, weight="Regular"):
    if not FONT.exists():
        raise SystemExit("SFNS.ttf not found. Run on macOS, or pass --font with a font supporting English and Cyrillic.")
    result = ImageFont.truetype(str(FONT), int(size))
    try:
        result.set_variation_by_name(weight.encode())
    except (OSError, ValueError):
        pass  # --font may be a static font rather than the macOS variable font.
    return result


def fitted(texts, size, maximum, weight="Heavy"):
    while size >= 16:
        result = font(size, weight)
        if all(result.getlength(text) <= maximum for text in texts):
            return result
        size -= 1
    raise ValueError(f"Copy does not fit: {texts}")


def wrap(text, face, maximum):
    lines = [""]
    for word in text.split():
        trial = (lines[-1] + " " + word).strip()
        if face.getlength(trial) <= maximum:
            lines[-1] = trial
        else:
            if face.getlength(word) > maximum:
                raise ValueError(f"Word does not fit: {word}")
            lines.append(word)
    return lines


def background(size, accent, index):
    width, height = size
    # Render a smooth two-dimensional atmosphere at low resolution, then upscale.
    small = Image.new("RGB", (180, 360))
    pixels = small.load()
    for y in range(360):
        for x in range(180):
            gx, gy = x / 180, y / 360
            glow = math.exp(-((gx - 0.8) ** 2 / 0.32 + (gy - 0.5) ** 2 / 0.12))
            pixels[x, y] = tuple(int(base + tint * glow * 0.055 + (1 - gy) * 4)
                                 for base, tint in zip((7, 12, 19), accent))
    image = small.resize(size, Image.Resampling.BICUBIC).convert("RGBA")
    decoration = Image.new("RGBA", size)
    draw = ImageDraw.Draw(decoration)
    for x in range(-height, width + height, 120):
        draw.line([(x, height), (x + height * 0.65, height * 0.28)], fill=(*accent, 10), width=1)
    for y in range(int(height * 0.3), height, 120):
        draw.line([(0, y), (width, y)], fill=(*accent, 7), width=1)
    # Small geometric echoes of the app icon sit outside the screenshot frame.
    for x, y, length in [(-32, height * 0.58, 70), (width - 108, height * 0.77, 56)]:
        for cell_x, cell_y in [(0, 0), (1, 0), (1, 1), (2, 1)]:
            left = x + cell_x * (length + 8)
            top = y + cell_y * (length + 8)
            draw.rounded_rectangle((left, top, left + length, top + length), radius=10,
                                   outline=(*accent, 40), width=2)
    return Image.alpha_composite(image, decoration)


def frame(image, screen, x, y, width, radius):
    height = round(width * screen.height / screen.width)
    screen = screen.resize((width, height), Image.Resampling.LANCZOS)
    border = 10
    shadow = Image.new("RGBA", image.size)
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((x - 14, y + 20, x + width + 14, y + height + 48),
                                  radius=radius + border, fill=(0, 0, 0, 220))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(36)))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((x - border, y - border, x + width + border, y + height + border),
                           radius=radius + border, fill=(18, 27, 36), outline=(62, 77, 87), width=2)
    mask = Image.new("L", (width, height))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=255)
    image.paste(screen, (x, y), mask)
    return height


def compose(language, family, index, copy):
    size = SIZES[family]
    width, height = size
    is_phone = family.startswith("iphone")
    pad = 88 if is_phone else 116
    accent = COLORS[copy["accent"]]
    image = background(size, accent, index)
    draw = ImageDraw.Draw(image)
    logo_size = 24 if is_phone else 32
    for dx, dy, color in [(0, 0, COLORS["mint"]), (logo_size + 5, 0, COLORS["mint"]),
                          (logo_size + 5, logo_size + 5, COLORS["amber"])]:
        draw.rounded_rectangle((pad + dx, 78 + dy, pad + dx + logo_size, 78 + dy + logo_size),
                               radius=4, fill=color)
    draw.text((pad + logo_size * 2 + 26, 79), "pt.TetrisDuel", fill=WHITE,
              font=font(36 if is_phone else 44, "Semibold"), anchor="lt")
    label_font = fitted([copy["tag"]], 28 if is_phone else 34, width - pad * 2 - 44, "Semibold")
    draw.line((pad, 205, pad + 23, 205), fill=accent, width=5)
    draw.text((pad + 42, 190), copy["tag"], fill=accent, font=label_font, anchor="lt")

    headline = fitted(copy["headline"], 148 if is_phone else 174, width - pad * 2)
    title_top = 272 if is_phone else 263
    leading = round(headline.size * 1.12)
    for line, text in enumerate(copy["headline"]):
        draw.text((pad - 5, title_top + line * leading), text, fill=WHITE if line == 0 else accent,
                  font=headline, anchor="lt", stroke_width=0)
    body_font = font(43 if is_phone else 52)
    body_lines = wrap(copy["body"], body_font, width - pad * 2)
    if len(body_lines) > 2:
        raise ValueError(f"Too many body lines: {language}/{family}/{copy['scene']}")
    body_top = title_top + leading * 2 + 30
    for line, text in enumerate(body_lines):
        draw.text((pad, body_top + line * round(body_font.size * 1.3)), text,
                  fill=MUTED, font=body_font, anchor="lt")

    source = ROOT / "captures" / language / family / f"{copy['scene']}.png"
    screen = Image.open(source).convert("RGB")
    if screen.size != size:
        raise ValueError(f"Expected native {size} capture, got {screen.size}: {source}")
    screen_top = max(766 if is_phone else 806,
                     body_top + len(body_lines) * round(body_font.size * 1.3) + 62)
    screen_bottom = height - (139 if is_phone else 148)
    screen_width = round((screen_bottom - screen_top) * screen.width / screen.height)
    x = (width - screen_width) // 2
    frame_height = frame(image, screen, x, screen_top, screen_width, 72 if is_phone else 44)
    if screen_top + frame_height > screen_bottom + 2:
        raise ValueError("Screenshot frame overruns the footer")

    draw = ImageDraw.Draw(image)
    footer_font = fitted([copy["footer"]], 24 if is_phone else 32, width - pad * 2 - 92, "Medium")
    draw.text((pad, height - 69), copy["footer"], font=footer_font, fill=MUTED, anchor="lt")
    draw.text((width - pad, height - 69), f"0{index + 1}",
              font=font(26 if is_phone else 32, "Semibold"), fill=accent, anchor="rt")
    destination = ROOT / "screenshots" / language / family / f"{index + 1:02d}-{copy['scene']}.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(destination, optimize=True)
    print(f"Rendered {destination.relative_to(ROOT)} ({width} × {height})")
    return destination


def contact_sheet(language, family, paths):
    thumb_width = 280 if family.startswith("iphone") else 360
    thumb_height = round(thumb_width * SIZES[family][1] / SIZES[family][0])
    gap, margin = 24, 36
    image = Image.new("RGB", (margin * 2 + len(paths) * thumb_width + gap * (len(paths) - 1), thumb_height + 156), (11, 16, 24))
    draw = ImageDraw.Draw(image)
    label = DISPLAY_LABELS[family]
    draw.text((margin, 24), f"pt.TetrisDuel  /  {language.upper()}  /  {label}", font=font(27, "Semibold"), fill=WHITE)
    for index, path in enumerate(paths):
        x = margin + index * (thumb_width + gap)
        with Image.open(path) as screenshot:
            image.paste(screenshot.resize((thumb_width, thumb_height), Image.Resampling.LANCZOS), (x, 78))
        draw.text((x, thumb_height + 98), path.stem, font=font(20, "Medium"), fill=MUTED)
    directory = ROOT / "previews"
    directory.mkdir(exist_ok=True)
    image.save(directory / f"{language}-{family}.jpg", quality=93)


def preview_page(groups):
    sections = []
    for language, family, paths in groups:
        cards = "".join(f'<a href="{path.relative_to(ROOT)}" target="_blank"><img src="{path.relative_to(ROOT)}" '
                        f'alt="{html.escape(path.stem)}" loading="lazy"><span>{html.escape(path.stem)}</span></a>' for path in paths)
        sections.append(f'<section><h2>{language.upper()} / {DISPLAY_LABELS[family]}</h2><div class="gallery">{cards}</div></section>')
    content = """<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>pt.TetrisDuel — App Store assets</title>
<style>
body{margin:0;background:#0b1018;color:#e9f0f6;font:16px -apple-system,BlinkMacSystemFont,sans-serif;padding:48px}
h1{font-size:40px;letter-spacing:-1.5px;margin:0 0 12px}p{color:#97aab8;line-height:1.6}h2{font-size:20px;margin-top:48px;color:#5ce8c4}
.gallery{display:flex;gap:20px;overflow-x:auto;padding:12px 2px 24px}.gallery a{display:block;min-width:220px;width:260px;flex-shrink:0;text-decoration:none;color:#97aab8}
img{display:block;width:100%;height:auto;border-radius:12px;border:1px solid #293541}span{display:block;margin-top:14px}a{color:#5ce8c4}
</style><h1>pt.TetrisDuel</h1><p>Promotional App Store screenshots · English + Russian<br>
iPhone 6.5-inch: 1284 × 2778 · iPad 13-inch: 2064 × 2752<br>
5 designs per device and language. Select an image to open its full-resolution PNG.</p>
<p><a href="promotional-appstore.zip">Download promotional iPhone 6.5-inch + iPad screenshot pack</a></p>
<p><a href="metadata/en-US.json">English listing</a> · <a href="metadata/ru.json">Russian listing</a> · <a href="README.md">Upload and regeneration guide</a></p>
<p>Privacy policy: <a href="privacy/en.md">English</a> · <a href="privacy/ru.md">Русский</a></p>
<p>App support: <a href="support/en.md">English</a> · <a href="support/ru.md">Русский</a></p>
<p><a href="snapshots/README.md">Required-size app snapshots</a> · <a href="snapshots/appstore-snapshots.zip">Download snapshot ZIP</a></p>
""" + "".join(sections) + "</html>\n"
    (ROOT / "index.html").write_text(content)


def package_promotional_screenshots(entries):
    """Package exactly the user's iPhone 6.5-inch and iPad promotional sets."""
    folders = {"iphone-6.5": "iphone-6.5-1284x2778", "ipad": "ipad-13-2064x2752"}
    files = []
    archive_path = ROOT / "promotional-appstore.zip"
    with ZipFile(archive_path, "w", compression=ZIP_DEFLATED, compresslevel=6) as archive:
        archive.writestr("README.txt", "pt.TetrisDuel — promotional App Store screenshots\n\n"
                        "iPhone 6.5-inch display: 1284 x 2778 pixels (portrait).\n"
                        "iPad 13-inch display: 2064 x 2752 pixels (portrait).\n\n"
                        "en = English (U.S.); ru = Russian. Each device/language folder has five PNGs.\n"
                        "Select the matching localization and display slot in App Store Connect,\n"
                        "then upload the five images in filename order. All images are opaque RGB PNGs.\n")
        for entry in entries:
            if entry["device"] not in folders:
                continue
            path = ROOT / entry["file"]
            archive_name = f"{entry['language']}/{folders[entry['device']]}/{path.name}"
            archive.write(path, archive_name)
            files.append({"file": entry["file"], "archive_name": archive_name})
    print(f"Packaged {len(files)} promotional screenshots into promotional-appstore.zip")
    return {"file": str(archive_path.relative_to(ROOT)), "files": files}


def listing_document():
    version = json.loads((ROOT / "metadata/version.json").read_text())
    sections = ["# pt.TetrisDuel — App Store descriptions\n",
                "Listing text is generated from the JSON files in `metadata`.\n",
                f"**Copyright:** {version['copyright']}\n"]
    for locale, language in [("en-US", "English (U.S.)"), ("ru", "Russian / Русский")]:
        metadata = json.loads((ROOT / "metadata" / f"{locale}.json").read_text())
        sections.append(f"## {language}\n\n**Name:** {metadata['name']}\n\n"
                        f"**Subtitle:** {metadata['subtitle']}\n\n"
                        f"**Support URL:** {metadata['support_url']}\n\n"
                        f"### Promotional text\n\n{metadata['promotional_text']}\n\n"
                        f"### Keywords\n\n`{metadata['keywords']}`\n\n"
                        f"### Description\n\n{metadata['description']}\n")
    (ROOT / "DESCRIPTION.md").write_text("\n".join(sections))


def main():
    global FONT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, help="Optional replacement font with English and Cyrillic glyphs")
    args = parser.parse_args()
    if args.font:
        FONT = args.font
    copy = json.loads((ROOT / "screenshot-copy.json").read_text())
    groups, manifest = [], []
    for language, families in copy.items():
        for family in SIZES:
            designs = families["iphone" if family.startswith("iphone") else "ipad"]
            paths = [compose(language, family, index, design) for index, design in enumerate(designs)]
            contact_sheet(language, family, paths)
            groups.append((language, family, paths))
            manifest.extend({"file": str(path.relative_to(ROOT)), "language": language,
                             "device": family, "width": SIZES[family][0], "height": SIZES[family][1],
                             "mode": "RGB", "scene": design["scene"]}
                            for path, design in zip(paths, designs))
    icon = ROOT / "icon/app-icon-1024.png"
    icon.parent.mkdir(exist_ok=True)
    with Image.open(ROOT.parent / "TetrisDuel/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png") as source:
        source.convert("RGB").save(icon, optimize=True)
    export_snapshots()
    promotional_archive = package_promotional_screenshots(manifest)
    preview_page(groups)
    listing_document()
    (ROOT / "manifest.json").write_text(json.dumps({"screenshots": manifest,
                                                  "promotional_archive": promotional_archive,
                                                  "icon": str(icon.relative_to(ROOT))}, indent=2) + "\n")


if __name__ == "__main__":
    main()

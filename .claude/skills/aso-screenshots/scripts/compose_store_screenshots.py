#!/usr/bin/env python3
"""Composes App Store screenshots from raw simulator captures.

Generic copy (aso-screenshots skill). Run from the project root:
  python3 ~/.claude/skills/aso-screenshots/scripts/compose_store_screenshots.py
pages.json may override "font_dir", "font_prefix" (e.g. "Geist", "Inter")
and "themes" (same shape as THEMES below) to match the app's brand.

Reads marketing/screenshots/pages.json (one entry per product page: the
default page plus each custom product page) and writes store-ready PNGs:

  marketing/screenshots/out/<page>/6.9/01.png   1320x2868
  marketing/screenshots/out/<page>/6.7/01.png   1290x2796
  marketing/screenshots/out/<page>/preview.png  side-by-side contact sheet

Needs only Pillow. Fonts come from assets/fonts (Geist, the app's own font).
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path.cwd()
RAW = ROOT / "marketing/screenshots/raw"
OUT = ROOT / "marketing/screenshots/out"
FONTS = ROOT / "assets/fonts"

W, H = 1320, 2868  # 6.9" master; 6.7" is a resize (same aspect within 0.1%)
SIZES = {"6.9": (1320, 2868), "6.7": (1290, 2796)}

THEMES = {
    # Calm off-white with a soft green wash. Most frames.
    "light": {
        "bg": ("#FBFBFA", "#E3EEE6"),
        "head": "#2C3531",
        "sub": "#4F5A54",
        "chip_bg": "#4A7C59",
        "chip_fg": "#FFFFFF",
    },
    # Deep brand green. Frame 1 and moments that need weight.
    "brand": {
        "bg": ("#4A7C59", "#2F5A3D"),
        "head": "#FFFFFF",
        "sub": "#E9F1EB",
        "chip_bg": "#FFFFFF",
        "chip_fg": "#3D6A4B",
    },
    # Warm cream for the low-supply / refill story.
    "warm": {
        "bg": ("#FDF7EE", "#F6E7CF"),
        "head": "#2C3531",
        "sub": "#5E4A2A",
        "chip_bg": "#7A4E0E",
        "chip_fg": "#FFFFFF",
    },
}


FONT_PREFIX = "Geist"


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    path = FONTS / f"{FONT_PREFIX}-{weight}.ttf"
    if not path.exists():  # fall back to a macOS system font
        return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    return ImageFont.truetype(str(path), size)


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def gradient(top: str, bottom: str) -> Image.Image:
    a, b = hex_rgb(top), hex_rgb(bottom)
    col = Image.new("RGB", (1, H))
    for y in range(H):
        t = (y / (H - 1)) ** 1.4
        col.putpixel((0, y), tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3)))
    return col.resize((W, H))


def wrap(draw, text, fnt, max_w):
    lines = []
    for para in text.split("\n"):
        words, line = para.split(), ""
        for word in words:
            trial = f"{line} {word}".strip()
            if draw.textlength(trial, font=fnt) <= max_w:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def balanced(draw, text, fnt, max_w):
    """Wraps into the fewest lines, then evens them out so no word sits alone."""
    lines = wrap(draw, text, fnt, max_w)
    if len(lines) != 2 or "\n" in text:
        return lines
    words = text.split()
    best = None
    for i in range(1, len(words)):
        a, b = " ".join(words[:i]), " ".join(words[i:])
        wa, wb = draw.textlength(a, font=fnt), draw.textlength(b, font=fnt)
        if max(wa, wb) <= max_w and (best is None or max(wa, wb) < best[0]):
            best = (max(wa, wb), [a, b])
    return best[1] if best else lines


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *size), radius, fill=255)
    return mask


def device(shot: Image.Image, width: int) -> Image.Image:
    """Draws a modern iPhone around the capture: thin titanium-dark bezel."""
    bezel = round(width * 0.028)
    screen_w = width - 2 * bezel
    screen = shot.resize((screen_w, round(shot.height * screen_w / shot.width)), Image.LANCZOS)
    height = screen.height + 2 * bezel
    outer_r = round(width * 0.155)
    inner_r = outer_r - bezel

    frame = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, width - 1, height - 1), outer_r, fill="#1E2220")
    # Hairline highlight on the rim so it reads as metal, not a flat outline.
    d.rounded_rectangle((2, 2, width - 3, height - 3), outer_r - 2, outline="#5A605C", width=3)
    frame.paste(screen, (bezel, bezel), rounded_mask(screen.size, inner_r))
    return frame


def shadow(size, radius, blur, opacity):
    pad = blur * 3
    layer = Image.new("RGBA", (size[0] + 2 * pad, size[1] + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        (pad, pad, pad + size[0], pad + size[1]), radius, fill=(20, 40, 28, opacity)
    )
    return layer.filter(ImageFilter.GaussianBlur(blur)), pad


def chip(text, theme) -> Image.Image:
    fnt = font("SemiBold", 46)
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    tw = probe.textlength(text, font=fnt)
    w, h = round(tw + 120), 104
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, w - 1, h - 1), h // 2, fill=theme["chip_bg"])
    # Small check mark disc: the app's "done" language.
    cx, cy, r = 56, h // 2, 24
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=theme["chip_fg"])
    d.line([(cx - 11, cy + 1), (cx - 3, cy + 9), (cx + 12, cy - 8)], fill=theme["chip_bg"], width=6, joint="curve")
    d.text((94, h // 2), text, font=fnt, fill=theme["chip_fg"], anchor="lm")
    return img


def compose(frame: dict) -> Image.Image:
    theme = THEMES[frame.get("theme", "light")]
    canvas = gradient(*theme["bg"]).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    margin = 96

    # Headline: big, tight, two lines max.
    size = 124
    head_font = font("SemiBold", size)
    lines = balanced(d, frame["headline"], head_font, W - 2 * margin)
    while len(lines) > 2 and size > 92:
        size -= 6
        head_font = font("SemiBold", size)
        lines = balanced(d, frame["headline"], head_font, W - 2 * margin)
    y = 250
    for line in lines:
        d.text((W // 2, y), line, font=head_font, fill=theme["head"], anchor="mt")
        y += round(size * 1.08)

    sub_font = font("Regular", 54)
    y += 34
    for line in balanced(d, frame.get("subline", ""), sub_font, W - 2 * margin - 40):
        if line:
            d.text((W // 2, y), line, font=sub_font, fill=theme["sub"], anchor="mt")
            y += 70

    # Device bleeds off the bottom edge: reads larger and more premium than a
    # fully shown phone, and keeps the top of the UI (the story) in view.
    shot = Image.open(RAW / frame["shot"]).convert("RGB")
    phone_w = round(W * frame.get("scale", 0.80))
    phone = device(shot, phone_w)
    # Fixed position so the phones line up when the set is swiped.
    top = max(y + 70, 760)
    left = (W - phone_w) // 2
    blur_img, pad = shadow(phone.size, round(phone_w * 0.155), 48, 70)
    canvas.alpha_composite(blur_img, (left - pad, top - pad + 36))
    canvas.alpha_composite(phone, (left, top))

    if frame.get("pop"):
        card, cy = pop_card(frame["pop"], shot, phone, top)
        cx = (W - card.width) // 2
        blur_img, pad = shadow(card.size, 44, 40, 95)
        canvas.alpha_composite(blur_img, (cx - pad, cy - pad + 28))
        canvas.alpha_composite(card, (cx, cy))

    if frame.get("chip"):
        c = chip(frame["chip"], theme)
        cy = top + round(phone.height * frame.get("chip_y", 0.42))
        canvas.alpha_composite(shadow_chip(c), ((W - c.width) // 2 - 30, cy - 30 + 14))
        canvas.alpha_composite(c, ((W - c.width) // 2, cy))

    return canvas.convert("RGB")


def pop_card(pop: dict, shot: Image.Image, phone: Image.Image, top: int):
    """Lifts one region of the UI out of the phone, larger, so the proof
    reads at search-result thumbnail size. Returns the card and its y."""
    source = Image.open(RAW / pop["from"]).convert("RGB") if pop.get("from") else shot
    x0, y0, x1, y1 = pop["box"]
    region = source.crop((x0, y0, x1, y1))
    width = round(W * pop.get("width", 0.92))
    region = region.resize((width, round(region.height * width / region.width)), Image.LANCZOS)
    card = Image.new("RGBA", region.size, (0, 0, 0, 0))
    card.paste(region, (0, 0), rounded_mask(region.size, 44))
    ImageDraw.Draw(card).rounded_rectangle(
        (0, 0, card.width - 1, card.height - 1), 44, outline="#E4E5E1", width=3
    )
    # Default: float where the region sits on the phone, so it "lifts out".
    at = pop.get("at", (y0 + y1) / 2 / source.height)
    cy = top + round(phone.height * at) - card.height // 2
    return card, min(max(cy, top + 40), H - card.height - 90)


def shadow_chip(c: Image.Image) -> Image.Image:
    layer = Image.new("RGBA", (c.width + 60, c.height + 60), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        (30, 30, 30 + c.width, 30 + c.height), c.height // 2, fill=(20, 40, 28, 90)
    )
    return layer.filter(ImageFilter.GaussianBlur(18))


def contact_sheet(images, path):
    thumb_w = 440
    thumbs = [im.resize((thumb_w, round(im.height * thumb_w / im.width)), Image.LANCZOS) for im in images]
    gap = 40
    sheet = Image.new("RGB", (len(thumbs) * (thumb_w + gap) + gap, thumbs[0].height + 2 * gap), "#ECEDEA")
    for i, t in enumerate(thumbs):
        sheet.paste(t, (gap + i * (thumb_w + gap), gap))
    sheet.save(path, optimize=True)


def main():
    global FONTS, FONT_PREFIX
    pages = json.loads((ROOT / "marketing/screenshots/pages.json").read_text())
    FONTS = ROOT / pages.get("font_dir", "assets/fonts")
    FONT_PREFIX = pages.get("font_prefix", FONT_PREFIX)
    THEMES.update(pages.get("themes", {}))
    for page in pages["pages"]:
        rendered = []
        for i, frame in enumerate(page["frames"], 1):
            img = compose(frame)
            rendered.append(img)
            for label, size in SIZES.items():
                folder = OUT / page["id"] / label
                folder.mkdir(parents=True, exist_ok=True)
                out = img if size == (W, H) else img.resize(size, Image.LANCZOS)
                out.save(folder / f"{i:02d}.png", optimize=True)
        contact_sheet(rendered, OUT / page["id"] / "preview.png")
        print(f"{page['id']}: {len(rendered)} frames")


if __name__ == "__main__":
    main()

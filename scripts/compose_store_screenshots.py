#!/usr/bin/env python3
"""Composes Gave It App Store screenshots from raw simulator captures.

Reads marketing/screenshots/gaveit.json and writes store-ready PNGs:

  marketing/screenshots/out/<page>/6.9/01.png   1320x2868
  marketing/screenshots/out/<page>/6.7/01.png   1290x2796
  marketing/screenshots/out/<page>/preview.png  contact sheet

The look is the app's ledger, not the category's: ruled paper, a mono entry
stamp, left-aligned display type and the real screen as a flat clipped page.
No device mockups, gradients, glows or mascots. Needs only Pillow; fonts come
from assets/fonts (the app's own).
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "marketing/screenshots/gaveit.json"
OUT = ROOT / "marketing/screenshots/out"
FONTS = ROOT / "assets/fonts"

W, H = 1320, 2868  # 6.9" master; 6.7" is a resize (same aspect within 0.1%)
SIZES = {"6.9": (1320, 2868), "6.7": (1290, 2796)}
K = 1.0  # type and spacing scale; the iPad canvas is wider

# iPad 13" (2064x2752) renders from its own captures at a larger scale.
IPAD = {"size": (2064, 2752), "k": 1.45}

PAPER = "#F5F1E8"
RULE = "#ECE5D7"  # texture, not stripes
MARGIN_RULE = "#D9D2C3"
INK = "#1A1C24"
MUTED = "#5E5A52"
BRAND = "#2638C4"
EDGE = "#D9D2C3"
STAMP_BG = "#FBEBCF"
STAMP_LINE = "#F2B04C"
STAMP_INK = "#7A4A00"

LEFT = 150  # text starts right of the margin rule (scaled by K)
RULE_GAP = 88


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"{name}.ttf"), size)


def wrap(draw, text, fnt, max_w):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=fnt) <= max_w or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def k(value: float) -> int:
    return round(value * K)


def paper() -> Image.Image:
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    for y in range(k(RULE_GAP), H, k(RULE_GAP)):
        d.line([(0, y), (W, y)], fill=RULE, width=2)
    d.line([(k(LEFT) - 40, 0), (k(LEFT) - 40, H)], fill=MARGIN_RULE, width=3)
    return img.convert("RGBA")


def without_status_bar(shot: Image.Image) -> Image.Image:
    """Drops the system status bar (time, signal, battery): the page starts
    at the app's own content, like a clipped entry, not a phone."""
    phone = shot.height / shot.width > 1.6
    bar = round(shot.height * (0.052 if phone else 0.026))
    return shot.crop((0, bar, shot.width, shot.height))


def content_column(shot: Image.Image) -> Image.Image:
    """iPad: keep the app's centred content column (measured x 400-1784 of
    2064) so the UI shows at a readable size. Phones are already one column."""
    if shot.height / shot.width > 1.6:
        return shot
    return shot.crop((round(shot.width * 0.18), 0, round(shot.width * 0.875), shot.height))


def below_stamp(shot: Image.Image) -> Image.Image:
    """Crops a guard screen just below the app's own amber stamp, so the
    frame's big stamp is the only one. Falls back to the whole screen."""
    small = shot.resize((shot.width // 4, shot.height // 4))
    last = None
    for y in range(small.height // 3, small.height):
        for x in range(small.width // 5, small.width * 4 // 5, 2):
            r, g, b = small.getpixel((x, y))[:3]
            if abs(r - 242) < 20 and abs(g - 176) < 25 and b < 110:
                last = y
                break
    if last is None:
        return shot
    sheet = shot.crop((0, (last + 8) * 4, shot.width, shot.height))
    return trim_dim_edges(sheet)


def trim_dim_edges(shot: Image.Image) -> Image.Image:
    """Cuts the dimmed backdrop beside a sheet (wide iPad layouts)."""
    gray = shot.convert("L").resize((shot.width // 4, 40))
    def light(x):
        return sum(gray.getpixel((x, y)) for y in range(40)) / 40 > 170
    cols = [x for x in range(gray.width) if light(x)]
    if not cols:
        return shot
    return shot.crop((cols[0] * 4, 0, (cols[-1] + 1) * 4, shot.height))


def stamp(who_time: str, scale: float = 1.0) -> Image.Image:
    """The ALREADY GIVEN stamp, drawn like the app's GivenStamp."""
    top = font("AtkinsonHyperlegibleNext-Bold", round(44 * scale))
    mono = font("AtkinsonHyperlegibleMono-Medium", round(50 * scale))
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    w = round(max(probe.textlength("ALREADY GIVEN", font=top) + 14 * 12 * scale / 4,
                  probe.textlength(who_time, font=mono)) + 90 * scale)
    h = round(190 * scale)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((3, 3, w - 4, h - 4), round(12 * scale), fill=STAMP_BG,
                        outline=STAMP_LINE, width=round(7 * scale))
    # Letter-spaced label, like the in-app stamp.
    x = (w - (probe.textlength("ALREADY GIVEN", font=top) + 12 * 12 * scale / 4)) / 2
    for ch in "ALREADY GIVEN":
        d.text((x, round(40 * scale)), ch, font=top, fill=STAMP_INK)
        x += probe.textlength(ch, font=top) + 3 * scale
    d.text((w / 2, round(118 * scale)), who_time, font=mono, fill=STAMP_INK, anchor="mt")
    return img.rotate(4, resample=Image.BICUBIC, expand=True)


def clipped_page(shot: Image.Image, width: int) -> Image.Image:
    """The real screen as a page clipped into the log: flat, hairline edge,
    and a hard offset edge instead of a soft shadow."""
    screen = shot.resize((width, round(shot.height * width / shot.width)), Image.LANCZOS)
    radius = k(40)
    offset = k(14)
    out = Image.new("RGBA", (width + offset, screen.height + offset), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((offset, offset, width + offset - 1, screen.height + offset - 1),
                        radius, fill=EDGE)
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *screen.size), radius, fill=255)
    out.paste(screen, (0, 0), mask)
    d.rounded_rectangle((0, 0, width - 1, screen.height - 1), radius, outline=EDGE, width=4)
    return out


def compose(frame: dict, raw_dir: Path) -> Image.Image:
    canvas = paper()
    d = ImageDraw.Draw(canvas)
    left = k(LEFT)
    max_w = W - left - k(110)

    # The entry stamp: time and who, the way a log line reads.
    y = 2 * k(RULE_GAP) + k(40)
    mono = font("AtkinsonHyperlegibleMono-Medium", k(46))
    d.text((left, y), frame["entry"], font=mono, fill=BRAND)
    if frame.get("pro"):
        # Paid features say so on the frame (App Review Guideline 2.3.2).
        x = left + d.textlength(frame["entry"], font=mono) + k(30)
        tag = font("AtkinsonHyperlegibleNext-Bold", k(34))
        tw = d.textlength("PRO", font=tag)
        d.rounded_rectangle((x, y - k(4), x + tw + k(32), y + k(52)), k(8), outline=BRAND, width=3)
        d.text((x + k(16), y + k(24)), "PRO", font=tag, fill=BRAND, anchor="lm")
    y += k(100)

    size = k(132)
    head = font("BricolageGrotesque-Bold", size)
    lines = wrap(d, frame["headline"], head, max_w)
    while len(lines) > 3 and size > k(100):
        size -= 6
        head = font("BricolageGrotesque-Bold", size)
        lines = wrap(d, frame["headline"], head, max_w)
    for line in lines:
        d.text((left, y), line, font=head, fill=INK)
        y += round(size * 1.04)

    y += k(44)
    sub = font("AtkinsonHyperlegibleNext-Regular", k(54))
    for line in wrap(d, frame.get("subline", ""), sub, max_w):
        d.text((left, y), line, font=sub, fill=MUTED)
        y += k(74)

    shot = Image.open(raw_dir / frame["shot"]).convert("RGB")
    if frame.get("stamp"):
        shot = below_stamp(shot)
    else:
        shot = without_status_bar(shot)
    if not frame.get("stamp"):
        shot = content_column(shot)
    page_w = W - left - 40
    page = clipped_page(shot, page_w)
    top = max(y + k(80), k(940))

    if frame.get("stamp"):
        # The stamp gets its own space: it never covers the screen's text.
        s = stamp(frame["entry"], 1.6 * K)
        canvas.alpha_composite(s, ((W - s.width) // 2 + k(30), top))
        top += s.height + k(60)

    canvas.alpha_composite(page, (left - 30, top))

    return canvas.convert("RGB")


def contact_sheet(images, path):
    thumb_w = 440
    thumbs = [im.resize((thumb_w, round(im.height * thumb_w / im.width)), Image.LANCZOS)
              for im in images]
    gap = 40
    sheet = Image.new("RGB", (len(thumbs) * (thumb_w + gap) + gap,
                              thumbs[0].height + 2 * gap), "#E9E4D8")
    for i, t in enumerate(thumbs):
        sheet.paste(t, (gap + i * (thumb_w + gap), gap))
    sheet.save(path, optimize=True)


def render_ipad(config):
    """iPad 13" set from its own captures; skipped until they exist."""
    global W, H, K
    raw_dir = ROOT / config.get("raw_ipad", "")
    if not config.get("raw_ipad") or not raw_dir.exists():
        return
    missing = sorted({
        f["shot"] for page in config["pages"] for f in page["frames"]
        if not (raw_dir / f["shot"]).exists()
    })
    if missing:
        print(f"iPad skipped, captures missing: {', '.join(missing)}")
        return
    saved = (W, H, K)
    (W, H), K = IPAD["size"], IPAD["k"]
    try:
        for page in config["pages"]:
            rendered = []
            for i, frame in enumerate(page["frames"], 1):
                img = compose(frame, raw_dir)
                rendered.append(img)
                folder = OUT / page["id"] / "ipad-13"
                folder.mkdir(parents=True, exist_ok=True)
                img.save(folder / f"{i:02d}.png", optimize=True)
            contact_sheet(rendered, OUT / page["id"] / "preview-ipad.png")
            print(f"{page['id']}: {len(rendered)} iPad frames")
    finally:
        W, H, K = saved


def main():
    config = json.loads(CONFIG.read_text())
    raw_dir = ROOT / config["raw"]
    for page in config["pages"]:
        rendered = []
        for i, frame in enumerate(page["frames"], 1):
            img = compose(frame, raw_dir)
            rendered.append(img)
            for label, size in SIZES.items():
                folder = OUT / page["id"] / label
                folder.mkdir(parents=True, exist_ok=True)
                out = img if size == (W, H) else img.resize(size, Image.LANCZOS)
                out.save(folder / f"{i:02d}.png", optimize=True)
        contact_sheet(rendered, OUT / page["id"] / "preview.png")
        print(f"{page['id']}: {len(rendered)} frames")
    render_ipad(config)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Verify the PDF carries no text a reader cannot see.

Author: Patrik Goldschmidt
Date: 2026-10-29

Hidden text is how keyword stuffing is done -- white words on a white page,
2pt type, text pushed off the page or stacked under other text -- and screening
tools that look for it flag the whole document, not just the words. The class
puts invisible glyphs into the PDF on purpose, but only whitespace: tagging
turns every word gap into a real U+0020, the header carries U+00A0s, and the
entry separator gets tagpdf's \\pdffakespace on each side, all zero-width or
offset so nothing moves. This check keeps it that way: whitespace may be
invisible, nothing else may.

What it fails on, for any character that is not whitespace:

  * render mode 3 (invisible) -- text drawn without ink
  * a colour too close to the white page: contrast with white under MIN_CONTRAST
  * opacity under MIN_OPACITY
  * a size under MIN_SIZE points
  * an origin outside the page
  * a glyph covering more than MAX_OVERLAP of another visible glyph -- text
    stacked on text
  * a glyph inside the visible area of an image -- text behind a picture

Whitespace is counted and reported, never failed. Not covered: text hidden by
a clipping path, or under a vector shape filled after it; the class draws
neither over text. An image's visible area is its clip's bounding box, so text
in the corners of a clipped circle would count as hidden.

Needs PyMuPDF; without it the check reports SKIP. run.sh calls it as

    hidden-text-check.py PDF
"""

import sys

# Thresholds. The class's faintest text is the light grey of the date leader's
# dots, 1.51:1 against white, and its smallest is 8pt; each limit sits clearly
# below that while still catching a real hiding trick (white is 1:1).
MIN_CONTRAST = 1.25  # WCAG contrast ratio against a white page
MIN_OPACITY = 0.25
MIN_SIZE = 4.0       # points
MAX_OVERLAP = 0.5    # share of the smaller glyph's box
INVISIBLE = 3        # PyMuPDF texttrace `type' for render mode 3


def to_rgb(color):
    """A texttrace colour (Gray, RGB or CMYK components, 0-1) as RGB."""
    if not color:
        return (0.0, 0.0, 0.0)

    if len(color) == 1:
        return (color[0],) * 3

    if len(color) == 4:
        c, m, y, k = color
        return tuple((1 - v) * (1 - k) for v in (c, m, y))

    return tuple(color[:3])


def contrast_with_white(rgb):
    """The WCAG 2 contrast ratio of a colour against white."""
    def channel(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(v) for v in rgb)
    luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

    return 1.05 / (luminance + 0.05)


def image_areas(page, pymupdf):
    """The visible area of each image on the page, as rectangles.

    An image is reported at its full placement, but a clip can show only part
    of it -- the header photo is a rectangle clipped to a circle, and in
    `twocolumn' a heading sits under the hidden part. Each image is cut to the
    smallest clip that lies mostly on it; the clip's bounding box is as close
    as PyMuPDF gets, so a circle counts as its square.
    """
    clips = [pymupdf.Rect(d["scissor"])
             for d in page.get_drawings(extended=True) if d["type"] == "clip"]
    areas = []

    for info in page.get_image_info():
        img = pymupdf.Rect(info["bbox"])
        own = [c for c in clips
               if not c.is_empty
               and (c & img).get_area() >= 0.5 * c.get_area()]

        if own:
            img &= min(own, key=lambda c: c.get_area())

        areas.append(img)

    return areas


def stacked(glyphs):
    """[(a, b)] for visible glyphs covering more than MAX_OVERLAP of another.

    A sweep over the glyphs sorted by top edge: only boxes whose vertical
    ranges meet can overlap, so each glyph is compared with the few after it.
    """
    glyphs = sorted(glyphs, key=lambda g: g[1].y0)
    found = []

    for i, (c, r) in enumerate(glyphs):
        for c2, r2 in glyphs[i + 1:]:
            if r2.y0 >= r.y1:
                break

            inter = r & r2

            if inter.is_empty:
                continue

            smaller = min(r.width * r.height, r2.width * r2.height)

            if smaller > 0 and inter.width * inter.height / smaller > MAX_OVERLAP:
                found.append((c, c2))

    return found


def main(path):
    print(f"hidden-text-check.py: {path}\n")

    try:
        import pymupdf
    except ImportError:
        print("SKIP: needs pymupdf -- run tests/setup.sh")
        return 0

    total = whitespace = 0
    found = {key: [] for key in ("invisible", "faint", "transparent", "tiny",
                                 "off-page", "stacked", "under an image")}
    faintest = None

    with pymupdf.open(path) as doc:
        for pno, page in enumerate(doc, 1):
            area = page.rect
            images = image_areas(page, pymupdf)
            visible = []

            for span in page.get_texttrace():
                rgb = to_rgb(span["color"])

                for ch in span["chars"]:
                    total += 1
                    c = chr(ch[0])

                    if not c.strip():
                        whitespace += 1
                        continue

                    where = f"p{pno} {c!r}"
                    box = pymupdf.Rect(ch[3])

                    if span["type"] == INVISIBLE:
                        found["invisible"].append(where)
                        continue

                    ratio = contrast_with_white(rgb)
                    faintest = ratio if faintest is None else min(faintest, ratio)

                    if ratio < MIN_CONTRAST:
                        found["faint"].append(where)
                    if span["opacity"] < MIN_OPACITY:
                        found["transparent"].append(where)
                    if span["size"] < MIN_SIZE:
                        found["tiny"].append(f"{where} {span['size']:.1f}pt")
                    if not area.contains(pymupdf.Point(ch[2])):
                        found["off-page"].append(where)
                    if any(img.contains(box) for img in images if not box.is_empty):
                        found["under an image"].append(where)

                    visible.append((c, box))

            found["stacked"] += [f"p{pno} {a!r} on {b!r}"
                                 for a, b in stacked(visible)]

    print(f"  characters             {total}, {whitespace} of them whitespace "
          f"(allowed to be invisible)")

    if faintest is not None:
        print(f"  faintest text          {faintest:.2f}:1 against white "
              f"(limit {MIN_CONTRAST}:1)")

    for key, hits in found.items():
        shown = ", ".join(hits[:6]) + (" ..." if len(hits) > 6 else "")
        print(f"  {key:<22} {len(hits) if hits else 'none'}"
              f"{'  ' + shown if hits else ''}")

    failed = [key for key, hits in found.items() if hits]

    if failed:
        print(f"\nFAIL: text a reader cannot see: {', '.join(failed)}.")
        print("\n      Screening tools read hidden text as keyword stuffing and\n"
              "      flag the whole document. Only whitespace may be invisible;\n"
              "      find what put the characters above there.")
        return 1

    print("\nPASS: every non-whitespace character is visible on the page.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

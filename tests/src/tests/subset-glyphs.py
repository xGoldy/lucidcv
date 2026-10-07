#!/usr/bin/env python3
"""Verify the PDF carries real space characters between words.

Author: Patrik Goldschmidt
Date: 2026-08-22, last rev. 2026-10-04

This is the check that the whole LuaLaTeX migration exists for. TeX turns an
interword space into glue, and glue is a positioning instruction, not a
character -- so by default every word gap in the PDF is a number that each
extractor has to guess about. Ghostscript guesses per GLYPH PAIR rather than by
width, which is why `Some fancy' came back as `Somefancy' at exactly the gap
width that 175 other pairs survived, and why no `WordSpace' setting ever
reached it.

`\\DocumentMetadata{tagging=on}' makes the engine emit a real space glyph and
shrink the following offset to compensate:

    before:  <029402640345>      -261 <01F80246...>
    after:   <0294026403450692>   -12 <01F80246...>

So there are two things to check, and both matter:

  1. every text font carries a space glyph in its subset -- without one there is
     nothing to emit;
  2. those glyphs are actually USED in the page content -- a font can carry the
     glyph while the pages still fall back to bare offsets, which is exactly
     what happens if \\DocumentMetadata is missing or tagging is off.

Only (2) is failed on. A font may legitimately carry no space glyph if no word
gap is ever set in it -- the icon fonts, for instance.

Exits non-zero if the pages use no space glyphs at all. run.sh calls it as

    subset-glyphs.py PDF
"""

import collections
import pathlib
import re
import sys

from utils.pdf import page_fonts, tounicode_map


# Fonts that never set running text, so a missing space glyph means nothing.
DECORATIVE = ("FontAwesome",)

# What counts as a space glyph. U+00A0 is included because it is still a space
# in the text layer -- whitespace-report.py is what judges whether it is a good
# one, since Java's \s does not match it.
SPACE_CODEPOINTS = (0x20, 0xA0)


def space_cids(doc, page):
    """Map font resource name -> (font name, {cid: codepoint}) for space glyphs.

    Only the first code unit is compared: a glyph whose mapping STARTS with a
    space is drawing a space, whatever else trails it.
    """
    out = {}

    for xref, ref, name in page_fonts(page):
        cmap = tounicode_map(doc, xref) or {}
        out[ref] = (name, {cid: codes[0] for cid, codes in cmap.items()
                           if codes and codes[0] in SPACE_CODEPOINTS})

    return out


def used_space_glyphs(page, fonts):
    """Count how many space glyphs the page's content stream actually draws."""
    raw = page.read_contents().decode("latin-1", "replace")
    current, used = None, collections.Counter()

    for tok in re.finditer(r"/(\w+)\s+[\d.]+\s+Tf|<([0-9a-fA-F]+)>", raw):
        if tok.group(1):
            current = tok.group(1)
            continue

        name, cmap = fonts.get(current, (None, {}))

        if not cmap:
            continue

        run = tok.group(2)
        for i in range(0, len(run) - 3, 4):
            cid = int(run[i:i + 4], 16)
            if cid in cmap:
                used[name] += 1

    return used


def main(path):
    try:
        import pymupdf
    except ImportError:
        print("SKIP: needs pymupdf -- run ./setup.sh")
        return 0

    pdf = pathlib.Path(path)
    carried, drawn = {}, collections.Counter()

    with pymupdf.open(pdf) as doc:
        for page in doc:
            fonts = space_cids(doc, page)

            for name, cmap in fonts.values():
                carried.setdefault(name, cmap)

            drawn.update(used_space_glyphs(page, fonts))

    if not carried:
        print(f"subset-glyphs.py: {pdf} embeds no fonts -- nothing to check")
        return 0

    print(f"subset-glyphs.py: {pdf}\n")
    width = max(len(n) for n in carried)
    print(f"{'FONT':<{width}}  {'SPACE GLYPH':>11}  {'DRAWN':>6}")

    text_fonts = 0

    for name in sorted(carried):
        cmap = carried[name]
        decorative = any(d in name for d in DECORATIVE)
        glyph = ", ".join(f"{c:04X}" for c in sorted(cmap)) if cmap else "none"
        n = drawn.get(name, 0)

        if not decorative:
            text_fonts += 1

        note = "  (decorative)" if decorative else ""
        print(f"{name:<{width}}  {glyph:>11}  {n:>6}{note}")

    total = sum(n for name, n in drawn.items()
                if not any(d in name for d in DECORATIVE))

    print(f"\n{total} space glyphs drawn across {text_fonts} text fonts.")

    if total == 0:
        print("\nFAIL: the pages draw no space glyphs, so every word gap is a bare\n"
              "      positioning offset that each extractor has to guess about.\n"
              "      Check that \\DocumentMetadata{...,tagging=on} is the FIRST line\n"
              "      of the .tex, and that the build really used LuaLaTeX.")
        return 1

    print("\nPASS: word gaps are real characters, not positioning instructions.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

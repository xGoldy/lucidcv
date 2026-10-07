#!/usr/bin/env python3
"""Verify the icons contribute nothing but whitespace to extracted text.

Author: Patrik Goldschmidt
Date: 2026-08-22, last rev. 2026-10-04

An icon is decoration. It must not reach a parser as a word -- "Never label an
icon with ActualText" in ../../../README.md is about exactly this, and a
contact line that extracts as `Envelope Adddress, Street' is worse than one
that extracts as `Adddress, Street', because now there is a word in the CV
that the author never wrote.

The class defends this twice over, and it needs both:

  * an EMPTY accsupp ActualText around every icon. poppler, PDFBox and Tika
    honour it. pdfium, pdf.js and Ghostscript do NOT.
  * a ToUnicode entry mapping every icon glyph to U+0020, patched into the font
    at load time by \\directlua in the class. That is what the engines above fall
    back to.

This checks the second, because it is the one that catches everything and the one
that is easy to lose. Under xdvipdfmx the FontAwesome fonts got no ToUnicode at
all, and a separate script had to attach one afterwards; luaotfload writes one
itself now, but it spells the glyph's NAME -- `Envelope', `Github' --
so it has to be overridden rather than merely present.

Exits non-zero if any icon glyph maps to something other than a space. run.sh
calls it as

    icon-check.py PDF
"""

import pathlib
import sys

from utils.pdf import page_fonts, tounicode_map


# Fonts whose glyphs are decoration, never text.
ICON_FONTS = ("FontAwesome",)

# What an icon is allowed to extract as. U+0020 is what the class patches in;
# U+00A0 is tolerated because it is still whitespace, though it is worse -- Java's
# \s does not match it, so a PDFBox/Tika-based ATS would not split a word there.
ALLOWED = {0x20: "U+0020 SPACE", 0xA0: "U+00A0 NO-BREAK SPACE"}


def icon_maps(doc, page):
    """Yield (font name, {cid: [codepoint]} or None) for each icon font used."""
    for xref, _ref, name in page_fonts(page):
        if any(f in name for f in ICON_FONTS):
            yield name, tounicode_map(doc, xref)


def main(path):
    try:
        import pymupdf
    except ImportError:
        print("SKIP: needs pymupdf -- run ./setup.sh")
        return 0

    pdf = pathlib.Path(path)
    seen, bad = {}, {}

    with pymupdf.open(pdf) as doc:
        for page in doc:
            for name, cmap in icon_maps(doc, page):
                seen.setdefault(name, cmap)

    if not seen:
        print(f"icon-check.py: {pdf} embeds no icon fonts -- nothing to check")
        return 0

    width = max(len(n) for n in seen)

    for name in sorted(seen):
        cmap = seen[name]

        if cmap is None:
            print(f"  {name:<{width}}  no ToUnicode -- MISSING")
            bad[name] = ["(no ToUnicode map at all)"]
            continue

        # CID 0 is .notdef. It is never drawn, and luaotfload maps it to U+FFFF
        # whatever we do, so counting it would fail every build for nothing.
        glyphs = {cid: codes for cid, codes in cmap.items() if cid != 0}
        offenders = [f"CID {cid:04X} -> " + "".join(chr(c) for c in codes)
                     for cid, codes in sorted(glyphs.items())
                     if len(codes) != 1 or codes[0] not in ALLOWED]

        state = "ok" if not offenders else f"{len(offenders)} NOT a space"
        print(f"  {name:<{width}}  {len(glyphs):2d} glyphs  {state}")

        if offenders:
            bad[name] = offenders

    if bad:
        print("\nFAIL: icons would reach a parser as words, not whitespace.")

        for name, offenders in bad.items():
            for o in offenders[:6]:
                print(f"    {name}: {o}")

        print("\n      The class patches these to U+0020 at font-load time with a\n"
              "      \\directlua luaotfload.patch_font callback -- see the note beside\n"
              "      \\RequirePackage{fontawesome5} in lucidcv.cls. A failure here\n"
              "      means that patch did not run, or the font names it matches on\n"
              "      changed.")
        return 1

    print("\nPASS: every icon glyph extracts as a space.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

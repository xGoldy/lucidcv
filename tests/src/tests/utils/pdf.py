"""PDF structures the checks read, through PyMuPDF.

Author: Patrik Goldschmidt
Date: 2026-09-06

icon-check.py and subset-glyphs.py both ask the same question of a font -- what
does its ToUnicode CMap say each glyph extracts as -- and then judge the answer
differently: one wants the glyphs that are NOT a space, the other wants the ones
that are. The reading is identical, so it lives here; only the judging is theirs.

Not a script -- there is nothing to run here. See utils/__init__.py for why the
helpers sit beside the checks rather than in src/.
"""

import re

#: `<0041> <00410042>' in a CMap: one source CID, one or more UTF-16 code units.
_CMAP_ENTRY = re.compile(r"<([0-9a-fA-F]{4})>\s*<([0-9a-fA-F]{4,})>")


def tounicode_map(doc, xref):
    """{cid: [codepoint]} from a font's ToUnicode CMap, or None if it has none.

    The value is a LIST because a multi-unit destination is a name rather than a
    character: luaotfload maps an icon glyph to the UTF-16 run spelling
    `Envelope', and telling that from a genuine single character is the whole
    point of icon-check.py.
    """
    tu = doc.xref_get_key(xref, "ToUnicode")

    if tu[0] == "null":
        return None

    ref = re.search(r"(\d+) 0 R", tu[1])

    if not ref:
        return None

    text = doc.xref_stream(int(ref.group(1))).decode("latin-1", "replace")

    return {int(src, 16): [int(dst[i:i + 4], 16) for i in range(0, len(dst), 4)]
            for src, dst in _CMAP_ENTRY.findall(text)}


def page_fonts(page):
    """(xref, resource name, base font name) for each font used on the page."""
    return [(f[0], f[4], f[3]) for f in page.get_fonts(full=True)]

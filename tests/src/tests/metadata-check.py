#!/usr/bin/env python3
"""Verify the document metadata reached the XMP packet, not only the Info dict.

Author: Patrik Goldschmidt
Date: 2026-10-29

A PDF carries its title, author, subject and keywords twice: in the old Info
dictionary and in the XMP metadata stream. PDF/A and PDF/UA read the XMP --
PDF/UA-1 7.1-9 requires a dc:title there -- while `pdfinfo' and most viewers'
property dialogs read the Info dict, so a gap between them stays invisible.

This is what actually happened here: the class set the metadata in the
`enddocument' hook, but the XMP packet is built when the last page ships, and
in `twocolumn' \\end{paracol} ships it before \\end{document}. The Info dict was
complete and the XMP had no title, author, subject or keywords. The class now
sets them in `shipout/firstpage', which the kernel runs ahead of
`shipout/lastpage'; this test is what notices if that ever stops holding.

What it checks, none of which depends on what main.tex says:

  * the XMP holds a non-empty dc:title
  * every field set in the Info dict -- Title, Author, Subject, Keywords -- is
    in the XMP too, with the same value (dc:title, dc:creator, dc:description,
    dc:subject)
  * dc:language agrees with the catalog's /Lang
  * /ViewerPreferences has /DisplayDocTitle true, so a viewer's title bar
    shows the title rather than the file name (PDF/UA-1 7.1-10)

Needs PyMuPDF; without it the check reports SKIP. run.sh calls it as

    metadata-check.py PDF
"""

import sys
import xml.etree.ElementTree as ET

NS = {
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "dc": "http://purl.org/dc/elements/1.1/",
}
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"

# (Info dict key, XMP property). Keywords are one comma-separated string in
# Info and one rdf:li per keyword in dc:subject, so they compare as lists.
FIELDS = [
    ("title", "dc:title"),
    ("author", "dc:creator"),
    ("subject", "dc:description"),
    ("keywords", "dc:subject"),
]


def xmp_items(root, prop):
    """[text] of the rdf:li items under `prop', x-default first for an Alt.

    Alt (title, description) holds one value per language, Seq and Bag
    (creator, subject, language) an ordered or unordered list. None when the
    property is absent altogether.
    """
    el = root.find(f".//{prop}", NS)

    if el is None:
        return None

    items = el.findall("./*/rdf:li", NS)
    default = [li for li in items if li.get(XML_LANG) == "x-default"]

    if default:
        return [(default[0].text or "").strip()]

    return [(li.text or "").strip() for li in items]


def info_items(key, value):
    """The Info dict value as the list the XMP property would hold."""
    if key == "keywords":
        return [k.strip() for k in value.split(",") if k.strip()]

    return [value.strip()]


def main(path):
    print(f"metadata-check.py: {path}\n")

    try:
        import pymupdf
    except ImportError:
        print("SKIP: needs pymupdf -- run tests/setup.sh")
        return 0

    failures = []

    with pymupdf.open(path) as doc:
        info = doc.metadata or {}
        packet = doc.get_xml_metadata()
        catalog = doc.pdf_catalog()
        lang = doc.xref_get_key(catalog, "Lang")
        prefs = doc.xref_get_key(catalog, "ViewerPreferences")

        # /ViewerPreferences is usually an indirect object; follow it.
        if prefs[0] == "xref":
            display = doc.xref_get_key(int(prefs[1].split()[0]), "DisplayDocTitle")
        elif prefs[0] == "dict":
            display = ("bool", "true" if "/DisplayDocTitle true" in prefs[1]
                       else "false")
        else:
            display = ("null", "null")

    # --- the packet ---------------------------------------------------------
    if not packet:
        print("  XMP packet             MISSING")
        print("\nFAIL: the PDF has no XMP metadata stream at all. Check that\n"
              "      main.tex still opens with \\DocumentMetadata{...}.")
        return 1

    try:
        root = ET.fromstring(packet)
    except ET.ParseError as e:
        print(f"  XMP packet             unparsable ({e})")
        print("\nFAIL: the XMP metadata stream is not well-formed XML.")
        return 1

    print("  XMP packet             present")

    # --- the fields, against the Info dict ------------------------------------
    for key, prop in FIELDS:
        xmp = xmp_items(root, prop)
        want = info_items(key, info.get(key) or "")
        shown = "; ".join(xmp) if xmp else "-"
        label = f"{prop:<22} "

        if key == "title" and not (xmp and xmp[0]):
            print(f"  {label}MISSING")
            failures.append("no dc:title in the XMP (PDF/UA-1 7.1-9)")
        elif want and not xmp:
            print(f"  {label}MISSING  -- Info has {key}: {info[key]!r}")
            failures.append(f"Info {key} is set but {prop} is missing")
        elif want and xmp != want:
            print(f"  {label}{shown!r}  -- Info has {info[key]!r}")
            failures.append(f"{prop} disagrees with Info {key}")
        else:
            print(f"  {label}{shown}")

    # --- language -------------------------------------------------------------
    xmp_lang = xmp_items(root, "dc:language")
    cat_lang = lang[1].strip("()") if lang[0] == "string" else None

    if cat_lang and xmp_lang != [cat_lang]:
        print(f"  {'dc:language':<22} {xmp_lang}  -- catalog /Lang is {cat_lang!r}")
        failures.append("dc:language disagrees with the catalog /Lang")
    else:
        print(f"  {'dc:language':<22} {'; '.join(xmp_lang or ['-'])}"
              f"  (catalog /Lang {cat_lang or '-'})")

    # --- title bar ------------------------------------------------------------
    shows_title = display == ("bool", "true")
    print(f"  {'DisplayDocTitle':<22} {'true' if shows_title else 'NOT SET'}")

    if not shows_title:
        failures.append("/ViewerPreferences lacks /DisplayDocTitle true "
                        "(PDF/UA-1 7.1-10)")

    # --- verdict --------------------------------------------------------------
    if failures:
        print("\nFAIL: the document metadata did not all reach the XMP packet.")

        for reason in failures:
            print(f"    - {reason}")

        print("\n      The XMP is built as the last page ships. lucidcv.cls sets\n"
              "      the fields in `shipout/firstpage', so a field missing here\n"
              "      was declared after the first page shipped -- or that hook\n"
              "      no longer runs first. Check where main.tex sets it.\n"
              "      DisplayDocTitle comes from \\hypersetup{pdfdisplaydoctitle}.")
        return 1

    print("\nPASS: the XMP carries the same metadata as the Info dict.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

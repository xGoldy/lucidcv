#!/usr/bin/env python3
"""Verify the built PDF really is the PDF/UA-1 it says it is.

Author: Patrik Goldschmidt
Date: 2026-10-29

`main.tex` declares \\DocumentMetadata{pdfstandard={A-2b,UA-1},...}, and as with
PDF/A that is a CLAIM: the engine writes the pdfuaid identification into the
XMP whether or not the structure behind it holds up. A PDF/UA claim is read by
assistive technology and by accessibility checkers, which trust the tags, so a
false one is worse than none.

The claim also does work of its own. Only with UA-1 declared does LaTeX give
every link annotation the /Contents description PDF/UA-1 7.18.5 asks for; the
A-2b-only build failed veraPDF on exactly that, on all six contact links. A
main.tex that drops UA-1 again loses the descriptions and the identification
together, so this check fails on a missing claim rather than skipping it.

SCOPE. This checks the rules this document can plausibly break, not the whole
of ISO 14289-1:

  * the PDF/UA identification in the XMP says part 1
  * the document is marked as tagged and has a structure tree
  * every page orders its annotations by structure (/Tabs /S)
  * every annotation is in the structure tree and has a /Contents description
  * every Figure has alternative text

The title, /DisplayDocTitle and language are metadata-check.py's job. Those
checks are an approximation, so the script also runs **veraPDF** with its
PDF/UA-1 profile when it can find one, which decides the machine-checkable
part outright and names the clause behind a failure. What no machine can
decide -- whether alt text describes its image, whether headings nest sensibly
-- stays a human review.

Needs PyMuPDF for everything after the identification; without it those checks
report `skipped' and veraPDF, when present, still decides. run.sh calls it as

    pdfua-check.py PDF
"""

import pathlib
import re
import sys

# src/ is one directory up: these run as scripts, so the shared module is not
# on the path unless we put it there.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from common import find_verapdf, raw_objects, verapdf_verdict

# What the XMP has to say for this document to be claiming PDF/UA-1.
WANT_PART = "1"

# Annotations a reader never meets as content, so PDF/UA does not ask them to
# be tagged (7.18.1). The class makes none of either.
UNTAGGED_ANNOTS = ("/Popup", "/PrinterMark")


def pdfua_part(blob):
    """The part from the XMP pdfuaid schema, or None."""
    part = re.search(rb"pdfuaid[:/]part\s*[>=]\s*[\"']?(\d+)", blob)

    return part.group(1).decode() if part else None


def role_map(doc, root):
    """{custom role: the role it maps to} from the structure tree root."""
    kind, value = doc.xref_get_key(root, "RoleMap")

    if kind == "xref":
        value = doc.xref_object(int(value.split()[0]))
    elif kind != "dict":
        return {}

    return dict(re.findall(r"/([^\s/<>\[\]()]+)\s*/([^\s/<>\[\]()]+)", value))


def standard_role(role, roles):
    """Follow the role map from `role' until it stops, as a reader does."""
    seen = set()

    while role in roles and role not in seen:
        seen.add(role)
        role = roles[role]

    return role


def structure(path):
    """[(check, summary, failures)] for the tagged structure. Needs pymupdf.

    `summary' is what to print when it is more than whether the check held.
    """
    try:
        import pymupdf
    except ImportError:
        return None

    results = []

    with pymupdf.open(path) as doc:
        cat = doc.pdf_catalog()
        marked = doc.xref_get_key(cat, "MarkInfo")
        marked = (doc.xref_object(int(marked[1].split()[0]))
                  if marked[0] == "xref" else marked[1])
        tree = doc.xref_get_key(cat, "StructTreeRoot")

        tagged = []
        if "/Marked true" not in re.sub(r"\s+", " ", marked):
            tagged.append("/MarkInfo has no /Marked true")
        if tree[0] != "xref":
            tagged.append("no /StructTreeRoot")
        results.append(("tagged", None, tagged))

        tabs = [f"page {n}" for n, page in enumerate(doc, 1)
                if doc.xref_get_key(page.xref, "Tabs")[1] != "/S"]
        results.append(("tab order /S", None, tabs))

        annots, count = [], 0
        for n, page in enumerate(doc, 1):
            for xref, _, _ in page.annot_xrefs():
                kind = doc.xref_get_key(xref, "Subtype")[1]

                if kind in UNTAGGED_ANNOTS:
                    continue

                count += 1
                if doc.xref_get_key(xref, "StructParent")[0] == "null":
                    annots.append(f"page {n} {kind} untagged")
                if doc.xref_get_key(xref, "Contents")[0] == "null":
                    annots.append(f"page {n} {kind} without /Contents")
        results.append(("annotations", f"{count}, {len(annots)} problems",
                        annots))

        figures, bare = 0, []
        if tree[0] == "xref":
            roles = role_map(doc, int(tree[1].split()[0]))

            for xref in range(1, doc.xref_length()):
                if doc.xref_get_key(xref, "Type")[1] != "/StructElem":
                    continue

                role = doc.xref_get_key(xref, "S")[1].lstrip("/")

                if standard_role(role, roles) != "Figure":
                    continue

                figures += 1
                if all(doc.xref_get_key(xref, key)[0] == "null"
                       for key in ("Alt", "ActualText")):
                    bare.append(f"object {xref} ({role})")
        results.append(("figures", f"{figures}, {len(bare)} without alt text",
                        bare))

    return results


def main(path):
    pdf = pathlib.Path(path)
    print(f"pdfua-check.py: {pdf}\n")

    blob = raw_objects(pdf.read_bytes())
    failures = []

    # --- the claim ----------------------------------------------------------
    part = pdfua_part(blob)

    if part is None:
        print("  PDF/UA identification  MISSING")
        print("\nFAIL: the PDF carries no pdfuaid metadata, so it does not claim\n"
              "      PDF/UA at all, and its links lose their /Contents with it.\n"
              "      Check that main.tex still opens with\n"
              "      \\DocumentMetadata{pdfstandard={A-2b,UA-1},tagging=on}.")
        return 1

    claim = f"PDF/UA-{part}"
    ok = part == WANT_PART
    print(f"  PDF/UA identification  {claim}"
          f"{'' if ok else f'  -- expected PDF/UA-{WANT_PART}'}")

    if not ok:
        failures.append(f"claims {claim}, not PDF/UA-{WANT_PART}")

    # --- the structure ------------------------------------------------------
    results = structure(pdf)

    if results is None:
        print("  structure              skipped (needs pymupdf)")
    else:
        for check, summary, hits in results:
            state = summary or ("ok" if not hits else f"{len(hits)} FAILED")
            print(f"  {check:<22} {state}")

            for hit in hits[:6]:
                print(f"      {hit}")
            if len(hits) > 6:
                print(f"      ... {len(hits) - 6} more")

            if hits:
                failures.append(f"{check}: {len(hits)} failed")

    # --- the reference validator ---------------------------------------------
    # Authoritative when present, as in pdfa-check.py: veraPDF's PDF/UA-1
    # profile covers every machine-checkable rule of ISO 14289-1.
    exe = find_verapdf()

    if exe is None:
        print("  veraPDF                not installed -- run tests/setup.sh")
    else:
        passed, detail = verapdf_verdict(exe, pdf, "ua1")

        if passed is True:
            print(f"  veraPDF                PASS  (PDF/UA-{WANT_PART})")
        elif passed is False:
            print(f"  veraPDF                FAIL  {detail}")
            failures.append(f"veraPDF rejects it: {detail}")
        else:
            print(f"  veraPDF                inconclusive -- {detail}")

    # --- verdict ------------------------------------------------------------
    if failures:
        print(f"\nFAIL: {pdf.name} claims {claim} but breaks it.")

        for reason in failures:
            print(f"    - {reason}")

        print("\n      A Figure without alt text is the likeliest cause: an image\n"
              "      or tikz drawing added to the CV needs one (\\cvphoto's comes\n"
              "      from \\name). A link without /Contents means UA-1 is no\n"
              "      longer declared in \\DocumentMetadata.")
        return 1

    print(f"\nPASS: {pdf.name} holds up as {claim}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

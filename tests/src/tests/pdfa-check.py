#!/usr/bin/env python3
"""Verify the built PDF really is the PDF/A-2B it says it is.

Author: Patrik Goldschmidt
Date: 2026-08-28, last rev. 2026-10-29

`main.tex` opens with \\DocumentMetadata{pdfstandard={A-2b,UA-1},...}, and that
line is a CLAIM, not a guarantee: the engine stamps the PDF/A identification
into the XMP whether or not the file that comes out actually conforms. It warns
when it notices a breach --

    Package pdf Warning: PDF standard validation failure.
    (pdf)                Embedded non-PDF files detected.
    (pdf)                This is not allowed in standard pdf/A-2B

-- but that warning goes to the .log, which ../build.sh deletes. A
PDF that claims PDF/A and is not one is worse than one that never claimed it,
because an archive that trusts the claim will reject the file downstream.

This is what actually happened here: LaTeX's list and align tagging attaches
latex-list-css.html and latex-align-css.html as associated files, and PDF/A-2
allows embedding only PDF/A-1 or PDF/A-2 files. The class now suppresses them
with \\tagpdfsetup{attach-css=false}; this test is what keeps them suppressed.

SCOPE. This checks the conformance rules that this document can plausibly
break, not the whole of ISO 19005-2:

  * the PDF/A identification in the XMP says part 2, conformance B
  * no embedded file is anything other than a PDF        (the bug above)
  * an OutputIntent with a destination profile is present
  * every font used is embedded
  * the file is not encrypted
  * no JavaScript, and no Launch/Movie/Sound actions

Those checks are an approximation, so the script also runs **veraPDF** when it
can find one -- the reference implementation of ISO 19005, which decides the
question outright and names the clause behind a failure. It is looked for in
$VERAPDF, then tests/env/verapdf/vendor/, then on PATH; tests/setup.sh
installs it. Without it the checks above still run and still fail the build,
they just cannot cite chapter and verse.

Exits non-zero if the PDF claims PDF/A-2B and breaks one of the rules above,
or if it does not carry the PDF/A identification at all. run.sh calls it as

    pdfa-check.py PDF
"""

import pathlib
import re
import sys

# src/ is one directory up: these run as scripts, so the shared module is not
# on the path unless we put it there.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from common import find_verapdf, raw_objects, verapdf_verdict


# What the XMP has to say for this document to be claiming PDF/A-2B.
WANT_PART = "2"
WANT_CONFORMANCE = "B"

# Subtypes that may legally sit in an /EmbeddedFile under PDF/A-2. The spec
# allows only PDF/A-1 and PDF/A-2 files; a PDF mime type is as close as we can
# get without recursing into the attachment and validating it too.
PDF_SUBTYPES = ("application/pdf",)

# Actions PDF/A forbids outright.
FORBIDDEN_ACTIONS = ("/JavaScript", "/Launch", "/Movie", "/Sound", "/ResetForm",
                     "/ImportData")


def pdfa_identification(blob):
    """(part, conformance) from the XMP pdfaid schema, or (None, None)."""
    part = re.search(rb"pdfaid[:/]part\s*[>=]\s*[\"']?(\d+)", blob)
    conf = re.search(rb"pdfaid[:/]conformance\s*[>=]\s*[\"']?([AB])", blob)

    return (part.group(1).decode() if part else None,
            conf.group(1).decode() if conf else None)


def embedded_file_subtype(blob, objnum):
    """The /Subtype of the /EmbeddedFile stream held in object `objnum`."""
    obj = re.search(rb"(?<![0-9])" + str(objnum).encode() + rb"\s+0\s+obj(.{0,400}?)stream",
                    blob, re.S)

    if not obj or b"/EmbeddedFile" not in obj.group(1):
        return ""

    subtype = re.search(rb"/Subtype\s*/([A-Za-z0-9#]+)", obj.group(1))

    return subtype.group(1).decode("latin-1") if subtype else ""


def unhex_name(raw):
    """PDF names escape non-regular bytes as #xx -- `text#2Fhtml' is text/html."""
    return re.sub(r"#([0-9a-fA-F]{2})",
                  lambda m: chr(int(m.group(1), 16)), raw)


def embedded_files(blob):
    """[(filename, subtype)] for every /Filespec that carries an attachment.

    The MIME type is not on the /Filespec: it sits on the /EmbeddedFile stream
    the spec's /EF entry points at, so the object reference has to be followed.
    """
    found = []

    for match in re.finditer(rb"/Type\s*/Filespec(.{0,400}?)>>\s*>>",
                             blob, re.S):
        spec = match.group(1)
        name = re.search(rb"/F\s*\(([^)]*)\)", spec)
        ref = re.search(rb"/EF\s*<<\s*/F\s+(\d+)\s+0\s+R", spec)

        subtype = embedded_file_subtype(blob, int(ref.group(1))) if ref else ""

        # fall back to a /Subtype on the spec itself, if some producer put it there
        if not subtype:
            own = re.search(rb"/Subtype\s*/([A-Za-z0-9#]+)", spec)
            subtype = own.group(1).decode("latin-1") if own else ""

        found.append((name.group(1).decode("latin-1") if name else "<unnamed>",
                      unhex_name(subtype)))

    return found


def unembedded_fonts(path):
    """Fonts the document draws with but does not carry. Needs pymupdf."""
    try:
        import pymupdf
    except ImportError:
        return None

    with pymupdf.open(path) as doc:
        # Every font once, however many pages use it.
        fonts = {f[0]: f[3] for page in doc for f in page.get_fonts(full=True)}

        # extract_font returns an empty buffer for a font that is only
        # referenced by name and expected to come from the viewer.
        missing = {name for xref, name in fonts.items()
                   if not doc.extract_font(xref)[3]}

        return missing, doc.is_encrypted


def main(path):
    pdf = pathlib.Path(path)
    print(f"pdfa-check.py: {pdf}\n")

    blob = raw_objects(pdf.read_bytes())
    failures = []

    # --- the claim ----------------------------------------------------------
    part, conformance = pdfa_identification(blob)

    if part is None or conformance is None:
        print("  PDF/A identification   MISSING")
        print("\nFAIL: the PDF carries no pdfaid metadata, so it does not claim\n"
              "      PDF/A at all. Check that main.tex still opens with\n"
              "      \\DocumentMetadata{pdfstandard={A-2b,UA-1},tagging=on}.")
        return 1

    claim = f"PDF/A-{part}{conformance}"
    ok = part == WANT_PART and conformance == WANT_CONFORMANCE
    print(f"  PDF/A identification   {claim}"
          f"{'' if ok else f'  -- expected PDF/A-{WANT_PART}{WANT_CONFORMANCE}'}")

    if not ok:
        failures.append(f"claims {claim}, not PDF/A-{WANT_PART}{WANT_CONFORMANCE}")

    # --- embedded files -----------------------------------------------------
    attachments = embedded_files(blob)
    offenders = [(n, s) for n, s in attachments
                 if not any(p in s for p in PDF_SUBTYPES)]

    if not attachments:
        print("  embedded files         none")
    else:
        print(f"  embedded files         {len(attachments)}, "
              f"{len(offenders)} not a PDF")

        for name, subtype in attachments:
            mark = "  <-- not allowed" if (name, subtype) in offenders else ""
            print(f"      {name}  [{subtype or 'no /Subtype'}]{mark}")

    if offenders:
        failures.append(f"{len(offenders)} embedded non-PDF file(s)")

    # --- output intent ------------------------------------------------------
    has_intent = b"/OutputIntent" in blob and b"/DestOutputProfile" in blob
    print(f"  output intent          {'present' if has_intent else 'MISSING'}")

    if not has_intent:
        failures.append("no OutputIntent with a DestOutputProfile")

    # --- forbidden actions --------------------------------------------------
    present = [a for a in FORBIDDEN_ACTIONS
               if re.search(re.escape(a.encode()) + rb"[^A-Za-z]", blob)]
    print(f"  forbidden actions      {', '.join(present) if present else 'none'}")

    if present:
        failures.append(f"forbidden action(s): {', '.join(present)}")

    # --- fonts and encryption ----------------------------------------------
    fonts = unembedded_fonts(pdf)

    if fonts is None:
        print("  fonts embedded         skipped (needs pymupdf)")
    else:
        missing, encrypted = fonts
        print(f"  fonts embedded         "
              f"{'all' if not missing else f'{len(missing)} MISSING'}")
        print(f"  encryption             {'YES' if encrypted else 'none'}")

        if missing:
            for name in sorted(missing):
                print(f"      {name}  not embedded")
            failures.append(f"{len(missing)} font(s) not embedded")

        if encrypted:
            failures.append("file is encrypted")

    # --- the reference validator ---------------------------------------------
    # Authoritative when present: veraPDF implements the whole of ISO 19005-2,
    # so it decides the question the checks above only approximate. They still
    # run, because their per-rule breakdown says WHERE the problem is, and
    # because they are all a machine without veraPDF gets.
    exe = find_verapdf()

    if exe is None:
        print("  veraPDF                not installed -- run tests/setup.sh")
    else:
        passed, detail = verapdf_verdict(exe, pdf, "2b")

        if passed is True:
            print(f"  veraPDF                PASS  (PDF/A-{WANT_PART}{WANT_CONFORMANCE})")
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

        print("\n      An embedded non-PDF file is the one this project has hit:\n"
              "      LaTeX's list/align tagging attaches latex-list-css.html and\n"
              "      latex-align-css.html unless the class turns them off with\n"
              "      \\tagpdfsetup{attach-css=false}. Check that hook is still in\n"
              "      lucidcv.cls, and read the build log -- the engine says\n"
              "      `PDF standard validation failure' when it notices.")
        return 1

    print(f"\nPASS: {pdf.name} holds up as {claim}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

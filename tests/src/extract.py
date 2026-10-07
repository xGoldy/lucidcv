#!/usr/bin/env python3
"""Read a PDF back with every text extractor available on this machine.

Author: Patrik Goldschmidt
Date: 2026-08-20, last rev. 2026-10-05

Writes one <engine>.txt per engine into the output directory; check.py scores
them. Engines that are not installed are skipped with a note rather than
failing the run -- none of them is a hard dependency. run.sh calls it as

    extract.py PDF OUTDIR

The engines, and why each one is here:

  poppler          pdftotext -- what Okular, most Linux tooling and a good share
                   of real ATS pipelines use. The one that matters most.
  poppler-raw      same, in content-stream order rather than reading order
  poppler-layout   same, preserving physical layout; interleaves two columns
  mupdf            PyMuPDF, a wholly independent implementation
  pdfium           Chrome's engine, via pypdfium2
  pdfminer         pdfminer.six, pure Python, the usual choice for home-grown
                   CV parsers
  ghostscript      txtwrite -- the strictest word-gap heuristic of the set
  pdfjs-old        pdf.js 2.5.207, the vintage embedded in editor viewers such
                   as the VS Code PDF extension. Needs ./setup.sh.
  pdfjs-new        current pdf.js, i.e. Firefox. Needs ./setup.sh.
  pdfbox           Apache PDFBox, the extractor underneath a large share of the
                   JVM document pipelines an ATS is built out of. Needs
                   ./setup.sh.
  pdfbox-sorted    the same with -sort, the position-sorting mode ATS
                   integrations commonly switch on; interleaves two columns
  tika             Apache Tika, the general-purpose detect-and-extract front
                   end. It delegates PDFs to PDFBox, so this checks what Tika's
                   own defaults do to that output rather than a second
                   implementation. Needs ./setup.sh.
  tesseract        OCR of the rendered pixels, via poppler's pdftoppm. What an
                   ATS falls back to when a PDF has no usable text layer, and
                   the only engine here that never reads one.

Not covered: the commercial resume parsers (Sovren, Daxtra, HireAbility and
friends). They are hosted, paid and rate-limited, so no local test can exercise
them -- but they extract with one of the engines above before their own
semantic pass runs, so what is checked here is the half that can be checked.
"""

import concurrent.futures
import pathlib
import shutil
import subprocess
import sys
import tempfile

from common import ENGINES, ENV_DIR


PDFJS_DIR = ENV_DIR / "pdfjs"
PDFJS_VENDOR = PDFJS_DIR / "vendor"
JAVA_VENDOR = ENV_DIR / "java" / "vendor"

#: Engines that run inside this interpreter rather than as a subprocess. They
#: stay on the main thread: pdfium is not safe to call from a second thread.
IN_PROCESS = {"mupdf", "pdfium", "pdfminer"}


# ---- Helper functions ------------------------------------------------------
def get_node_bin_path():
    """Return the path to a Node binary, or None if it is not available."""
    local = PDFJS_VENDOR / "node" / "bin" / "node"

    return str(local) if local.exists() else shutil.which("node")


def get_jar_path(name):
    """Return the path to a jar fetched by setup.sh, or None if absent."""
    jar = JAVA_VENDOR / name

    return str(jar) if jar.exists() else None


# Neither helper reports success: main() checks the file each engine left
# behind, so "it ran" and "it produced something" are one test for all of them.
def run(cmd):
    """Run a command that writes its own output file."""
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)


def capture(cmd, out):
    """Run a command and capture stdout into out."""
    r = subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL)
    out.write_bytes(r.stdout)

# ---- Extraction engines ----------------------------------------------------
def mupdf(pdf, out):
    """Extract text with PyMuPDF."""
    import pymupdf

    with pymupdf.open(pdf) as doc:
        text = "".join(page.get_text() for page in doc)

    out.write_text(text, encoding="utf-8")


def pdfium(pdf, out):
    """Extract text with pypdfium2."""
    import pypdfium2

    doc = pypdfium2.PdfDocument(pdf)

    # Unlike PyMuPDF, a pdfium page does not end in a newline: joined with "",
    # the last line of a page would fuse with the first line of the next.
    try:
        text = "\f".join(p.get_textpage().get_text_range() for p in doc)
    finally:
        doc.close()

    out.write_text(text, encoding="utf-8")


def pdfminer(pdf, out):
    """Extract text with pdfminer.six."""
    from pdfminer.high_level import extract_text

    text = extract_text(str(pdf))
    out.write_text(text, encoding="utf-8")

def tesseract(pdf, out):
    """Render the pages to bitmaps with poppler and OCR them with Tesseract.

    The only engine here that never reads the text layer, so it says what an
    ATS sees when it decides there is not a usable one and falls back to OCR.
    300 dpi greyscale is the usual choice: below it the 8 pt body text in the
    sidebar starts to break up, above it costs time and changes nothing.
    Pages are independent, so they are read concurrently, in page order.
    """
    with tempfile.TemporaryDirectory() as tmp:
        stem = pathlib.Path(tmp) / "page"
        subprocess.run(["pdftoppm", "-r", "300", "-gray", "-png",
                        str(pdf), str(stem)],
                       check=True, stderr=subprocess.DEVNULL)

        pages = sorted(pathlib.Path(tmp).glob("page-*.png"))

        if not pages:
            raise RuntimeError("pdftoppm rendered no pages")

        def ocr(page):
            return subprocess.run(["tesseract", str(page), "stdout"],
                                  check=True, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL).stdout.decode("utf-8")

        with concurrent.futures.ThreadPoolExecutor() as pool:
            text = "".join(pool.map(ocr, pages))

    out.write_text(text, encoding="utf-8")

def attempt(fn, pdf, target):
    """Run one engine. None if it wrote text, else why it was skipped.

    An engine that exits 0 without writing anything used to report `ok' and
    then read as `not run' in every table -- the emptiest possible way to lose
    an engine -- so the file it left behind is what decides.
    """
    try:
        fn(pdf, target)

        if not (target.exists() and target.stat().st_size):
            raise RuntimeError("exited cleanly but wrote no text")

        return None
    except Exception as e:  # noqa: BLE001 -- a missing engine is not fatal
        target.unlink(missing_ok=True)
        return f"{type(e).__name__}: {e}"


# ---- Main program ----------------------------------------------------------
def main(pdf, outdir):
    # Resolve PDF path and check if it exists
    pdf = pathlib.Path(pdf).resolve()

    if not pdf.exists():
        print(f"extract.py: no such file: {pdf}", file=sys.stderr)
        return 1

    # Create the output directory and clear the previous run out of it. The
    # .json summaries go with the .txt they describe: order.py's order.json
    # names specific engines and counts, so left behind it would outlive the
    # extraction it summarises and read as current. Only these files: the
    # directory also holds pipeline.sh's phrases.txt, which the scorers read
    # next.
    out = pathlib.Path(outdir)
    out.mkdir(parents=True, exist_ok=True)

    for stale in [f"{engine}.txt" for engine in ENGINES] + ["order.json"]:
        (out / stale).unlink(missing_ok=True)

    node = get_node_bin_path()
    pdfbox_jar = get_jar_path("pdfbox-app.jar")
    tika_jar = get_jar_path("tika-app.jar")
    java = shutil.which("java")
    engines = []

    # Initialize engines -- pdftotext and ghostscript as command line utilities
    if shutil.which("pdftotext"):
        engines += [
            ("poppler", lambda pdf, out: run(
                ["pdftotext", str(pdf), str(out)])),
            ("poppler-raw", lambda pdf, out: run(
                ["pdftotext", "-raw", str(pdf), str(out)])),
            ("poppler-layout", lambda pdf, out: run(
                ["pdftotext", "-layout", str(pdf), str(out)])),
        ]

    if shutil.which("gs"):
        engines.append(("ghostscript", lambda pdf, out: run(
            ["gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=txtwrite",
             f"-sOutputFile={out}", str(pdf)])))

    # Initialize engines -- pdf.js requires a Node binary
    if node:
        engines += [
            ("pdfjs-old", lambda pdf, out: capture(
                [node, str(PDFJS_DIR / "extract-old.cjs"), str(pdf)], out)),
            ("pdfjs-new", lambda pdf, out: capture(
                [node, str(PDFJS_DIR / "extract-new.mjs"), str(pdf)], out)),
        ]

    # Initialize engines -- PDFBox and Tika are jars needing a JRE on PATH
    if java and pdfbox_jar:
        engines += [
            ("pdfbox", lambda pdf, out: run(
                [java, "-jar", pdfbox_jar, "export:text",
                 "-i", str(pdf), "-o", str(out)])),
            ("pdfbox-sorted", lambda pdf, out: run(
                [java, "-jar", pdfbox_jar, "export:text", "-sort",
                 "-i", str(pdf), "-o", str(out)])),
        ]

    if java and tika_jar:
        engines.append(("tika", lambda pdf, out: capture(
            [java, "-jar", tika_jar, "--text", str(pdf)], out)))

    # Initialize engines -- OCR needs both the renderer and Tesseract itself
    if shutil.which("pdftoppm") and shutil.which("tesseract"):
        engines.append(("tesseract", tesseract))

    # Initialize engines -- PyMuPDF, pypdfium2, and pdfminer via Python calls
    engines += [("mupdf", mupdf), ("pdfium", pdfium), ("pdfminer", pdfminer)]

    # Report in the order the scorers do, and refuse a name they do not know:
    # an engine that writes to a file check.py never looks for reads as "not
    # run" in every table, which is the quietest way to lose a whole engine.
    unknown = [name for name, _ in engines if name not in ENGINES]

    if unknown:
        print(f"extract.py: engine name(s) missing from common.ENGINES: "
              f"{', '.join(unknown)}", file=sys.stderr)
        return 2

    engines.sort(key=lambda e: ENGINES.index(e[0]))

    print(f"extract.py: reading {pdf} -> {out}/")

    # Every engine writes a file of its own and none reads another's, so the
    # subprocess ones run concurrently -- Tesseract and the JVM start-ups
    # otherwise dominate the run -- while the in-process ones take the main
    # thread. Results are printed afterwards, in the scorers' order.
    with concurrent.futures.ThreadPoolExecutor() as pool:
        pending = {name: pool.submit(attempt, fn, pdf, out / f"{name}.txt")
                   for name, fn in engines if name not in IN_PROCESS}
        skipped = {name: attempt(fn, pdf, out / f"{name}.txt")
                   for name, fn in engines if name in IN_PROCESS}
        skipped.update((name, f.result()) for name, f in pending.items())

    for name, _ in engines:
        why = skipped[name]
        print(f"  {name:<15} {'ok' if why is None else f'skipped ({why})'}")

    # Print notes about missing dependencies
    for name, why in [
        ("pdftotext", "poppler-utils" if not shutil.which("pdftotext") else None),
        ("gs", "ghostscript" if not shutil.which("gs") else None),
        ("node", "run tests/setup.sh" if not node else None),
        ("java", "install a JRE 11+" if not java else None),
        ("pdfbox-app.jar / tika-app.jar",
         "run tests/setup.sh" if java and not (pdfbox_jar and tika_jar)
         else None),
        ("tesseract", "tesseract-ocr" if not shutil.which("tesseract") else None),
    ]:
        if why:
            print(f"  note: {name} not found -- {why}")

    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))

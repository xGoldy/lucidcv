"""Shared vocabulary for the pipeline and the two scorers.

Author: Patrik Goldschmidt
Date: 2026-09-06, last rev. 2026-10-04

check.py and order.py read the same extractions and the same phrase list, so
they have to agree on which engines exist and in what order they are reported,
which of them each variant excuses, how a phrase is folded before it is
matched, where a phrase is found in an extraction, and how the phrase file is
parsed. All of that lives here, so neither scorer imports the other.
pdfa-check.py and pdfua-check.py share the raw-object scan and the veraPDF run.

Not a script -- there is nothing to run here.
"""

import collections
import os
import pathlib
import re
import shutil
import subprocess
import unicodedata
import zlib

SRC_DIR = pathlib.Path(__file__).resolve().parent
TESTS_DIR = SRC_DIR.parent

#: One folder per pipeline run, out/<label>/.
OUT_DIR = TESTS_DIR / "out"

#: Third-party engines and their setup scripts, one directory each.
ENV_DIR = TESTS_DIR / "env"

#: Every engine extract.py can write, in the order both scorers report them.
ENGINES = ["poppler", "poppler-raw", "poppler-layout", "mupdf", "pdfium",
           "pdfminer", "ghostscript", "pdfjs-old", "pdfjs-new",
           "pdfbox", "pdfbox-sorted", "tika", "tesseract"]

#: The four builds the class can make: layout, and whether it is compressed.
VARIANTS = ("onecolumn", "onecolumn-compr", "twocolumn", "twocolumn-compr")

#: Engines excused per variant, one table per scorer. An advisory engine is
#: reported and never failed on; every engine not named is STRICT. A
#: compressed build interleaves the same way as its plain twin -- measured,
#: not assumed -- so each pair shares a set.
#:
#: Coverage (check.py). Tesseract reads pixels rather than the text layer, so
#: its misses are a fact about the typography, and it is advisory everywhere.
#: In two columns, poppler-layout, ghostscript and pdfbox-sorted lay the
#: columns side by side on one line, so every phrase that wraps gets the other
#: column spliced into it. poppler and pdfjs-old also sort by position, but
#: measurably return every phrase there, so they stay strict.
#:
#: Order (order.py). In two columns every engine that rebuilds reading order
#: from geometry interleaves the columns somewhere -- poppler and pdfminer
#: included. pdfminer runs LAParams over the page and agreed with content
#: order until an edit moved the column heights, at which point it emitted
#: the whole Publications block after References. The engines that hold 1.00
#: there do so because they emit content-stream order. In one column all
#: twelve text-layer engines reach 1.00 (re-verified 2026-09-06).
_COVERAGE_2C = {"poppler-layout", "ghostscript", "pdfbox-sorted", "tesseract"}
_ORDER_2C = _COVERAGE_2C | {"poppler", "pdfminer"}

COVERAGE_ADVISORY = {"onecolumn": {"tesseract"}, "twocolumn": _COVERAGE_2C}
ORDER_ADVISORY = {"onecolumn": {"tesseract"}, "twocolumn": _ORDER_2C}

for _table in (COVERAGE_ADVISORY, ORDER_ADVISORY):
    _table["onecolumn-compr"] = _table["onecolumn"]
    _table["twocolumn-compr"] = _table["twocolumn"]

#: The phrase-file section holding the contact block. order.py scores that
#: group but never fails on it -- see its module docstring.
HEADER_GROUP = "header / contact"

#: Typographic variants an extractor may legitimately return in place of the
#: character the document sets. Folding them is not leniency: a phrase that
#: comes back with an en dash for a hyphen has survived extraction.
_FOLD = [("‐", "-"), ("‑", "-"), ("‒", "-"), ("–", "-"),
         ("—", "-"), ("−", "-"), ("‘", "'"), ("’", "'"),
         ("“", '"'), ("”", '"'), ("ﬀ", "ff"), ("ﬁ", "fi"),
         ("ﬂ", "fl"), (" ", " "), (" ", " "), (" ", " ")]

#: What load_phrases returns: the whole list in file order, plus the two groups
#: order.py holds to different standards. `all' is what check.py scores.
Phrases = collections.namedtuple("Phrases", "all header body")


def norm(s):
    """Fold away the typographic variants an extractor may legitimately emit."""
    s = unicodedata.normalize("NFKC", s)

    for a, b in _FOLD:
        s = s.replace(a, b)

    # Case-folded, because a heading set through \MakeUppercase is not a lost
    # phrase -- every parser worth the name matches case-insensitively.
    return re.sub(r"\s+", " ", s).strip().casefold()


def locate(text, phrases):
    """{key: [start, ...]} -- where each phrase occurs in folded `text'.

    Every occurrence is its own, so a phrase listed twice can be found twice and
    a short phrase is not found inside a longer one. Keys are claimed longest
    first, and a match may not overlap a span a longer key already claimed:
    `Experience' the heading is only found where it stands on its own, not
    inside `R&D experience'. A match also has to sit on word boundaries
    wherever the phrase starts or ends with a word character, so `BUT' is not
    found inside `distributed'.

    `text' is folded with norm() already; `phrases' are raw and folded here.
    """
    keys = sorted({k for k in map(norm, phrases) if k}, key=len, reverse=True)
    taken, found = [], {}

    for key in keys:
        head = r"(?<!\w)" if re.match(r"\w", key) else ""
        tail = r"(?!\w)" if re.search(r"\w$", key) else ""
        spans = []

        for m in re.finditer(head + re.escape(key) + tail, text):
            start, end = m.span()

            if not any(s < end and start < e for s, e in taken):
                spans.append(start)
                taken.append((start, end))

        found[key] = spans

    return found


def read_extractions(outdir):
    """{engine: folded text} for every engine that wrote into outdir.

    Both scorers walk the same directory and fold the same files with norm(),
    and order.py scores two phrase groups over them -- so reading here rather
    than in each of them normalises every extraction once instead of three
    times, and keeps "which files count as a run" in one place.
    """
    out = pathlib.Path(outdir)
    texts = {}

    for engine in ENGINES:
        f = out / f"{engine}.txt"

        if f.exists():
            texts[engine] = norm(f.read_text(encoding="utf-8", errors="replace"))

    return texts


def load_phrases(path):
    """The visible phrases of the document.

    A `# name' line opens a section, and the section named by HEADER_GROUP is
    the contact block. A file with no section comments puts everything in the
    body, which is the safe direction -- it fails loudly rather than quietly
    excusing.

    `path' is required: there is no default list. A score is only meaningful
    against the list generated from the document that was built, and a shared
    default is how a one-page body was once scored against a two-page body's
    list -- 32 phrases it never contained came back as a regression in all
    twelve strict engines at once. pipeline.sh generates the list per run.
    """
    every, header, body, group = [], [], [], None

    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        line = line.strip()

        if line.startswith("#"):
            group = line.lstrip("#").strip()
        elif line:
            every.append(line)
            (header if group == HEADER_GROUP else body).append(line)

    return Phrases(every, header, body)


def raw_objects(data):
    """The file's bytes plus every stream we can inflate, as one blob.

    Object streams keep most of the structure compressed, so a plain scan of
    the file misses the catalog, the Filespec dictionaries and the XMP packet.
    """
    blobs = [data]

    for match in re.finditer(rb"stream\r?\n(.*?)endstream", data, re.S):
        try:
            blobs.append(zlib.decompress(match.group(1)))
        except zlib.error:
            pass

    return b"\n".join(blobs)


# Where veraPDF may be found, most explicit first. setup.sh installs into
# env/verapdf/vendor/; VERAPDF overrides when it was put somewhere else,
# which is what a full root filesystem forces.
def find_verapdf():
    env = os.environ.get("VERAPDF")

    if env and pathlib.Path(env).is_file() and os.access(env, os.X_OK):
        return env

    local = ENV_DIR / "verapdf" / "vendor" / "verapdf"

    if local.is_file() and os.access(local, os.X_OK):
        return str(local)

    return shutil.which("verapdf") or None


def verapdf_verdict(exe, pdf, flavour):
    """(passed, detail) from the reference validator, or (None, why-not).

    `flavour' is veraPDF's profile name: `2b' for PDF/A-2B, `ua1' for PDF/UA-1.
    One run of the default XML report carries both the verdict and, on a
    failure, the standard and clause behind each failed rule.
    """
    try:
        r = subprocess.run([exe, "-f", flavour, str(pdf)],
                           capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.SubprocessError) as e:
        return None, f"could not run veraPDF: {e}"

    verdict = re.search(r'isCompliant="(true|false)"', r.stdout)

    if not verdict:
        head = (r.stderr or r.stdout).strip().split("\n")[0]
        return None, head or "veraPDF produced no verdict"

    if verdict.group(1) == "true":
        return True, ""

    rules = re.findall(r'specification="([^":]+)[^"]*"\s+clause="([^"]+)"'
                       r'\s+testNumber="([^"]+)"', r.stdout)
    detail = "; ".join(f"{s} clause {c} test {t}"
                       for s, c, t in dict.fromkeys(rules))

    return False, detail or "non-compliant, no rule named"

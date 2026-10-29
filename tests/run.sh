#!/usr/bin/env bash
#
# Read a built PDF back with every text extractor on this machine and check
# that the sample's content survived.
#
# Author: Patrik Goldschmidt
# Date: 2026-08-20, last rev. 2026-10-04
#
#   ./run.sh <pdf> <variant> [label] --phrases=FILE
#
# The TEST STAGE: it builds nothing and generates nothing. It checks the PDF it
# is handed against the phrase list it is handed, under <variant>'s rules --
# one of onecolumn, onecolumn-compr, twocolumn, twocolumn-compr -- and writes
# the extractions to out/<label>. <label> defaults to <variant>.
#
# Both the PDF and the list are required, and there are no defaults for either:
# a default PDF scores whatever build happens to be lying around, and a default
# list scores it against whichever document that list was generated from. Each
# has produced a green run on a stale file, or a twelve-engine "regression" in
# a document that never contained the phrases. ./pipeline.sh builds the PDF and
# generates the list from the same main.tex and then calls this; use it unless
# you already have both.
#
# Six independent checks FAIL the run:
#
# src/tests/subset-glyphs.py -- word gaps are real space characters, not positioning
#                     instructions. A property of the PDF LuaLaTeX guarantees.
# src/tests/check.py -- every phrase in the list comes back from each
#             extractor, under the rules for the layout the PDF was built in.
# src/tests/icon-check.py -- every icon glyph extracts as a space rather than as NAME.
#                  some ignore the empty ActualText, needing \directlua patch.
# src/tests/pdfa-check.py -- the PDF is the PDF/A-2B it advertises. \DocumentMetadata
#                  stamps the claim in either way, and the engine's complaint
#                  goes only to a .log that ../build.sh deletes.
#                  Defers to veraPDF when ./setup.sh has installed it.
# src/tests/metadata-check.py -- the title, author, subject and keywords reached
#                  the XMP packet, not only the Info dict. In twocolumn the
#                  last page once shipped before the class had set them.
# src/tests/order.py -- how much of each engine's output arrives in document ORDER.
#             check.py tests only whether a phrase is present; a CV whose
#             Education dates come back after References is still mis-filed.
#             The BODY (the file main.tex \input's) is strict and fails the
#             run. The contact block is reported only -- field order there
#             carries no meaning. In twocolumn every geometry-based engine is
#             advisory, poppler included: interleaving two columns is the
#             layout, not a regression.
#
# One further pass reports rather than fails, as it judges the document:
#
# src/tests/whitespace-report.py -- which engines return a word gap that is not U+0020.
#                         E.g., java.util.regex \s does not match U+00A0
#                         so PDFBox/Tika-based ATSs will not split on it.
#
# Exits non-zero if any of the six fails. Which engines each variant excuses is
# COVERAGE_ADVISORY and ORDER_ADVISORY in src/common.py.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The three Python extractors (PyMuPDF, pypdfium2, pdfminer.six) live in the
# virtualenv setup.sh builds, not in the system Python, so the checkers are
# invoked through that interpreter. Falling back to PATH keeps the suite usable
# on a machine where those three are installed some other way -- the engines
# that are missing then report as `not run' rather than failing anything.
PY="$HERE/env/python/bin/python3"
[[ -x "$PY" ]] || PY="$(command -v python3 || true)"
[[ -n "$PY" ]] || { echo "run.sh: no python3 -- run ./setup.sh" >&2; exit 1; }

# ---- Arguments --------------------------------------------------------------
# --phrases may appear anywhere, not only ahead of the path. An earlier revision
# stopped scanning at the first non-flag and silently dropped a trailing
# --phrases=FILE, scoring against the wrong list.
phrases=""
args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phrases=*)  phrases="${1#--phrases=}"; shift ;;
    --)           shift; args+=("$@"); break ;;
    -*)           echo "run.sh: unknown flag: $1 -- expected --phrases=FILE" >&2
                  exit 1 ;;
    *)            args+=("$1"); shift ;;
  esac
done

set -- "${args[@]+${args[@]}}"

if [[ $# -lt 2 || $# -gt 3 || -z "$phrases" ]]; then
  echo "run.sh: a PDF, its variant and its phrase list are required" >&2
  echo "  usage: run.sh <pdf> <variant> [label] --phrases=FILE" >&2
  echo "  ./pipeline.sh <main.tex> builds the PDF, generates the list and runs this" >&2
  exit 1
fi

PDF="$1"
VARIANT="$2"
# The output directory, out/<label>. Defaults to the variant; pipeline.sh
# passes the document's own label so two documents never share one.
LABEL="${3:-$VARIANT}"

case "$VARIANT" in
  onecolumn|onecolumn-compr|twocolumn|twocolumn-compr) ;;
  *) echo "run.sh: unknown variant: $VARIANT -- expected onecolumn," \
          "onecolumn-compr, twocolumn or twocolumn-compr" >&2
     exit 1 ;;
esac

[[ -f "$PDF" ]]     || { echo "run.sh: no such file: $PDF" >&2; exit 1; }
[[ -f "$phrases" ]] || { echo "run.sh: no such phrase list: $phrases" >&2; exit 1; }

# Set explicit UTF-8 encoding
export PYTHONIOENCODING=utf-8

OUT="$HERE/out/$LABEL"
status=0

echo "=== real word spaces ==="
"$PY" "$HERE/src/tests/subset-glyphs.py" "$PDF" || status=1

echo
echo "=== icons extract as whitespace ==="
"$PY" "$HERE/src/tests/icon-check.py" "$PDF" || status=1

echo
echo "=== PDF/A-2B conformance ==="
"$PY" "$HERE/src/tests/pdfa-check.py" "$PDF" || status=1

echo
echo "=== XMP metadata ==="
"$PY" "$HERE/src/tests/metadata-check.py" "$PDF" || status=1

echo
echo "=== text extraction ==="
"$PY" "$HERE/src/extract.py" "$PDF" "$OUT"
echo
"$PY" "$HERE/src/tests/check.py" "$OUT" "$VARIANT" "$phrases" || status=1

echo
echo "=== reading order ==="
"$PY" "$HERE/src/tests/order.py" "$OUT" "$VARIANT" "$phrases" || status=1

echo
echo "=== word-gap characters ==="
"$PY" "$HERE/src/tests/whitespace-report.py" "$OUT"

exit $status

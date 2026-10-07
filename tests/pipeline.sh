#!/usr/bin/env bash
#
# Generate the phrase list for one document, build it, and test it.
#
# Author: Patrik Goldschmidt
# Date: 2026-09-26, last rev. 2026-10-04
#
#   ./pipeline.sh MAIN                       the document MAIN
#   ./pipeline.sh MAIN --opt twocolumn ...   ... with class options appended
#
#   ./pipeline.sh ../main.tex                                  the root document
#   ./pipeline.sh ../main.tex --opt twocolumn                  ... as two columns
#
# MAIN is the document's top-level .tex file; the body is whatever it \input's.
# Per run this writes out/<label>/ -- the phrase list, the PDF, every engine's
# extraction, run.log and pipeline.json -- where <label> is MAIN's folder name
# (or MAIN's own name, if it is not a main.tex) plus any --opt, e.g.
# lucidcv+twocolumn.
#
# run.sh is the test stage and builds nothing; this is the entry point that
# makes sure the PDF and the phrase list it scores come from the same main.tex.
# See src/pipeline.py for the stages. Exits non-zero if any stage failed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The extractors live in the virtualenv setup.sh builds, not in the system
# Python; falling back to PATH keeps the suite usable where they were installed
# some other way, and the engines that are missing report as `not run'.
PY="$HERE/env/python/bin/python3"
[[ -x "$PY" ]] || PY="$(command -v python3 || true)"
[[ -n "$PY" ]] || { echo "pipeline.sh: no python3 -- run ./setup.sh" >&2; exit 1; }

export PYTHONIOENCODING=utf-8

exec "$PY" "$HERE/src/pipeline.py" "$@"

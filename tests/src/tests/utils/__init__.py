"""Helpers the checks share, grouped by what they read.

Author: Patrik Goldschmidt
Date: 2026-09-06

A check in the directory above answers one question about the document and
prints a verdict. Anything it needs on the way there that a second check would
also need lives here, named for the thing it reads rather than for the check
that first wanted it:

    utils.pdf   the PDF's own structures, through PyMuPDF

Kept apart from src/common.py, which the pipeline and the scorers import and
which is deliberately stdlib-only: these modules may depend on whatever their
subject needs. Nothing above src/tests/ imports from here.

Spelled as a real package rather than left implicit: src/ sits ahead of
src/tests/ on the path, so a namespace package of this name would silently
merge with a src/utils/ if one were ever added.
"""

#!/usr/bin/env python3
"""Score extracted text against the visible phrases of the document.

Author: Patrik Goldschmidt
Date: 2026-08-20, last rev. 2026-10-04

Reads the .txt files written by extract.py and reports, per engine, how many of
the document's phrases survived extraction. run.sh calls it as

    check.py OUTDIR VARIANT PHRASES

with the same three arguments it hands order.py. PHRASES is the list
pipeline.sh generated from the document that was built.

The VARIANT matters because several engines sort by absolute position, so what
they can recover depends on the layout the PDF was built in. Which engines each
variant excuses is COVERAGE_ADVISORY in common.py.

NO SCORES ARE RECORDED, deliberately. An engine either returns everything or it
does not. A remembered number only says what some earlier build happened to
score: it goes stale the moment the document changes. What is worth knowing --
that an engine is not held to the full count, and why -- is the membership of
the advisory table, not a number.
"""

import pathlib
import sys

# src/ is one directory up: these run as scripts, so the shared module is not
# on the path unless we put it there.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from common import (COVERAGE_ADVISORY, ENGINES, load_phrases, locate, norm,
                    read_extractions)


def score(texts, phrases):
    """{engine: [phrases it did not return]} for every engine that ran.

    A phrase listed n times has to be found n times, each at a place of its own
    -- see locate(). When an engine returns fewer, the later listings are the
    ones reported missing.
    """
    keys = [norm(p) for p in phrases]
    missing = {}

    for engine, text in texts.items():
        left = {k: len(at) for k, at in locate(text, phrases).items()}
        lost = []

        for p, k in zip(phrases, keys):
            if not k:
                continue

            if left.get(k):
                left[k] -= 1
            else:
                lost.append(p)

        missing[engine] = lost

    return missing


def main(outdir, variant, phrase_file):
    phrases = load_phrases(phrase_file)
    advisory = COVERAGE_ADVISORY[variant]
    out = pathlib.Path(outdir)
    total = len(phrases.all)
    missing = score(read_extractions(out), phrases.all)
    fails = {}

    if not missing:
        print(f"check.py: no extractions found in {out}/", file=sys.stderr)
        return 1

    # ---- The table ----------------------------------------------------------
    w = max(len(e) for e in ENGINES)
    print(f"{'ENGINE':<{w}}  {'FOUND':>7}  RESULT   ({variant})")

    for engine in ENGINES:
        if engine not in missing:
            print(f"{engine:<{w}}  {'-':>7}  not run")
            continue

        n = total - len(missing[engine])

        if engine in advisory:
            note = "advisory"
        elif n == total:
            note = "ALL INTACT"
        else:
            note = f"MISSING {len(missing[engine])}  <-- REGRESSION"
            fails[engine] = missing[engine]

        print(f"{engine:<{w}}  {n:>3}/{total:<3}  {note}")

    # ---- What each engine lost ----------------------------------------------
    for engine in ENGINES:
        if missing.get(engine):
            print(f"\n--- {engine} missing ---")

            for p in missing[engine]:
                print("   ", repr(p))

    # ---- The verdict ---------------------------------------------------------
    if fails:
        print(f"\nFAIL: {', '.join(sorted(fails))} lost phrases that geometry-based "
              f"extraction should preserve.")
        return 1

    print(f"\nPASS: every strict engine returned all {total} phrases.")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))

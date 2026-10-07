#!/usr/bin/env python3
"""How much of the document comes back in document ORDER, per engine.

Author: Patrik Goldschmidt
Date: 2026-08-23, last rev. 2026-10-04

check.py asks whether a phrase survived. That is the wrong question for a CV:
an engine can return every phrase and still hand a parser the dates under the
wrong employer. run.sh calls it with the same arguments as check.py:

    order.py OUTDIR VARIANT PHRASES

The reference order is the PDF's own content-stream order, taken from
poppler-raw, which does not re-sort. For each engine we list the phrase
occurrences it returns, in the order it returns them, and measure the longest
common subsequence with the reference's list: the share of the document that
arrives in the order it was written. 1.00 is perfect. Occurrences rather than
phrases, because a phrase may be listed more than once -- `Ph.D.' under two
projects -- and each listing is placed where it was found (see locate() in
common.py).

Because the reference IS the content stream, poppler-raw scores 1.00 by
construction, and an edit that scrambled the stream would move the target
rather than fail the test. It matches the body section for section today; a
declared order list would close that gap and has not been written.

HEADER vs BODY. The contact block is a bag of independent fields -- an e-mail
address means the same thing whether it comes before or after a phone number,
and the engines legitimately disagree about how to serialise a row of icons.
Those phrases are scored and printed but never failed on. The body is scored
STRICTLY: a CV whose Education dates arrive after
References is a CV the ATS mis-files, and that is worth a red build.

The split is taken from the phrase file's own section comments -- the group
under `# header / contact' is the advisory one -- so the two cannot drift.

Position-sorting engines are advisory in `twocolumn' only, where interleaving two
columns is what they are built to do. In `onecolumn' there is nothing to
interleave and they are held to 1.00 like everyone else. Tesseract reads pixels,
so its ceiling is what the page LOOKS like rather than what the text layer says;
it stays advisory everywhere. The sets are ORDER_ADVISORY in common.py.

Writes order.json beside the extractions, which is the machine-readable twin of
the table it prints.
"""

import collections
import json
import pathlib
import sys

# src/ is one directory up: these run as scripts, so the shared module is not
# on the path unless we put it there.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from common import (ENGINES, ORDER_ADVISORY, load_phrases, locate, norm,
                    read_extractions)


#: The engine whose output defines document order: it emits the content stream
#: without re-sorting, so it scores 1.00 by construction. See the docstring.
REFERENCE = "poppler-raw"


def sequence(located, keys):
    """The occurrences of `keys' in the order an extraction returns them."""
    return [k for _, k in sorted((at, k) for k in keys
                                 for at in located.get(k, ()))]


def lcs_length(a, b):
    """Longest common subsequence of two sequences, one row at a time."""
    row = [0] * (len(b) + 1)

    for x in a:
        diag = 0

        for j, y in enumerate(b, 1):
            diag, row[j] = row[j], (diag + 1 if x == y else max(row[j], row[j - 1]))

    return row[-1]


def fidelity(located, ref_seq, keys):
    """Per-engine {in_order, compared, fidelity} over one phrase group.

    `compared' is how many occurrences the engine and the reference both
    returned -- the most that could be in order -- and `in_order' how many of
    those arrive in the reference's sequence.
    """
    ref_count = collections.Counter(ref_seq)
    scores = {}

    for engine in ENGINES:
        if engine not in located:
            continue

        seq = sequence(located[engine], keys)
        compared = sum(min(n, ref_count[k])
                       for k, n in collections.Counter(seq).items())
        in_order = lcs_length(ref_seq, seq)
        scores[engine] = {
            "in_order": in_order,
            "compared": compared,
            "fidelity": round(in_order / compared, 4) if compared else None,
        }

    return scores


def main(outdir, variant, phrase_file):
    phrases = load_phrases(phrase_file)
    out = pathlib.Path(outdir)
    texts = read_extractions(out)

    if not texts:
        print(f"order.py: no extractions found in {out}/", file=sys.stderr)
        return 1

    if REFERENCE not in texts:
        print(f"order.py: no {REFERENCE}.txt in {out}/ -- it is the reference "
              f"order", file=sys.stderr)
        return 1

    advisory = ORDER_ADVISORY[variant]

    # ---- Reference order, then every engine against it ----------------------
    # Located over the WHOLE list, so a header phrase and a body phrase never
    # claim the same text; each group is then read out of that.
    located = {e: locate(text, phrases.all) for e, text in texts.items()}
    groups = {}

    for name, group in (("body", phrases.body), ("header", phrases.header)):
        keys = {norm(p) for p in group} - {""}
        groups[name] = fidelity(located, sequence(located[REFERENCE], keys), keys)

    # ---- The table ----------------------------------------------------------
    w = max(len(e) for e in groups["body"])
    print(f"{'ENGINE':<{w}}   BODY  IN ORDER / COMPARED   HEADER  RESULT  ({variant})")

    fails = {}

    for engine in ENGINES:
        if engine not in groups["body"]:
            continue

        b = groups["body"][engine]
        h = groups["header"].get(engine, {"fidelity": None})
        bf = b["fidelity"]
        hf = h["fidelity"]

        if engine in advisory:
            note = "advisory"
        elif bf is not None and bf < 1.0:
            note = "OUT OF ORDER  <-- REGRESSION"
            fails[engine] = bf
        else:
            note = "in order"

        print(f"{engine:<{w}}  {('n/a' if bf is None else f'{bf:.2f}'):>5}  "
              f"{b['in_order']:>8} / {b['compared']:<9} "
              f"{('n/a' if hf is None else f'{hf:.2f}'):>5}  {note}")

    print(f"\nBody = the file main.tex inputs, scored strictly. Header = the contact "
          f"block, reported only.")

    (out / "order.json").write_text(json.dumps(
        {"variant": variant, "reference": REFERENCE,
         "advisory": sorted(advisory),
         "body": groups["body"], "header": groups["header"]},
        indent=1), encoding="utf-8")

    # ---- The verdict ---------------------------------------------------------
    if fails:
        print(f"FAIL: {', '.join(sorted(fails))} returned the body out of "
              f"document order.")
        return 1

    print("PASS: every strict engine returned the body in document order.")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))

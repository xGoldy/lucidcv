#!/usr/bin/env python3
"""Report the whitespace character each engine returns between words.

Author: Patrik Goldschmidt
Date: 2026-08-22, last rev. 2026-10-04

check.py folds U+00A0, U+2009 and U+202F to a plain space before matching, which
is right for scoring phrases -- an extractor that returns a thin space has still
found the words. But it means the suite cannot tell a word gap that comes back as
U+0020 from one that comes back as U+00A0, and the difference matters:

    Java's \\s does not match U+00A0, and Character.isWhitespace('\\u00A0') is
    false, because it is a NO-BREAK space.

So a PDFBox- or Tika-based ATS splitting on \\s+ -- which is most of the JVM
document pipelines an ATS is built out of -- does NOT split there. A fix that
puts a literal U+00A0 into the text layer to defeat Ghostscript would look like a
pass here while quietly fusing the words for that whole family of parsers.

This reports, per engine, every non-U+0020 whitespace character returned between
two word characters, with the surrounding text. Nothing here fails a run: it is a
report, because whether a given separator is acceptable is a judgement about the
document, not a property of it.

run.sh calls it with the folder extract.py has just written:

    whitespace-report.py OUTDIR
"""

import pathlib
import sys

# src/ is one directory up: these run as scripts, so the shared module is not
# on the path unless we put it there.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from common import ENGINES

# Every whitespace codepoint an extractor might plausibly emit for a word gap.
# U+0020 is the one we want; the rest are reported. U+000A and U+000D are line
# structure rather than word gaps, so they are not interesting here.
INTERESTING = {
    " ": "NO-BREAK SPACE",
    " ": "EN QUAD",
    " ": "EM QUAD",
    " ": "EN SPACE",
    " ": "EM SPACE",
    " ": "THREE-PER-EM SPACE",
    " ": "FOUR-PER-EM SPACE",
    " ": "SIX-PER-EM SPACE",
    " ": "FIGURE SPACE",
    " ": "PUNCTUATION SPACE",
    " ": "THIN SPACE",
    " ": "HAIR SPACE",
    " ": "NARROW NO-BREAK SPACE",
    " ": "MEDIUM MATHEMATICAL SPACE",
    "　": "IDEOGRAPHIC SPACE",
    "​": "ZERO WIDTH SPACE",
    "﻿": "ZERO WIDTH NO-BREAK SPACE",
    "­": "SOFT HYPHEN",
    "\t": "TAB",
}

# Which of those a Java \s+ tokenizer would fail to split on. Character.isWhitespace
# is false for the no-break ones precisely because they are non-breaking, and \s in
# java.util.regex is only [ \t\n\x0B\f\r] -- so every space here except TAB is one a
# JVM-based parser reads as part of the word.
JAVA_FUSES = set(INTERESTING) - {"\t"}


def contexts(text, ch, width=28):
    """Yield the surrounding text for each occurrence of ch between word chars."""
    for i, c in enumerate(text):
        if c != ch:
            continue

        # Only interested where it is acting as a word gap, i.e. it has real text
        # either side. A separator at a line end is line structure, not fusion.
        # Indexed rather than sliced: `text[:i]' per occurrence copies the whole
        # extraction each time, which is quadratic on a document that has many.
        if i == 0 or not text[i - 1].isalnum():
            continue

        if i + 1 >= len(text) or not text[i + 1].isalnum():
            continue

        yield (text[max(0, i - width):i] + "␣"
               + text[i + 1:i + 1 + width]).replace("\n", " ")


def main(outdir):
    out = pathlib.Path(outdir)
    # The engines' own files only: the folder also holds pipeline.sh's
    # phrases.txt, which is the source text rather than an extraction.
    files = [out / f"{e}.txt" for e in ENGINES if (out / f"{e}.txt").exists()]

    if not files:
        print(f"whitespace-report.py: no extractions in {out}/", file=sys.stderr)
        return 1

    print(f"whitespace-report.py: {out}/\n")
    print("Word gaps that come back as something other than U+0020.")
    print("A gap marked JAVA-FUSES is one that java.util.regex \\s does not match, so a")
    print("PDFBox/Tika-based parser splitting on \\s+ reads the two words as one.\n")

    findings = {}

    for f in files:
        text = f.read_text(encoding="utf-8", errors="replace")
        hits = {}

        for ch, name in INTERESTING.items():
            found = list(contexts(text, ch))
            if found:
                hits[ch] = (name, found)

        findings[f.stem] = hits

    width = max(len(e) for e in findings)
    clean = []

    for engine, hits in findings.items():
        if not hits:
            clean.append(engine)
            continue

        print(f"--- {engine} ---")

        for ch, (name, found) in hits.items():
            flag = "  JAVA-FUSES" if ch in JAVA_FUSES else ""
            print(f"  U+{ord(ch):04X} {name} x{len(found)}{flag}")

            for ctx in found[:4]:
                print(f"      {ctx}")

            if len(found) > 4:
                print(f"      ... and {len(found) - 4} more")

        print()

    if clean:
        print(f"{'CLEAN':<{width}}  every word gap is U+0020:")
        for engine in clean:
            print(f"  {engine}")

    affected = [e for e, h in findings.items()
                if any(c in JAVA_FUSES for c in h)]

    if affected:
        print(f"\n{len(affected)} of {len(findings)} engines return a separator that a "
              f"JVM \\s+ tokenizer will not split on:")
        print(f"  {', '.join(affected)}")
        print("\nThis is a report, not a failure. But a word gap that only some engines")
        print("render as a real space is a gap that only some ATS pipelines will find.")
    else:
        print("\nEvery engine returns U+0020 for every word gap.")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

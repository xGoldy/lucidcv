# tests

Checks that a PDF built with the template in `../` still reads back the way a
resume has to: every phrase intact, in the right order, with real spaces between
the words, icons that extract as nothing, and a PDF/A claim the file actually
honors.

```sh
./setup.sh                    # once: builds env/ -- see Dependencies below
./setup.sh --no-system        # ... without the system packages, so without root

./pipeline.sh ../main.tex                               # the root document
./pipeline.sh ../main.tex --opt twocolumn
                              # ... with a class option appended for this run
```

`pipeline.sh` exits non-zero if anything regressed, so it drops straight into a
check before you send the resume, or into a CI step.

## Running — `./pipeline.sh MAIN`

`MAIN` is the document's top-level `.tex` file: usually the template root's
`main.tex`, but a `main.tex` in its own subfolder of the template (e.g., a copy
tailored to one job offer) works too. The body is whatever that file `\input`s,
resolved from its own folder, so a new document needs no registration anywhere.
Per run, in order:

| | Stage | |
| --- | --- | --- |
| 1 | phrases | `init-phrases.py MAIN` → `out/<label>/phrases.txt` |
| 2 | build | `../build.sh MAIN` → `out/<label>/<label>.pdf` |
| 3 | score | `run.sh` that PDF against that list, under the variant the class options name |
| 4 | report | `out/<label>/pipeline.json` and `out/<label>/run.log` |

**The PDF and the list always come from the same `main.tex`.** That is the
point of the pipeline. A score is only meaningful against the list generated
from the document that was built: a one-page body was once scored against a
two-page body's list and came back **32 phrases short in all twelve strict
engines at once** — not one of which the document ever held. Twelve engines
failing identically is the signature of a wrong fixture rather than a
regression, because a real extraction fault varies by engine. Generating the
list on every run from the file being built is what rules that out.

**`<label>`** is the name of `MAIN`'s folder when `MAIN` is a `main.tex` — the
template's own folder name for the root (`lucidcv` in a default checkout), the
subfolder's name otherwise — and `MAIN`'s own name without `.tex` for any
other file, with any `--opt` appended: `lucidcv+twocolumn`. Everything the run
produced lands in `out/<label>/`, which is cleared first so no stale extraction,
PDF or list can survive into a new run. The PDF is built there too rather than
beside the sources: the `resume.pdf` in the template tree is the one that
ships, and an `--opt` build is not one of them.

**The variant** — `onecolumn`, `twocolumn`, either with `-compr` — decides which
engines are held strictly; see *Engines* below. It is read from the
`\documentclass` option list with any `--opt` appended, last-wins, exactly as
the class reads it: `--opt twocolumn` on a `onecolumn` document builds and
scores as `twocolumn`, and `compressed=false` counts as a plain build.

**The build** runs `build.sh` with the source folder and then the template root
on `TEXINPUTS`, and `fonts/` on `TTFONTS`, so a `main.tex` in a subfolder
still finds the class and its fonts. `--opt` is handed straight to `build.sh`, which
appends it to the `\documentclass` list for that build without touching the file.

**Covering the layouts.** Each of the class's four layout and density
combinations is one `--opt` away from any document, and is scored against that
document's own freshly generated list.

```sh
./pipeline.sh ../main.tex                                  # onecolumn
./pipeline.sh ../main.tex --opt compressed                 # onecolumn-compr
./pipeline.sh ../main.tex --opt twocolumn                  # twocolumn
./pipeline.sh ../main.tex --opt twocolumn --opt compressed # twocolumn-compr
```

`pipeline.json` holds every figure the run produced — options, variant, page
and phrase counts, each gate's verdict (`pass`, `fail`, `skipped` or `report`),
per-engine coverage and `order.py`'s scores — as the raw material for a
report. The latest published report is
[`../resources/report.html`](../resources/report.html).

## The test stage — `./run.sh`

`run.sh` builds nothing and generates nothing. It runs every check on the PDF
it is handed, against the phrase list it is handed, and writes the extractions
to `out/<label>`:

```sh
./run.sh <pdf> <variant> [label] --phrases=FILE
```

**Every argument but the label is required**, and none has a default. The
variant has to be one of `onecolumn`, `onecolumn-compr`, `twocolumn` or
`twocolumn-compr`; the label defaults to the variant. A default PDF scores
whichever build happens to be lying around — which is how a stale one once
earned a green run, after the class had moved its `\cvtaglist` delimiter to an
en dash while the built PDF still carried the old bullet. A
default list scores it against whichever document that list was generated from.
`pipeline.sh` supplies both from one `main.tex`; call `run.sh` directly only to
re-score a PDF and list you already have, such as a finished run's:

```sh
./run.sh out/lucidcv/lucidcv.pdf onecolumn lucidcv --phrases=out/lucidcv/phrases.txt
```

`run.sh` is where the checks are listed, and the only place: `pipeline.sh` runs
them through it, so a check added to `run.sh` is picked up without an edit.

## What is checked

Seven checks fail the run, in the order `run.sh` runs them. An eighth reports.

A check that cannot run on this machine — `subset-glyphs.py`, `icon-check.py`,
`metadata-check.py` and `hidden-text-check.py` need PyMuPDF from `env/python` —
prints `SKIP:` instead of a verdict. The run
does not fail on it, but `pipeline.json` records the gate as `skipped` and the
summary line names it, so a missing dependency never passes for a clean result.
`pdfa-check.py` runs without PyMuPDF and skips only its font-embedding check.

### `src/tests/subset-glyphs.py` — real word spaces

A property of the PDF alone, independent of its content, so it is the stable
guard. TeX turns an interword space into *glue*, and glue is a positioning
instruction, not a character — so by default nothing in the file says where a
word ends and every extractor has to guess. Ghostscript guesses per **glyph
pair** rather than by width, which is why `Some fancy` used to come back as
`Somefancy` at exactly the gap width 175 other pairs survived.

LuaLaTeX with `\DocumentMetadata{tagging=on}` emits a real space glyph and
shrinks the following offset to compensate:

```text
before:  <029402640345>      -261 <01F80246...>
after:   <0294026403450692>   -12 <01F80246...>
```

The check counts space glyphs actually drawn on the pages, not merely present in
the subsets — a font can carry the glyph while the pages still fall back to bare
offsets, which is exactly what happens if `\DocumentMetadata` is missing. The
class warns about that in the log (and refuses any engine but LuaLaTeX
outright), but a warning is easy to miss, and the PDF looks perfect while it
reads back with the words run together. This check turns it into a failed run.

### `src/tests/icon-check.py` — icons extract as whitespace

An icon is decoration and must not reach a parser as a word. The class defends
this twice, and it needs both: an empty `accsupp` ActualText around every icon,
which poppler, PDFBox and Tika honor and pdfium, pdf.js and Ghostscript
*ignore*; and a `ToUnicode` entry mapping every icon glyph to U+0020, which is
what those three fall back to.

The second is the one that is easy to lose. luaotfload writes a `ToUnicode`
entry of its own, but it spells the glyph's **name**, so a contact line extracts
as `Envelope Address, Street` and a referee as `EnvelopeAddress` once a parser
closes the gap. The class overrides it at font-load time with a `\directlua`
callback; this check fails the build if that override stops working.

`check.py` cannot catch this. It asks whether the listed phrases are *present*,
never whether anything else crept in.

### `src/tests/pdfa-check.py` — the PDF really is PDF/A-2B

`\DocumentMetadata{pdfstandard=A-2b}` stamps the PDF/A identification into the
XMP whether or not the file that comes out conforms, so the claim needs checking
independently of itself. The engine does notice a breach —

```text
Package pdf Warning: PDF standard validation failure.
(pdf)                Embedded non-PDF files detected.
(pdf)                This is not allowed in standard pdf/A-2B
```

— but reports it only in the `.log`, where it went unread while `../build.sh`
deleted the log after every successful build. `build.sh` now prints the log's warnings
and keeps the log when there are any, but a printed warning still lets the build
succeed; this check is the one that fails the run.

The breach it was written for is real and was live in this repo: LaTeX's list
and align tagging attaches `latex-list-css.html` and `latex-align-css.html` as
associated files, and PDF/A-2 permits embedding only PDF/A-1 or PDF/A-2 files.
`lucidcv.cls` suppresses them with `\tagpdfsetup{attach-css=false}`.

It checks the rules this document can plausibly break — the `pdfaid` part and
conformance level, no non-PDF attachment, an `OutputIntent` with a destination
profile, every font embedded, no encryption, and none of the actions PDF/A
forbids.

Those checks approximate the standard, so the script also runs **veraPDF** when
it can find one. veraPDF is the reference implementation of ISO 19005 — it
decides the question outright rather than approximating it, and it names the
clause behind a failure, which the built-in checks cannot:

```text
veraPDF                FAIL  ISO 19005-2 clause 6.8 test 5
```

That is the EF-key rule — *"a file specification dictionary may contain the EF
key, provided that the embedded file is compliant with either ISO 19005-1 or
this part of ISO 19005"* — the exact rule the latex-lab CSS attachments broke.
Both checkers agree in both directions: they pass the sample in all four
variants (`onecolumn`, `twocolumn`, each with and without `compressed`), and
both fail a PDF built with the `attach-css=false` hook removed.

`./setup.sh` installs it into `env/verapdf/vendor/`, the same
delete-the-directory-to-undo arrangement as the JVM extractors. It needs a
`java` on PATH, 11 or newer. To install it somewhere else, which a full root
filesystem can force, run `setup.sh` with `VERAPDF_PREFIX=<dir>`.
`pdfa-check.py` looks in `$VERAPDF`, then `env/verapdf/vendor/`, then on
`PATH`, so set `VERAPDF=<dir>/verapdf` (the executable, not the folder) when
you run the suite. Without veraPDF the built-in checks still run and still fail
the build — they just cannot cite chapter and verse, and the run says so.

### `src/tests/metadata-check.py` — the metadata reached the XMP

A PDF carries its title, author, subject and keywords twice: in the Info
dictionary and in the XMP metadata stream. PDF/A and PDF/UA read the XMP —
PDF/UA-1 7.1-9 requires a `dc:title` there — while `pdfinfo` and most viewers'
property dialogs read the Info dictionary, so a gap between the two stays
invisible.

The gap it was written for was live in this repo. The class set the metadata
in the `enddocument` hook, but the XMP packet is built when the last page ships,
and in `twocolumn` `\end{paracol}` ships it before `\end{document}`. The Info
dictionary was complete; the XMP had no title, author, subject or keywords.
`lucidcv.cls` now sets them in `shipout/firstpage`, which the kernel runs ahead
of `shipout/lastpage` in every layout — this check is what would notice if that
ever stopped holding.

It checks properties of any build, not values copied from `main.tex`:

```text
  XMP packet             present
  dc:title               Adrian Castellanos -- Curriculum Vitae
  dc:creator             Adrian Castellanos
  dc:description         Senior Software Engineer
  dc:subject             curriculum vitae; resume; software engineer; ...
  dc:language            en-US  (catalog /Lang en-US)
  DisplayDocTitle        true
```

* `dc:title` is present and non-empty.
* Every field set in the Info dictionary is in the XMP with the same value:
  Title as `dc:title`, Author as `dc:creator`, Subject as `dc:description`, and
  Keywords, split at the commas, as the items of `dc:subject`.
* `dc:language` agrees with the catalog's `/Lang`.
* `/ViewerPreferences` has `/DisplayDocTitle true`, so a viewer's title bar
  shows the title rather than the file name (PDF/UA-1 7.1-10).

It fails the `twocolumn` build from before the fix on all four fields, and a
build with `pdfdisplaydoctitle` dropped from the class on the last check.

### `src/tests/hidden-text-check.py` — no text a reader cannot see

Hidden text is how keyword stuffing is done — white words on a white page, 2pt
type, text pushed off the page or stacked under other text — and screening
tools that look for it flag the whole document, not just the words. The class
does put invisible glyphs into the PDF, but only whitespace: tagging turns every
word gap into a real U+0020, the header carries U+00A0s, and the entry separator
gets tagpdf's `\pdffakespace` on each side. This check keeps it that way —
whitespace may be invisible, nothing else may:

```text
  characters             5911, 730 of them whitespace (allowed to be invisible)
  faintest text          1.51:1 against white (limit 1.25:1)
  invisible              none
  faint                  none
  transparent            none
  tiny                   none
  off-page               none
  stacked                none
  under an image         none
```

It fails on any character other than whitespace that is drawn in render mode 3
(invisible), in a colour under 1.25:1 contrast against white, at under 0.25
opacity, under 4pt, with its origin off the page, over more than half of another
visible glyph, or inside the visible area of an image. The limits sit well
below the class's own extremes: its faintest text is the date leader's light
grey dots at 1.51:1, and its smallest is 8pt.

An image's visible area is its placement cut to the smallest clip lying mostly
on it, because the header photo is a rectangle clipped to a circle, and in
`twocolumn` + `compressed` the right column's first heading sits under the
hidden part of that rectangle. PyMuPDF reports a clip by its bounding box, so a
circle counts as its square. Text hidden by a clipping path, or under a vector
shape filled after it, is not detected; the class draws neither over text.

A test document carrying one of each trick beside a clean control line fails on
all seven, with exactly the hidden characters counted and none of the control.

### `src/tests/check.py` — did the phrase survive at all

Every visible phrase in `main.tex` and the body it inputs, generated by
`src/init-phrases.py`, looked for in each engine's output after
folding away dashes, quotes, ligatures, whitespace and case.
`src/extract.py` writes the per-engine `.txt` it reads; see *Engines* below for
what each one is.

**Every listing is its own occurrence.** Both scorers find phrases through
`locate()` in `src/common.py`, which gives each listing a separate place in the
extraction:

* **Repeats count.** A phrase listed three times — a location under three jobs —
  has to be found three times. When an engine returns fewer, the later listings
  are the ones reported missing.
* **A phrase inside a longer one is not found for free.** Phrases claim text
  longest first, and a match may not overlap text a longer phrase already
  claimed. The heading `Experience` is only found where it stands on its own, not
  inside `R&D experience`; the tagline is only found in the header, not inside the
  About paragraph that opens with it.
* **Matches sit on word boundaries.** Where a phrase starts or ends with a letter
  or digit, the match cannot be glued to another one, so `BUT` is not found inside
  `distributed`.

This is what lets the phrase list keep every repeat and every phrase contained
in a longer one. A plain first-occurrence search would score a short phrase
inside the longer one or at the wrong copy, and dropping those phrases instead
would leave real text — a header location, section headings, repeated degree
lines — untested.

The `\cvtaglist` line is emitted as the whole rendered string, delimiters
included (`C++ – Embedded Systems – Statistical Analysis`), because its three
items on their own would each collide with the Skills paragraph. The delimiter
is the one place the generator has to know the class: if you change
`\cvtaglistmark`, change the `mark` default in `render_taglist()` to match.

### `src/tests/order.py` — did it come back in the right sequence

`check.py` asks whether a phrase is *present*, never where it landed, so a
document can pass it with every phrase intact and still hand a parser the fields
in the wrong sequence.

The reference order is the PDF's own content-stream order, from `poppler-raw`,
which does not re-sort. Each engine's matches, in the order it returns them,
are compared with the reference's by longest common subsequence — the share of
the document that arrives in the order it was written. It compares occurrences
rather than distinct phrases, so a phrase listed twice is placed twice. 1.00 is
the document's order; on the two-column sample (`2c1p`), the engines that sort
by position score between 0.71 and 0.86.

One caveat worth knowing: because the reference *is* the content stream,
`poppler-raw` scores 1.00 by construction, and an edit that scrambled the stream
would move the target rather than fail the test. Today the content stream
follows the body section by section. A declared order list, cross-checked
against `poppler-raw`, would close that gap and has not been written.

It scores the **body and the header separately**, and the split is taken from
the phrase file's own section comments — the group under `# header / contact` is
the header — so the two cannot drift apart from the list they describe.

* **Body** (the file `main.tex` inputs) is **strict and fails the run.** A CV
  whose Education dates come back after References is one the ATS mis-files,
  and that is worth a red build.
* **Header** (the contact block) is **reported only.** An email
  address means the same thing before or after a phone number, and the engines
  legitimately disagree about how to serialize a row of icons.

```text
ENGINE            BODY  IN ORDER / COMPARED   HEADER  RESULT  (twocolumn)
poppler-raw       1.00        65 / 65           1.00  in order
```

A drop in an engine that normally reports 1.00 is the signal worth acting on.
One known trigger: dropping the `photo` class option lets the contact block span
the full text width, and once it wraps to two rows poppler returns the contact
fields interleaved — see *Name and photo* in
[`../resources/docs.md`](../resources/docs.md#name-and-photo).

### `src/tests/whitespace-report.py` — which character the gap is (reports only)

Reports, per engine, any word gap returned as something other than U+0020. A
literal U+00A0 is the one that matters: `java.util.regex`'s `\s` does not match
it and `Character.isWhitespace` is false for it, so a PDFBox- or Tika-based ATS
would not split there — and a fix that put a U+00A0 into the text layer to
defeat Ghostscript would look like a pass everywhere else while quietly fusing
the words for that whole family of parsers.

It reports rather than fails, because whether a given separator is acceptable is
a judgment about the document rather than a property of it.

## Engines

`extract.py` runs every extractor it can find on the machine and writes one
`<engine>.txt` per engine. A missing engine is skipped with a note, never
failed on — none of them is a hard dependency. The engines are independent, so
the external ones run concurrently and Tesseract reads the pages concurrently;
the three Python libraries run in the main process, one after another.

There are 9 extraction engines, run in 13 configurations. Throughout this file,
"engine" means one configuration, as named in the first column:

| Engine | Is |
| --- | --- |
| `poppler` | `pdftotext`, default mode — widely used in Linux tooling (Okular, for one) and PDF-processing pipelines |
| `poppler-raw` | the same, in content-stream order |
| `poppler-layout` | the same, preserving the physical page layout |
| `mupdf` | PyMuPDF, an independent implementation |
| `pdfium` | pypdfium2 — the engine of Chromium-based browsers |
| `pdfminer` | pdfminer.six — a Python library commonly used in custom document-processing pipelines |
| `ghostscript` | `txtwrite`, the strictest word-gap heuristic of the set |
| `pdfjs-old` | pdf.js 2.5.207, representative of older pdf.js integrations |
| `pdfjs-new` | current pdf.js, as used by Firefox (pinned by `setup.sh`, currently 4.10.38) |
| `pdfbox` | Apache PDFBox, default mode — widely used in Java-based document-processing pipelines |
| `pdfbox-sorted` | the same, in position-sorting mode (`-sort`) |
| `tika` | Apache Tika — delegates PDFs to PDFBox, so this checks Tika's *defaults*, not a second implementation |
| `tesseract` | OCR of the rendered pages — what an ATS falls back to when the text layer is unavailable or unusable |

Commercial resume parsers (Textkernel/Sovren, Daxtra, HireAbility, etc.) are
proprietary, and their PDF-processing pipelines cannot be reproduced locally, so
the suite **does not guarantee compatibility with any particular commercial
ATS**. Every parser, however, has to get the text out of the PDF before it can
analyze it. Consistent extraction across these 13 configurations, OCR included,
is evidence that the PDF's content is robustly machine-readable, and a useful
indication that other extractors will read it correctly too — most strongly for
one-column builds, which every text-layer engine returns completely and in order.

### Strict and advisory

A **strict** engine must return everything — all phrases, in order — and a drop
fails the run. An **advisory** engine is reported and never failed on.
Strictness is *derived*, not listed: an engine is advisory exactly when
`COVERAGE_ADVISORY` (for `check.py`) or `ORDER_ADVISORY` (for `order.py`) in
`src/common.py` names it for that variant. Both tables live there, side by side,
with the reasoning for each.

**The suite stores no expected scores, deliberately.** An engine either returns
everything or it does not. A remembered number only says what some earlier
build happened to score: it goes stale the moment the document changes, and a
figure measured against one body ends up printed beside another. What is worth
knowing — that an engine is not held to the full count, and why — is the
membership, not a number. The figures quoted in this file illustrate the
reasons; nothing is compared against them.

Three things put an engine on those tables, and none of them is a defect in the
PDF:

* **Tesseract reads pixels**, not the text layer, so its misses are a fact about
  the typography rather than the encoding. It is advisory everywhere; see
  *Tesseract* below.
* **Two columns split phrases.** `poppler-layout`, `ghostscript` and
  `pdfbox-sorted` lay the columns side by side on one physical line, so every
  phrase that wraps gets the other column spliced into the middle of it. Chasing
  that means giving up the layout. In `onecolumn` there is nothing to interleave
  and all three reach the full count, so they are held strictly there — that is
  the whole point of the option.
* **Two columns reorder phrases.** Every engine that rebuilds reading order from
  geometry interleaves the columns somewhere, and its order score moves whenever
  content moves. That covers the three above, `poppler`, which sorts by
  position, and `pdfminer`, which runs LAParams over the page and began emitting
  the whole Publications block after References once an edit moved the column
  heights.

Coverage and order are judged separately, because an engine can be reliable
about one and not the other. For `twocolumn`:

| Engine | Coverage | Order |
| --- | --- | --- |
| `poppler` | **strict** | advisory |
| `poppler-raw` | **strict** | **strict** |
| `poppler-layout` | advisory | advisory |
| `mupdf` | **strict** | **strict** |
| `pdfium` | **strict** | **strict** |
| `pdfminer` | **strict** | advisory |
| `ghostscript` | advisory | advisory |
| `pdfjs-old` | **strict** | **strict** |
| `pdfjs-new` | **strict** | **strict** |
| `pdfbox` | **strict** | **strict** |
| `pdfbox-sorted` | advisory | advisory |
| `tika` | **strict** | **strict** |
| `tesseract` | advisory | advisory |

`poppler` and `pdfjs-old` also sort by position, but both measurably return the
full count in two columns, so they are strict on **coverage** there; only
`poppler`'s reading *order* suffers. `pdfminer` likewise recovers every phrase,
so it is strict on coverage and advisory on order. In `onecolumn` every engine
except `tesseract` is strict on both counts. The two `-compr` variants carry the
same sets as their plain twins.

**Ghostscript used to fail in both layouts.** Before the move to LuaLaTeX it
lost five more phrases to word-gap fusion, which no layout could fix and no
`WordSpace` value could reach. Now that word gaps are real space characters, it
loses phrases only to two-column interleaving, like `poppler-layout` and
`pdfbox-sorted`, and `onecolumn` recovers all of them. See *Ghostscript and word
spacing* in
[`../resources/docs.md`](../resources/docs.md#ghostscript-and-word-spacing).

### Tesseract

`tesseract` never reads the text layer. It renders each page at 300 dpi and
reads the pixels back, which is the path an ATS takes when it decides a PDF has
no usable text — so its score measures the typography rather than the PDF's
text encoding. It is advisory for two reasons: it does not recover every
phrase, and which phrases it misses is not stable.

On the `generic_research-1c2p` body it returns 79 of 91, and every miss is an
OCR character error, none of them in the text layer:

| Cause | Phrases |
| --- | --- |
| `AI` read as `Al` — Inter's capital I and lowercase l are the same shape | 6 |
| diacritics dropped (`Chudá`, `Kučera`) — only the `eng` language pack is installed | 4 |
| the Scholar URL, `9_uI59AAAAAJ`, its capital I read as `l` | 1 |
| a stray character (`model` read as `modell`) — Inter Light's thin stroke | 1 |

Folding accents on both sides of the comparison would recover the diacritic
misses; nothing does that today, and it would change what the suite counts
rather than what an ATS sees.

**Inter's alternate glyphs are not a fix.** The `AI`/`Al` confusion can be
removed at the font: on an earlier, 80-phrase body, `RawFeature={+cv08}`
(serifed capital I) or `+ss02` (disambiguation set) took a 300 dpi run from 71
to 74. But the alternate glyph has no usable `ToUnicode` entry, so the text
layer breaks — `cv08` turns `AI` into `A�` and dropped all twelve text-layer
engines to 56/80, `ss02` to 39/80. That trades the fallback path for the one
nearly every ATS reads. `+cv05` (tailed l) changed nothing. A `ToUnicode` remap
of the alternates, in the manner of the icon override, might close that; it has
not been tried.

The misses also move with resolution. On that earlier body the same build scored
72, 71, 70 and 71 at 200, 300, 400 and 600 dpi, with different phrases failing
at each, and the one glyph that used to fail read three different ways across
the four. Treat any future dip as noise until a second resolution agrees.

Setting the skills line with `\cvtaglist` used to cost exactly one phrase here,
when the delimiter was a `\textbullet` that OCR read as `«`. It is an en dash
now, which Tesseract returns as an em dash — the same character after `norm()`
folds dashes — so the chip line comes back intact. See *Chips* in
[`../resources/docs.md`](../resources/docs.md#chips)
for the sixteen marks that were measured: every round one fails, every stroke
survives.

## The directory

```text
tests/
  pipeline.sh               the entry point: phrases, build, run.sh, report
  run.sh                    the test stage; every check is reached through it
  setup.sh                  builds env/ from nothing; the only script that installs
  README.md                 this file
  src/
    common.py               what the checks must agree on: the engine list,
                            the variants and both advisory tables, norm(),
                            locate(), the phrase-file parser and the
                            extraction reader, plus the out/ and env/ paths
    extract.py              runs every engine on one PDF -> out/<label>/<engine>.txt
    init-phrases.py         reads the .tex and writes the phrase list
    pipeline.py             the four stages for one MAIN; run.sh does the
                            checking, this decides what it is handed
    tests/                  one file per check; run.sh runs all eight in order
      subset-glyphs.py      word gaps are real space characters
      icon-check.py         icon glyphs extract as U+0020
      pdfa-check.py         the PDF/A-2B claim holds; veraPDF decides when installed
      metadata-check.py     title, author, subject, keywords reached the XMP
      hidden-text-check.py  no invisible text other than whitespace
      check.py              coverage — did the phrase survive, strict vs advisory
      order.py              reading order — did it survive *in sequence*; body
                            strict, header reported only
      whitespace-report.py  which whitespace character each engine returns (report)
      utils/
        pdf.py              PDF structures the checks read, through PyMuPDF
  env/                      built by setup.sh, ignored by git, disposable
    python/                 virtualenv holding PyMuPDF, pypdfium2, pdfminer.six
    pdfjs/vendor/           a Node runtime and both pdf.js builds
    pdfjs/extract-*.{cjs,mjs}  the two drivers, written out by setup.sh
    java/vendor/            the PDFBox and Tika jars
    verapdf/vendor/         the veraPDF validator
  out/
    <label>/                one run of pipeline.sh: <label>.pdf, phrases.txt,
                            one .txt per engine, order.json, run.log and
                            pipeline.json, every figure the run produced
```

Nothing under `env/` is tracked, because `setup.sh` reconstructs all of it —
the two pdf.js driver scripts included, which is why they are written from
heredocs in that script rather than kept as files. Delete `env/` and re-run
`./setup.sh` to repair it; delete one engine's directory and only that engine
goes, reported as *not run* rather than failing the suite.

`pipeline.sh` and `run.sh` use `env/python/bin/python3` when it exists and the
`python3` on `PATH` otherwise. The scripts under `src/` are internals: they are
only ever run through `run.sh` and `pipeline.sh`, which hand them every argument
they need, so they do not validate their arguments themselves.

`src/tests/` holds one file per check and nothing else; adding a check is adding
a file there and a line to `run.sh`. Anything more than one check needs on the way
to its verdict goes in `src/tests/utils/`, named for the thing it reads rather than for
the check that first wanted it — `utils.pdf` is the PDF's own structures, read
through PyMuPDF. Everything in `src/` above them is machinery the whole suite is
built out of: `common.py` earns its place there by being imported from both
levels, where nothing in `utils/` has a caller outside `src/tests/`.

The checks that import `common` put `src/` on their own path first, since they
run as scripts from `src/tests/`.

`src/common.py` owns the suite's paths — `out/` and `env/` — and
`src/pipeline.py` takes the template root to be the folder `tests/` sits in, so
no path names the template's folder. `common.py` stays stdlib-only, which is
why the PyMuPDF helpers the PDF checks share sit in `src/tests/utils/pdf.py`
instead.

`run.sh` hands the two scorers the same three arguments, in the same order:

```text
check.py OUTDIR VARIANT PHRASES
order.py OUTDIR VARIANT PHRASES
```

`out/<label>/` is the first place to look when a phrase goes missing: it holds
verbatim what each engine returned. The latest published report is
[`../resources/report.html`](../resources/report.html).

## Maintenance

### The phrase list is generated

The phrase list is what every score is measured against, and `pipeline.sh`
writes it afresh on every run, from the `main.tex` it is about to build, into
`out/<label>/phrases.txt`. There is no list in force to keep up to date and none
to forget: edit the text, re-run the pipeline, and the list follows.

`src/init-phrases.py` is the same generator on its own, for looking at a list
without building anything. It needs nothing from `env/`, so any `python3` runs
it:

```sh
# to stdout, so you can look before you leap
./src/init-phrases.py ../main.tex
# ... diffed against the list the last run scored
./src/init-phrases.py ../main.tex \
    | diff out/lucidcv/phrases.txt -
```

Nothing is written unless `--out=FILE` names a target. Progress goes to stderr,
so a redirected stdout holds the list and nothing else. It reads `\name` or
`\fullname`, `\tagline` and the `\cvpersonalinfo` fields from `main.tex`, with each built-in
field's shown prefix taken from `lucidcv.cls`, found beside `main.tex` or in a
folder above it; every `\cvsection`, `\cvsubsection`, `\cventry`, `\cvsubentry`,
`\cvref`, `\cvtag` and `\cvtaglist` from the body — the file `main.tex`
`\input`s, resolved from its own folder (name other files after `main.tex` to
read those instead) — plus the items and running paragraphs between them; and
the title of every entry in the `.bib`, because `\printbibliography` draws those
and nothing in the `.tex` names them.

It reads the **sources, not the built PDF**, and that is deliberate. Deriving
the list from the PDF's own text layer would make the whole suite tautological:
a heading the class silently failed to draw would never enter the list, so
nothing would ever miss it. The `.tex` says what the document is supposed to
say; the PDF is the thing under test.

**Nothing is dropped**, and that decides what gets scored. Repeats and phrases
contained in longer ones stay in the list, in source order; the scorers give
each its own occurrence (see *check.py* above). Only a phrase that folds to
nothing is left out.

It approximates what LaTeX will draw rather than rendering it, so it tracks the
class's own macros and the TeX spellings the sample uses, not arbitrary ones.
After regenerating, **run the suite** — a phrase it got wrong shows up as every
engine losing exactly that one. Nothing has to be re-measured afterwards: the
suite stores no expected scores, so a list that changes length changes the denominator
and nothing else.

The file's `#` lines are load-bearing in one place — the section named
`header / contact` is the group `src/tests/order.py` reports without failing
on. Every other `#` line is a plain comment.

### The education dates

The bodies leave the education entries at the `\cventry` default, so their
dates stack under the title, except under `compressed`, which sets `\cventry`
to `oneline` and puts the date on the title line. Pass `[oneline=false]` to keep
them stacked under `compressed` too.

An earlier revision of this file argued for always stacking them, because
Tesseract read a one-line date's capitals as lowercase and cost three phrases.
**That no longer reproduces** at 300 dpi against the LuaLaTeX build. Do not
re-derive the argument from the old numbers, which were taken under the XeLaTeX
pipeline, where every advisory score was different.

### Dependencies

`./setup.sh` installs everything, in five stages:

| Stage | Gets | Needs root |
| --- | --- | --- |
| system | poppler, Ghostscript, Tesseract, a JRE, and the `curl`/`unzip`/`xz`/venv tooling the rest of the script uses — through `apt-get` on Debian-family distributions (`poppler-utils`, `ghostscript`, `tesseract-ocr`, `default-jre`, …) or `dnf` on Fedora-family ones (`poppler-utils`, `ghostscript`, `tesseract`, `java-latest-openjdk-headless`, …), picked from `/etc/os-release` | yes — via `sudo`, or skip it with `--no-system` |
| venv | `env/python/`, with PyMuPDF, pypdfium2 and pdfminer.six pip-installed into it | no |
| pdfjs | a Node runtime, both pdf.js builds, and the two driver scripts | no |
| java | the PDFBox and Tika jars | no |
| verapdf | the reference PDF/A validator | no |

Every stage is idempotent — it skips what is already there — and every stage is
optional. Skip one and the engines it provides report as *not run* rather than
failing anything. `--no-system` on a machine without the system packages still
gets you five of the thirteen engines (`mupdf`, `pdfium`, `pdfminer` and both
pdf.js builds): the poppler, Ghostscript and Tesseract engines need their
packages, and PDFBox, Tika and veraPDF need the Java runtime. Everything
`setup.sh` downloads is pinned — Node, both pdf.js builds, the jars, veraPDF and
the three Python packages — so a run compares like with like across machines;
the system packages are whatever the distribution ships.

The virtualenv is deliberately the suite's own rather than whatever Python
happens to be active — these three extractors are a test dependency, and a
setup script that installs into someone's working environment is one that
breaks an unrelated project.

What `setup.sh` does **not** install is the TeX toolchain. `pipeline.sh` builds,
so it needs **LuaLaTeX** with a LaTeX format of 2026-06-01 or newer (TeX Live
2026 with current updates) and `biber` — newer than what most distributions
package.
`../build.sh` looks for `lualatex` in `.texenv/bin/*` beside the script first,
then `~/texlive/*/bin/*` and `/usr/local/texlive/*/bin/*` (newest year first
within each), and `PATH` last, so a TeX Live installed by `install-tl`, with or
without root, is found automatically.

The full story behind all of this is in *ATS and accessibility notes* in
[`../resources/docs.md`](../resources/docs.md#ats-and-accessibility-notes).

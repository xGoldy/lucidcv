# Lucid CV — class reference

Reference documentation for `lucidcv.cls`: its options, macros, defaults, and the ATS/accessibility reasoning behind each design choice. The shorter `README.md` at the project root covers ordinary use; this one is the manual for adapting the class, and records *why* things are the way they are so a change does not quietly undo a measured result.

Every number below comes from the extraction harness in `tests/`, which reads the compiled PDF back with 9 extraction engines in 13 configurations.

The class is self-contained: `main.tex` and `contents.tex` hold the content, `lucidcv.cls` and `fonts/` are the engine, `build.sh` builds the document, and nothing outside this directory is required.

`lucidcv.cls` takes its color palette and font pairing from [PlushCV](https://github.com/cystema/PlushCV). The entry system, the header and photo layout, the two-column split and the accessibility engineering are the class's own — see *Origins* and *Licenses*.

**The driving design goal is that the compiled PDF should read back correctly** when a text extractor or ATS parses it, not just look right on screen. That constraint shaped most of the class: it is why the engine is fixed to LuaLaTeX, why icons carry no ActualText labels, and why `\cvtag` rewrites its own argument. See *ATS and accessibility notes*.

## Compiling

**LuaLaTeX only.** Two independent reasons, neither with a workaround:

* the fonts are `.ttf` files in `fonts/`, loaded through `fontspec`, which rules out pdfLaTeX;
* word gaps have to be *real space characters*, and the tagging that produces them is LuaTeX-only. Under XeLaTeX every gap is a positioning instruction each extractor has to guess about, and Ghostscript guesses wrong on some glyph pairs — see *Ghostscript and word spacing*.

The class raises a `\ClassError` under any other engine rather than quietly producing a résumé whose words run together when a parser reads it.

**Kernel floor: `2026-06-01`.** `\NeedsTeXFormat{LaTeX2e}[2026-06-01]` *warns* on an older format rather than stopping the build, so that warning is the only notice you get. The floor is not about syntax — every command the class calls is years older than that — it is the *tagged list* code. Under `tagging=on`, LaTeX's list implementation ignores the `topsep` that `\setlist` sets, so the class scales each list's closing skip from the `env/itemize/after` hook instead. That hook is load-bearing: removing it on a current kernel opens **6.97pt** under every list, which is the size of the hole an older kernel leaves when the hook does not reach the closing skip. TeX Live 2026 or a current `latex-dev` satisfies the floor, and so does a TeX Live install in `.texenv/`, the first place `build.sh` looks.

`main.tex` must open with `\DocumentMetadata{pdfstandard=A-2b,tagging=on,lang=en-US}` **before** `\documentclass` — that line supplies the PDF/A conformance, the real spaces, and the document language. The class warns if it is missing entirely, because conformance and spaces are lost silently while the PDF still looks right on screen.

`lang` is the only one of the three keys that nothing checks and whose absence breaks nothing, which makes it the easiest to drop. It writes `/Lang (en-US)` into the PDF catalog and `dc:language` into the XMP packet, and marks the title and subject entries `xml:lang="en-US"`. A screen reader picks its pronunciation from that value, and a parser that honors it stops inferring the language from the words. Set it to whatever language the CV is written in.

**The metadata is written as the first page ships, so it has to be declared before the content.** The class hands the title, author, subject and keywords to `\hypersetup` from the kernel's `shipout/firstpage` hook. It used to do so in `enddocument`, but the XMP packet is built in `shipout/lastpage`, and in `twocolumn` `\end{paracol}` ships the last page before `\end{document}` — the Info dictionary came out complete while the XMP had no title, author, subject or keywords, which PDF/UA-1 rejects. The kernel runs `shipout/firstpage` ahead of `shipout/lastpage` in every layout, including a one-page document where both fire on the same shipout, so the order needs no `\DeclareHookRule` and names no internal code label. The cost is a placement rule: `\cvtitle`, `\cvauthor`, `\cvsubject` and `\cvkeywords` go in the preamble, and `\name` and `\tagline` before `\makecvheader`. A metadata command reached after the first page has shipped is silently ignored and the PDF keeps the earlier value; `tests/src/tests/metadata-check.py` fails the run if the XMP and the Info dictionary disagree.

That line is a *claim*, though, and the claim needs backing up. LaTeX's list and align tagging attaches `latex-list-css.html` and `latex-align-css.html` to the PDF as associated files, and PDF/A-2 permits embedding only PDF/A-1 or PDF/A-2 files — so without a fix, the PDF would stop being PDF/A-2b while still claiming to be. The engine noticed (`PDF standard validation failure. Embedded non-PDF files detected.`) but said so only in the `.log`, which `./build.sh` deletes on success. Three things close that hole: the class suppresses the attachments with `\tagpdfsetup{attach-css=false}`, `./build.sh` prints the log's warnings, and a PDF/A validator (e.g., veraPDF) flags it if the PDF ever stops conforming.

The second `\tagpdfsetup` line in `main.tex` — `\tagpdfsetup{math/mathml/luamml/load=false}` — fixes a milder version of the same problem. `tagging=on` brings in LaTeX's math tagging module, which activates `luamml` to write a MathML sidecar; `luamml` needs `unicode-math` to map the math fonts, and this class loads `fontspec` without it. So every build warned:

```text
Package tagpdf Warning: Neither unicode-math nor lua-unicode-math has been
(tagpdf)                loaded.
(tagpdf)                luamml will not create a MathML file.
```

Nothing was broken by it: a CV has no math, no sidecar is written either way, and build times are identical within noise. It matters because `./build.sh` prints the log's warnings — left alone, this one fires on every build forever and trains you to skim past the place a real warning will appear. The key is the remedy the message itself proposes, and it sits next to `\DocumentMetadata` because that is the line that brings the math tagging module in.

If you ever load `unicode-math` to set formulas, drop the key — and re-check conformance when you do. `luamml` then activates in earnest and, by the module's own code path, opens `<jobname>-luamml-mathml.html` and attaches it as an associated file: the PDF/A-2 trap above, again.

Three ways to build:

* **`./build.sh`** builds `main.tex` into `resume.pdf` beside it, in two `lualatex` passes (a third when a `.bcf` calls for `biber`), then prints the log's warnings and deletes the log. `./build.sh path/to.tex [out.pdf]` builds something else instead. `./build.sh --opt NAME` adds a class option for that one build without touching the file, and is repeatable — `./build.sh --opt twocolumn --opt compressed`. Afterwards, spot-check the PDF with a text extractor (e.g., `pdftotext -layout`) to confirm the content still reads back correctly.
* **Overleaf**: open the shared template linked from the README and select *File → Make a Copy*, or upload the folder yourself; either way, check that *File → Settings → Compiler* is set to LuaLaTeX. `latexmkrc` sets this too, so a fresh project picks it up on its own — but only if the folder holding `main.tex` **is** the project root. Overleaf reads `latexmkrc` from the root and nowhere else, so uploading the whole repository leaves the file one level down where nothing looks for it, and the compiler has to be set by hand.
* **Locally, by hand**:

  ```sh
  lualatex main.tex
  lualatex main.tex
  ```

  Two passes: the first typesets, the second settles cross-references and the tagging structure. No `-shell-escape` is needed — nothing in the class shells out, and a build without it renders pixel-identically.

## Class options

Set on `\documentclass[...]{lucidcv}`. `10pt`, `a4paper` … are `extarticle`'s and still work: an unknown key is passed straight through to it.

| Option | Effect |
| --- | --- |
| `hyper` | clickable links. It governs the class's **own** links (the contact block); `hidelinks` and `\urlstyle{same}` are applied as the class loads either way, so any `\href` reaches the page without hyperref's default border box. Your `\hypersetup` in the preamble still overrides it — `\hypersetup{colorlinks=true,urlcolor=red}` gets you red links |
| `photo` | show the header photo declared by `\cvphoto`. On/off only — see *Name and photo* below |
| `noicons` | no icon glyphs anywhere — contact line, referees. The `\|` between contact items is unaffected: it is drawn in **both** modes, and only the air around it changes (`\cvinfodelimgapicon` beside an icon, `\cvinfodelimgap` without one). See *Copy-paste fidelity* below |
| `headingrule` | hairline under section headings (the default, `\cvrulewidth` = `0.4pt`); `\setlength{\cvrulewidth}{2pt}` for a heavier bar |
| `noheadingrule` | no rule — closest to the original PlushCV |
| `onecolumn` | one body column — **the default**, and the safest for ATS parsing (see *ATS and accessibility notes*). Can be passed explicitly, not just implied by omission. `cvbody` opens no columns and `\cvcolumnbreak` degrades to a paragraph break |
| `twocolumn` | run the body in two columns instead. Affects the body only — the header is identical either way, and the body file needs no edit. Costs reading-order robustness in geometry-sorting extractors, so opt in deliberately |
| `compressed` | tighter section-heading fonts and less vertical air around headings and entries, for a document that runs a few lines too long. A bundle of tighter defaults, individually overridable through the knobs below. It also defaults `\cventry` to `oneline`, folding each date onto its title line to save a line per entry — an explicit `oneline=` on the entry still wins |

### Typography the options do not reach

The class loads `ragged2e` only for its `justify` environment. Its `\RaggedRight` is deliberately never used, because it re-enables hyphenation, and in a narrow column that splits keyword phrases across a line: `Embedded Sys-` / `tems` extracts with a literal `-`.

**Hyphenation is off in every layout.** `\hyphenpenalty` and `\exhyphenpenalty` are 10000, so no line breaks at an inserted hyphen or after one already in the text (`data-driven`), and `\emergencystretch` is 3em so a line loosens its word gaps rather than overrunning the margin.

**The body is ragged right in both layouts.** Justify a block by hand with ragged2e's `justify` environment (the sample justifies About). Inside it the class **bounds** the word space's shrink to three quarters of the font's own shrink (`\fontdimen4`) rather than forbidding it. A heavily squeezed space (2.1pt where a natural one is 4.6pt) can be read by geometry-based extractors as no space at all (`P.Goldschmidt`), which is why the shrink is capped — but forbidding it outright is worse, and that is measured rather than argued.

With `minus 0pt` the line breaker had stretch as its only lever, and the sample's About paragraph came out with one line at **2.22×** its natural word gap (6.23pt against 2.81pt). Three of the thirteen configurations — Ghostscript `txtwrite`, pdf.js 2.5 and pdfminer.six — read gaps that wide as **two** spaces, so that line extracted as `PoCs  and  prototypes  in  academic …`, thirteen doubled gaps in the paragraph an ATS reads first. It also tripped an `Underfull \hbox (badness 1389)` that `./build.sh` did not surface, because its warning filter matches `Warning:` and a box warning carries no such word.

At `minus 0.75\fontdimen4\font` the squeeze reaches at most ~14% (2.43pt against 2.81pt), far from the `P.Goldschmidt` regime, and every doubled gap disappears. `order.py` — the reading-order scorer in `tests/src/tests/`, which this file refers to by bare name throughout — still returns 1.00 on all thirteen configurations, no words fuse, and the page count is unchanged. Allowing the font's *full* shrink produces byte-identical output, so the cap never actually binds: it is a ceiling against future content, not a working constraint. The rule applies only inside `justify`; ragged text keeps its natural spacing, since `\rightskip` absorbs the slack there.

`justify` is also redefined as a plain block rather than ragged2e's list (`\trivlist`), so it adds no glue of its own: it sits exactly where an ordinary paragraph would, with `\cvsection`'s trailing glue above it and the next heading's absolute gap below it. No `\vspace*{-…}` inside the block is needed, and none goes stale when the page changes.

**Every section opens the same distance below its heading, whatever follows it.** Left alone, TeX places the first *baseline* a fixed distance down, so the ink starts at a distance that depends on the line's tallest glyph and on the following element's own `\baselineskip` — a `(` on the first line, a smaller list font, or a larger `\cventry` title each landed differently. `\cvsection` therefore drops that interline glue outright and lays down one absolute skip, `\cvsectionbelowgap`. With no interline glue the top of the first line box *is* the top of its ink, so a paragraph, a list, a `\cventry`, a `\cvsubentry` and a row of chips all open at exactly the same distance. Nothing has to opt out, and adding a new construct to the class cannot get this wrong.

The skip is rigid on purpose. A `minus` component would let page pressure eat the gap — it used to cost the compressed variants about 0.5pt per heading — and a `plus` one never fires anyway, because the class is `\raggedbottom` and every bit of slack goes to the page foot. That is the same reasoning as the `plus`-only gap *above* the heading. Measured across the three shipped variants, the rule-to-ink distance now varies by 0.09pt or less within a variant; it used to vary by 0.41pt.

Page defaults are 1.2cm margins and a 65/35 column split; override with `\geometry{…}` and `\columnratio{…}` in your document. To move the font tree, put `\def\cvfontdir{path/to/fonts/}` **before** `\documentclass` — a definition already in place wins over the class's own search, which tries the `fonts/` directory beside `lucidcv.cls` first and then kpathsea (where a TeX distribution install keeps the `.ttf` files, apart from the class). It has to be that early: the class runs `\setmainfont` as it loads, so a `\renewcommand` in the preamble comes too late and fontspec fails to find the fonts.

## Usage

### Name and photo

`\name` takes **two** arguments, because PlushCV's two-tone name needs the split:

```latex
\name{Your Name}{Here}    % first part SemiBold, second Light
\fullname{Prince}         % single run, for mononyms or other name orders
```

There is one photo, it lives in the header beside the name, and it takes **two things** to get it there:

```latex
\documentclass[10pt,a4paper,hyper,photo]{lucidcv}     % 1. the switch
...
\cvphoto[4cm]{myface}                                 % 2. the photo itself
```

`\cvphoto` creates the photo and carries everything about it; the `photo` class option only decides whether it is shown. Either one alone gives no photo, which is the point: drop the option and a document's photo disappears without touching its `\cvphoto` line.

```latex
\cvphoto                      % avatar, default diameter and inset
\cvphoto[4cm]                 % avatar, your diameter
\cvphoto[4cm][0.6cm]          % avatar, your diameter and inset
\cvphoto{myface}              % your image, cropped to a circle
\cvphoto[4cm]{myface}         % your image at your diameter
\cvphoto[4cm][0.6cm]{myface}  % your image, both set
```

**One pattern to avoid.** The filename is an *optional* group, and TeX cannot tell an omitted argument from the author's next group. A `\cvphoto` with no filename therefore peeks at what follows, and if the very next token is a `{`, that group becomes the filename — its text never reaches the page, and the build stops with ``! LaTeX Error: File `<the swallowed text>' not found``. The error quotes what it ate, so it names its own cause.

Only that one pattern is affected. The peek skips spaces and a single newline and nothing else:

```latex
\cvphoto                  % ✗ eats the group below
{\bfseries Hello}

\cvphoto{}                % ✓ says "no file" outright
{\bfseries Hello}

\cvphoto                  % ✓ a blank line ends the peek

{\bfseries Hello}

\cvphoto                  % ✓ next token is a control sequence, not `{`
\textbf{Hello}
```

`\name`, `\tagline` and `\cvpersonalinfo` all begin with a control sequence, so the ordering in `main.tex` is safe. Write `\cvphoto{}` if you want the avatar and want to be explicit about it.

Cropping an image to the circle uses `fill overzoom image`, which comes from **`tikzfill`** — the class loads it as `\usetikzlibrary{fill.image}`. It ships with stock TeX Live and with Overleaf, but it is a real dependency: without it every `\cvphoto{file}` fails with `I do not know the key '/tikz/fill overzoom image'`, while the avatar path keeps working, so the breakage hides until someone supplies a photo.

Keep that `\usetikzlibrary` line if you adapt the class. The library is easy to lose by accident, because a class loading `\RequirePackage[skins]{tcolorbox}` gets `tikzfill.image` for free (`tcbskins.code.tex:22`) — so dropping tcolorbox, which this class does not otherwise need, would take the photo cropping with it. Loading it explicitly is what makes that impossible.

A photo of your own is yours to keep PDF/A-clean: an alpha channel is the usual way an image breaks conformance, so re-validate the output after adding one. Give `\cvphoto` **no** file and you get a drawn avatar instead — pure TikZ in the accent color, no image file to ship or forget, and no transparency, so PDF/A stays valid. The diameter defaults to 3cm; past about **4.4cm** the circle reaches the second column's first heading, which is the practical ceiling. The inset is measured in from the right margin; left out, it is computed so the photo ends up horizontally centered on the second column at whatever diameter you asked for.

**`\cvphoto` declares the photo; it does not draw it.** `\makecvheader` draws it later, so the line typesets nothing where it stands and can sit in the preamble or the body, as long as it comes before `\makecvheader` — after the header it is too late, and the class says so rather than silently ignoring it. Placing it beside `\name` and `\tagline` reads best.

The header band is empty once the contact block is held to the first column's width, and the photo is set at zero height, so it costs **no vertical space at any diameter** — enlarging it grows the circle into that empty band instead of pushing the document down. This matters beyond looks: a photo that drives the header's height shifts the two `paracol` columns by different amounts, and their lines can re-interleave for a reader that sorts by position. What the photo does cost is header *width* — diameter and inset both come off the name block, so a large photo pulled far in can wrap the contact line onto another row.

There is **one** photo and one place for it: `\cvphoto` fills the header slot, and there is no way to queue several images or to put one anywhere else. Note that in many markets a photo on a résumé is a liability, and image-heavy headers are a common cause of mis-parsed documents. To remove the photo, just drop the `photo` option.

**If you do drop it, pin the contact width too.** With no photo the band beside the name is empty, so `\cvinfowidth` defaults to the full `\textwidth` and the contact line flows across the page in fewer rows. That is good for space and bad for extraction: once the block wraps to **two** rows, poppler reads it column-wise rather than row by row, and the contact details come back interleaved —

```text
your_name@email.com
linkedin.com/in/your_id     <- row 2, returned second
000-00-0000                 <- back to row 1
```

Every item is still present in the text layer; only the order is wrong, which is what the reading-order report is there to show. It affects **both** layouts — the cause is the wide two-row block, not column interleaving. Holding the block to one column's width restores perfect order:

```latex
\setlength{\cvinfowidth}{0.65\dimexpr\textwidth-\columnsep\relax}
```

A contact line short enough to fit on one row is unaffected either way.

### Entries: `\cventry`

```latex
\cventry[oneline, askip=4pt, bskip=0pt]{Title}{Side text}{Date}
```

Three positional arguments (title, side text, date) plus keyword arguments, parsed with `keyval`.

The second argument is **side text** — arbitrary text set beside the title. It is usually the organization, and the class's internal names for it still say so (`\cventryorgfont`, the `entryorg` color), but nothing about the slot is reserved: a bare year goes there too, which is the award idiom below.

* `oneline` continues the header line with the date instead of stacking it underneath, so the entry reads `Title │ Side text │ Date` on one line. Written bare it means `oneline=true`. **It defaults to `false`, except under `compressed`, where it defaults to `true`** — folding the date up saves a line per entry, which is what that option is for. Writing the key on an entry overrides the default in either direction, so `\cventry[oneline=false]{...}` keeps one entry stacked in a compressed document.

  A flush-right date needs care: pushing it with plain `\hfill` used to be the single biggest reading-order defect in the class. A flush-right date on a single-column line leaves ~260pt of page with no glyphs in it, and poppler joins two words into one line only while the gap stays under about 1.5× the font size (measured on this document's 11pt type: 16pt joins, 20pt does not). The date became a block of its own, and once two of them stacked on adjacent baselines — the M.Sc. above the B.Sc. in Education — poppler read the pair as a right-hand *column* and emitted it after everything else on the page, putting both degrees' dates under References. pdfminer and Tesseract failed the same way. Filling the gap does not help: poppler discards `U+0020`, `U+00A0`, `U+2002`, `U+2007`, `U+200A` and the zero-width family before it measures word gaps (each one tested), and the only fillers that hold the line together are ones that survive into the text as garbage. `ActualText` is not the escape hatch either — see *Why not small caps*. Removing the open gap is the fix — a dotted leader in its place — and that is what `flushdate` sets and what makes it safe to default on.
* `flushdate` carries a one-line entry's date to the right margin, on a dot leader:

  ```latex
  \cventry[oneline]{Program Manager}{Weyland Yutani Industries}{May 2021 - Current}
  ```

  The entry reads `Title │ Side text` at the left and the date at the right margin, with `\cventrydatefill` — a dotted leader — spanning the distance.

  **The leader is not decoration; it is the fix.** An open gap of that width parts the date from its entry in every extractor that rebuilds lines from geometry; the dots are what hold the line together. What ships is measured to survive all of them — see *What the leader costs, and why it is a leader* below.

  **Because the leader passes every engine tested, it is the default for every `oneline` entry**, `compressed` included: writing `oneline` alone is enough. Written bare (or `flushdate=true`) it is a no-op unless it is overriding an explicit `flushdate=false` earlier in the same key list.
* `flushdate=false` keeps the date after the last bar instead — the form this class shipped before the leader existed:

  ```latex
  \cventry[oneline, flushdate=false]{Program Manager}{Weyland Yutani Industries}{May 2021 - Current}
  ```

  The key applies to `oneline` entries **only** — the stacked form already has its date on a line of its own and ignores it. An entry with an empty date ignores it too, so an award emits no filler. Like `oneline`, only a literal `true` counts: any other value silently falls back to `false` — see *Diagnostics*.

#### What the leader costs, and why it is a leader

Set the date flush right with plain `\hfill` and the filler leaves a **260pt gap — 23.5× the 11.1pt entry font** on the shipped sample (246–312pt, 22–28×, with every entry flushed), against the ~1.5× poppler will still join two runs across. Scored by `order.py` on the body in `onecolumn` at the shipped `10pt`:

| Filler between organization and date | poppler | pdfminer | Tesseract | `order.py` |
| --- | --- | --- | --- | --- |
| open gap, one entry flushed | 1.00 | **0.98** | 1.00 | **FAIL** |
| open gap, all ten flushed | **0.97** | **0.89** | 0.95 | **FAIL** |
| U+0020 space glyphs, 1em pitch | **0.97** | **0.89** | 0.95 | **FAIL** |
| period, 2em pitch | **0.95** | **0.91** | 0.95 | **FAIL** |
| period, 1em pitch | 1.00 | **0.91** | 0.95 | **FAIL** |
| en dash, 1em pitch | 1.00 | **0.94** | 0.95 | **FAIL** |
| period or middle dot, 0.4–0.5em pitch | 1.00 | **0.97** | 1.00 | **FAIL** |
| 7pt or 6pt dot, 0.2–0.333em pitch | 1.00 | **0.91–0.98** | 0.95 | **FAIL** |
| Light-face period, 0.333em pitch | 1.00 | **0.94** | 0.95 | **FAIL** |
| **period at entry size, 0.333em pitch — what ships** | **1.00** | **1.00** | **1.00** | **PASS** |

Every other engine holds 1.00 throughout; the failures come from poppler and pdfminer, which are strict in `onecolumn`. Four things fall out of that table, and they are why `\cventrydatefill` looks the way it does:

* **Space-family fillers do nothing.** A leader of real `U+0020` glyphs scores exactly what an empty gap scores — poppler discards spaces before it measures word gaps, along with `U+00A0`, `U+2002`, `U+2007`, `U+200A` and the zero-width family.
* **Two thresholds, and pdfminer's is the tight one.** A 1em dot pitch already satisfies poppler; pdfminer needs 0.333em, and between the two it is *inconsistent* — it joined some entries and split others, in one test emitting a leader and its date ahead of their own title line.
* **The dot must stay at the entry font size.** pdfminer's line-grouping tolerance scales with the glyph's own width, so a smaller dot shrinks the tolerance faster than it shrinks the gaps: 7pt and 6pt dots failed at every pitch tried, even with a tightened trailing pad, and so did the Light face's narrower period. Color is the exception — it never reaches an extractor, which is why `entryleader` is safe to restyle and `\cventrydateleadersep` is not.
* **The air before the first dot has a ceiling, and it moves with the title.** pdfminer joins two glyphs on one line only while the gap between them is under twice the wider one — 6.09pt for the 3.04pt dot at the `10pt` class size. The dots sit on a fixed grid (the pitch) measured from the line's left edge, so where the first one lands depends on where the title ends: the gap swings by one pitch, about 3.7pt, from entry to entry. At `\cventrydateleadergap` = `0.4em` the top of that swing was the limit itself, and about 2% of title widths split (a leader and its date came out after the next heading in `onecolumn` + `compressed`). At the shipped `0.35em` none of 483 varied titles did, with at least 0.4pt to spare; `0.3em` gives 1pt, at the price of dots that start closer to the title. If you raise it, re-run the tests.

Without the flushed date the untouched sample failed nothing, so this is a cost the key introduces and the leader cancels out, not a defect of the class. What the key still costs you: **the dots reach the parser as text** — around 67 of them between organization and date on a full-width entry — and a pale leader is harder for OCR to follow (Tesseract slips 1.00 → 0.95 at `CVGrey!20`, which is why the shipped `!30` is not lighter). In exchange every engine returns the entry as one line, `check.py` finds all 91 phrases of the shipped sample in every text-layer configuration, and word spaces, icons and PDF/A-2b are unaffected.

For the record, what an open gap does when it goes wrong: pdfminer detaches the date and re-emits it after the *following* job and that job's date, so the employer an ATS reads next to `Month 20XX – Ongoing` is the wrong one; flush the whole sample and poppler puts the M.Sc. and B.Sc. dates — the two on adjacent baselines — after References, while pdfminer sends all three degree dates to the foot of the document, below both referees. In `twocolumn` those same engines are advisory, so an open gap costs pdfminer 1.00 → 0.84 there and the run still reports PASS. Two columns *hide* this class of regression rather than avoiding it, so read `order.py`'s per-engine numbers rather than the PASS line whenever you touch the entry line.

#### The remaining keys

* `bskip` sets the vertical space *below* the entry, defaulting to `\cventryskip` (`\smallskipamount`, tighter under `compressed`). `bskip=0pt` binds the following paragraph to the entry — see the award idiom below.
* `askip` sets the vertical space *above* it, defaulting to `\cventrytopsep` (`0.25\baselineskip`, `0.1667` of it under `compressed` — `3pt` and `2pt` at the shipped `10pt`). It is added with `\addvspace`, so it takes the **maximum** of itself and whatever glue is already there rather than stacking on top of it — an entry after a bullet list gets one gap, not two. It is also suppressed for the **first entry of a section**, where the heading's own trailing glue already sets the distance; writing `askip` out explicitly overrides that suppression, so the caller always has the last word.
* `noscale` sets the entry at the document's own size, skipping the `\cventryfontscale` optical correction. Entry text is normally multiplied by `\cventryfontscale` (1.111) because Source Sans 3 looks smaller than Inter at the same nominal size, so a `10pt` document sets its entries at 11.11pt. With `noscale` the title and side text stay at `\normalsize` and a stacked date at `\footnotesize`, each keeping that size's own leading. Written bare; it takes no value. Use it where an entry has to line up with surrounding body text rather than read as a heading. `\cvsubentry` does not take it, as its fonts are unscaled already.

Every key is reset on each call, so one entry cannot leak its settings into the next, and an unknown key is an error rather than a warning — a stale `\cventry[true]`, or a `skip=` left over from before `askip`/`bskip` replaced it, fails loudly rather than misrendering.

There is no separate location argument: a location goes in the side text beside the organization, `{Company 1 | Location 1}`, or in the date field with its own bar. Set on one line, the date is typographically identical to the organization beside it — same font, size and color, separated by the same bar; stacked, it drops to the smaller gray meta font on its own line. The whole entry line is one family (Source Sans 3) at one size, scaled by `\cventryfontscale` to match the body optically unless `noscale` is given.

**Awards and achievements are entries with no date.** There is no separate achievement macro: it would be a near-copy of the stacked `\cventry` renderer, differing only in typeface choices that are not worth a second macro. Set an award as:

```latex
\cventry[bskip=0pt]{Fantastic Achievement}{20XX}{}
and some details about it
```

`bskip=0pt` is what binds the description to the name; `oneline` never needs mentioning, because with an empty date the one-line and stacked forms are identical.

### Sub-entries: `\begin{cvgroup}` and `\cvsubentry`

```latex
\begin{cvgroup}[rule]
  \cvsubentry[oneline=false, askip=..., bskip=0pt]{Title}{Side text}{Date}
  ...whatever belongs to that position...
\end{cvgroup}
```

A `\cventry` can have sub-entries, for example several positions held at one employer after a promotion. `cvgroup` wraps them and **owns the indentation of everything inside it** — sub-entries, paragraphs and lists alike — so the content needs no environment of its own. The indent is `\cvgroupindent` (`1.2em`); it is a narrower text width, not a `\leftskip`, so wrapped lines and list items are set inside it and never run past the right margin.

`\cvsubentry` takes the same three positional arguments as `\cventry` and is set as a regular paragraph: by default on one line like a `oneline` entry (it wraps like text if it is long), a semibold title, light side text after the bar and the date after a second bar. To read as *subordinate* to its `\cventry`, it is set at the plain body size, without the `\cventryfontscale` the entry line gets, so it comes out slightly smaller.

```latex
\cventry[oneline]{Employer}{City, Country}{09/2021 -- 06/2026}

\begin{cvgroup}[rule]
  \cvsubentry{Position 2}{}{09/2023 -- 06/2026}
  \begin{itemize}
    \item ...
  \end{itemize}

  \cvsubentry{Position 1}{}{09/2021 -- 08/2023}
  \begin{itemize}
    \item ...
  \end{itemize}
\end{cvgroup}
```

* **`rule`** is the group's only key. It draws a thin vertical line, purely as decoration, halfway into the indent, from the top of the first sub-entry to the bottom of the group's last line. Without it the group only indents. Written bare it means `rule=true`; `rule=false` is the default; any other value is read as `false` and no rule is drawn — see *Diagnostics*. The rule moves nothing: it and its two gaps take exactly `\cvgroupindent`, so the text sits at the same place with and without it. Its thickness is `\cvgrouprulewidth` (`1.25pt`), its position `\cvgrouprulepos` (a fraction of the indent, `0.5`), and its color `grouprule`, a lightened mix of `\cvaccent` that follows it. In the PDF the rule is an `/Artifact`, so screen readers and parsers skip it.
* **`oneline`** is the same key as on `\cventry`, but **defaults to `true` in every mode**, `compressed` or not. `oneline=false` stacks the date on a line of its own under the title, exactly like a stacked `\cventry`, in `\cvsubentrymetafont`.
* `flushdate` is the same key as on `\cventry` and likewise defaults to the sub-entry's own `oneline` value: a one-line sub-entry flushes its date right on the same dotted leader; `flushdate=false` keeps it after the last bar instead. A stacked sub-entry ignores it.
* `bskip` sets the space below, `0pt` unless given. Written bare it means `\cventryskip`, as in `\cventry`. A bare `bskip` gives the content under a position line the same small gap it gets under a `\cventry`, about `1pt` more than with no `bskip`, which is barely visible. Leave it off a sub-entry with no content that ends a group, where it would lengthen the rule and the gap below the group. The employer `\cventry` above needs no `bskip`.
* **Spacing between positions.** Every sub-entry but the group's first has the minimum air of `\cventrytopsep` above it, merged with a list's own closing skip rather than added to it. Sibling positions are therefore set apart by the same small gap whether or not the one above has content. An explicit `askip` replaces it and, unlike `\cventry`'s, is a plain skip that is added exactly; bare it means `\cventrytopsep`, and `askip=0pt` sets siblings tight.
* **Spacing after the group.** `cvgroup` closes with that same minimum air, and the next `\cventry` — the next employer — then gets a wider minimum, `\cvgroupsepratio` of `\baselineskip` (`0.5`, that is `6pt` at `10pt`), so a group of positions is set apart from the one below it. Under `compressed` it is `0` and the employers are as close as any two entries. An explicit `askip=` on that `\cventry` wins over it.
* `\cvsubentrytitlefont` and `\cvsubentryorgfont` set the title and the side text/one-line date fonts, `\cvsubentrymetafont` the stacked date; all are redefinable. `\renewcommand{\cvgroupindent}{0pt}` drops the indent.
* There is no `noscale` key, since a sub-entry's fonts are unscaled already; it is an unknown key and an error, like every other unknown key.
* A sub-entry consumes the section's first-entry flag, so a `\cvsubentry` placed directly under a heading takes the heading's own trailing gap and adds nothing of its own.
* A `\cvsubentry` outside a `cvgroup` is legal but has nothing to indent it, so it sits at the margin.
* **Limits.** The `framed` package sets the group in a box and splits it across pages, drawing one piece of the rule per page. That is why a group cannot hold footnotes, floats or `\cvsection`.
* **Groups do not nest**, and this is accepted rather than defended against. One global flag tracks *"is this the group's first sub-entry"*, so an inner group resets the outer one's state. A nested group holding at least one `\cvsubentry` happens to leave the flag in the state the next outer sub-entry wants, and renders correctly; an **empty** inner group leaves it set, and the next outer `\cvsubentry` drops its `\cventrytopsep` and butts against its sibling. Nesting buys nothing here — a group already owns the indentation of everything inside it — so put a second group after the first, not inside it.

### The body and its columns

The body goes inside `cvbody`, and that environment is the only place that knows `paracol` exists:

```latex
\makecvheader          % full width, in both layouts -- keep it outside

\begin{cvbody}
\input{contents}
\end{cvbody}           % anything full width goes after this
```

Under `twocolumn` it opens `\begin{paracol}{2}`; under `onecolumn` it opens nothing. The body file is the same file either way — there is no second copy of your CV to keep in sync.

The one thing a body file still has to say is **where the columns split**, because that is content rather than layout: `paracol` does not flow text from one column into the next the way `multicol` does. `\cvcolumnbreak` marks it, and degrades to a paragraph break under `onecolumn`:

```latex
\cvsection{About} …
\cvsection{Skills} …
\cvcolumnbreak          % -> right column
\cvsection{Experience} …
\cvcolumnbreak          % -> back to the left column
\cvsection{Education} …
```

It is repeatable: `\switchcolumn` alternates and resumes each column where it left off, so you can write the file in single-column reading order and slice it into columns with several breaks. `paracol` does not balance columns, so the more finely you slice, the more the vertical fit depends on how evenly the slices are sized. `\switchcolumn` is defined only inside `paracol`, so under `onecolumn` it raises `Undefined control sequence` — reach for `\cvcolumnbreak` there instead, the one token that means "next column" in both layouts.

`paracol` opens both columns level, so without help the two columns' opening lines always share a baseline — and an extractor that sorts by position can then fuse a line from one column into a wrapped line of the other. The **first** `\cvcolumnbreak` adds a small vertical push to the column it switches into, so that first pair never coincides:

```latex
\renewcommand{\colshift}{0.4\baselineskip}   % anywhere after \documentclass
```

The default is `0.25\baselineskip`. It is applied **once**, at the first break, not on every switch — so a body sliced into several columns with repeated `\cvcolumnbreak` still holds exactly one offset between the two columns. (Applying it per switch would push whichever column was entered, and after an even number of breaks both columns would carry the same total shift and their baselines would re-align, which is the one thing this is meant to prevent.)

**This is a mitigation, not a guarantee** — it only promises the two columns' *first* lines will not coincide; whether two lines further down do depends on the height of everything above them, which is a property of your content. If a text extractor drops a phrase in `twocolumn`, this is usually the mechanism: look at which two lines the report shows landing together, and either try a few `\colshift` values or adjust the spacing around the entry it points at.

### The rest of the body macros

`\cvsection{Name}` is the section heading; `\cvsubsection` is the smaller one, for grouping entries within a section (e.g., publications by type). `\cvdivider` draws a light dashed rule between entries. `\cvref{name}{email}{address}` sets a referee block with the contact lines hanging under the name.

Both headings are **tagged as headings**, not merely styled as them. Under `tagging=on` LaTeX tags every paragraph as `text` (role-mapped to `/P`), so a heading that only switches font and color reaches the structure tree as ordinary body text and the outline comes out flat — which is what this class used to produce: 158 paragraphs and not one heading element. The name is now `H1`, `\cvsection` is `H2` and `\cvsubsection` is `H3`, applied by retagging the heading's own paragraph through tagpdf's `para/tag` key. Retagging is the part that matters: wrapping the heading in `\tagstructbegin{tag=H2}` instead nests the auto-tagged paragraph *inside* the heading, and tagpdf rejects that with `Parent-Child ':H2' --> ':P'`.

`\cvtaglist` and `\cvtag` set skill chips — see *Chips*, which is worth reading before using either.

There is no bibliography-management macro — publications are a plain `itemize` list, written by hand. To embolden your own name, wrap it in `\textbf{}` as you would anywhere else.

Contact fields beyond the built-in set (`\email`, `\phone`, `\mailaddress`, `\location`, `\homepage`, `\linkedin`, `\github`, `\orcid`) are declared with `\CvInfoField`:

```latex
\CvInfoField[https://][gitlab.com/]{gitlab}{\faGitlab}  % \gitlab{your_id}
\CvInfoField*{mastodon}{\faMastodon}                    % \mastodon{@you@host}{https://host/@you}
```

The two optional arguments come first, before the field name, so that no optional argument trails. A trailing optional has to scan past the end of the line looking for a `[`, which is enough to swallow a following bracketed line as the shown prefix. In this position the scan stops at the first `{`, spaces and line breaks are harmless, and a long declaration wraps wherever you like.

**The prefix is declared in two halves, and the split is the point.** The link target is `scheme` + `shown` + value, while the typeset text is `shown` + value alone. So `\gitlab{your_id}` sets `gitlab.com/your_id` on the page and points it at `https://gitlab.com/your_id`. A contact value has to name itself to be worth anything to a parser: the icon beside it carries *no* label by design (see *Never label an icon with ActualText*), so a bare `your_id` reaches an ATS as an orphan token with nothing to say which service it belongs to.

Put only the scheme in the first slot. There are two ways to get that wrong and the class warns about both. Writing the prefix whole there (`[https://gitlab.com/]`) still links correctly but leaves nothing for the page, so the field falls back to printing the bare value. Leaving the scheme out altogether (`[][gitlab.com/]`) is the worse one: the text comes out right, but the target is relative and hyperref emits **no link annotation at all**, which nothing else would tell you about.

A scheme has to end in `:` or `//`, and that alone is what the class checks — so it needs no list of schemes, and `xmpp:` or `matrix:` pass as readily as `https://`. A first slot failing that test raises:

```text
Class lucidcv Warning: Field `gitlab' gives `https://gitlab.com/' as its link scheme,
which ends in neither `:' nor `//'.
```

A field declared with no prefix at all is not a mistake — it has nothing to link to and is left alone.

`[noprefix]` on an individual call drops the shown prefix from the text of that one item. **The link keeps the whole prefix regardless** — the key changes what is printed, not where it points:

```latex
\github{xGoldy}             % github.com/xGoldy  ->  https://github.com/xGoldy
\github[noprefix]{xGoldy}   % xGoldy             ->  https://github.com/xGoldy
```

Reach for it where the prefix is redundant next to a neighboring field, or where the contact line is tight: items are set in `\mbox`es and cannot break, so a shown prefix lengthens an atom that has to fit whole.

The starred form takes the full target as a second mandatory argument instead of building one, for a target that is not `prefix` + value at all. Both forms produce a macro you then use inside `\cvpersonalinfo`, and both accept `[noprefix]` — on a starred field there is no shown prefix to drop, so it does nothing.

**A field's link target is its value verbatim, so a space in the value reaches the URI.** That is fine for the page and not fine for the link: `\phone{+421 904 807 899}` sets a correct, readable number and points it at `tel:+421 904 807 899`. A space is not a legal URI character — tolerant readers strip it, strict ones refuse the link, and nothing warns either way. The starred form is the way out, because it is the one that lets the two differ:

```latex
\CvInfoField*{phone}{\faPhone}
\phone{+421 904 807 899}{tel:+421904807899}   % readable text, valid target
```

Values with no space in them — every `\github`, `\linkedin` or `\orcid` id — are unaffected, which is why the built-in `\phone` is the field where this bites. A `\mailaddress` or `\location` has no link prefix at all, so it never builds a target and the question does not arise.

The field command is made with `\DeclareDocumentCommand`, so **declaring a name twice redefines it, silently.** That is deliberate: it is what lets a document retune a *built-in* field rather than only restyle its icon — point `\github` at a different host, or give `\homepage` a shown prefix — which refusing a redeclaration would make impossible, since a field's scheme and prefix are fixed at declaration.

```latex
\CvInfoField[https://][www.gitlab.com/]{github}{\faGitlab}   % \github now points to GitLab
```

The cost is that a name LaTeX already owns is overwritten just as quietly, and the breakage surfaces somewhere else. `\CvInfoField{tagline}` takes over `\tagline`, and your tagline stops reaching the header. These names are taken in a default build, so a field must not use them:

```text
angle  author  bar   box    check  copyright  date   dot
hat    line    matrix  name  tilde  time      title  vec
```

`name`, `title`, `author` and `date` are the ones worth remembering. The math accents — `tilde`, `hat`, `vec`, `bar`, `dot`, `check` — fail differently and more confusingly: the field command is defined correctly and survives to the end of the preamble, then `amsmath` loads at `\begin{document}` (LaTeX's math tagging pulls it in) and takes the name back. The field silently stops existing, and the only symptom is a later *`\tilde` allowed only in math mode* pointing at your `\cvpersonalinfo` rather than at the declaration.

**To restyle a field's icon, do not redeclare it — `\cvfieldicon` replaces the icon in place**, and it works on the built-ins too:

```latex
\cvfieldicon{email}{\faEnvelope}        % \email keeps its mailto: prefix
\cvfieldicon{github}{\faGithubSquare}
```

A field's icon, shown prefix and link prefix live in a property list the class reads when the field is *used*, not values frozen into the field command when it was declared — which is what makes this possible. There is no lower-level entry point below the fields: every contact item goes through one, so a genuine one-off still costs a `\CvInfoField` line. In return, every item supports `\cvfieldicon` and `[noprefix]`, neither of which could reach an icon hardcoded at a call site.

**Escaping in a contact value.** `\lcv@detokenize` re-reads the display text with the specials made printable, so `_ & $ ~ ^` can all be written literally — `\github{your_id}`, not `\github{your\_id}`. `#` is the exception and has to be written `\#`: by the time the macro sees its argument TeX has already read a bare `#` as a parameter character, and `\scantokens` writes such a token back out **doubled**, so `ext#42` would silently typeset as `ext##42`. Inside `\cvpersonalinfo` it fails earlier and louder — that macro stores its argument with `\def`, and a bare `#` in a `\def` body is `! Illegal parameter number`.

### Headings and page breaks — a known deficiency

A `\cvsection` heading is **not** bound to the content below it. If a heading falls near the foot of a page or column with its first entry just too large to follow, the heading stays behind and the entry moves over, leaving the heading stranded at the bottom of the page with its rule under it.

This is a known deficiency rather than a bug the class defends against, and the reason is the rule. `\rule` is horizontal material, so in vertical mode it opens a *paragraph*, and the paragraph machinery reintroduces a breakpoint that no penalty placed around it removes — `\nobreak` before the trailing skip, the idiom `\@xsect` uses, does not bind it. (Under `noheadingrule` the heading never strands, which is how the cause was isolated.) Drawing the rule with `\hrule` instead *does* bind it, but `\hrule` omits the interline glue the rule's paragraph contributes: every shipped variant moved by up to 471pt, so the whole heading rhythm would have to be re-tuned to buy it back.

**The remedy is manual, and on a CV that is not a burden.** This class sets one or two pages that you read end to end before sending. If a heading lands badly, move it:

```latex
\newpage          % or \cvcolumnbreak in a two-column body
\cvsection{Experience}
```

Trimming a line of body text above it works just as well, and is usually what you want anyway on a document this size.

### The date stamp

`\lastupdated` draws an optional *Last update: `<date>`* line in the bottom-right corner of the **last** page. Call it anywhere in the document; `main.tex` ships it commented out just before `\end{document}`.

Three knobs: `\cvstampwidth` (`60mm`, the block's width, measured back from the right text edge), `\cvstampvshift` (`-0.1em`, a nudge from where it would otherwise sit; positive moves it down), and `\cvlastupdatedtext` (`Last update:`, the label). It is set in `\personalinfofont` and the `CVDate` color, so it matches the contact line's size and the tagline's color.

**The class is English-only by default**, and this label is the whole of it — the only prose the class itself typesets. Redefine `\cvlastupdatedtext` for another language; the date's own format comes from LaTeX's `\today`, or from `babel`/`polyglossia` if your document loads one.

**Vertically it is centered in the bottom margin** that `geometry` leaves — the band between the foot of the text block and the edge of the paper. That follows whatever margin you set rather than measuring a fixed gap from the paper edge, so the stamp keeps clear of the last line even on a page filled to the bottom. Horizontally it is flush with the text block's right edge.

It sits at the **foot** rather than the head because several extractors that sort by absolute position read a stamp at the head as the document's opening line, ahead of the name. It is placed from the text block's own edges rather than a fixed coordinate, so it lands correctly on any paper size, and under `twoside` it follows `\evensidemargin` on even pages, staying on the text edge when the margins are asymmetric.

**It is drawn from the kernel's `shipout/lastpage` hook**, not from the point where you call it, and that buys three things:

* **It costs no space.** A stamp is an overlay. Drawing it into the main vertical list — as a `textblock*` does — breaks the page when the body already reaches the foot of it, so switching the stamp on used to turn a one-page CV into a two-page one.
* **It lands on the last page**, wherever `\lastupdated` itself is written.
* **It works in both layouts.** This is the subtle one. Under `paracol` the last page is shipped from *inside* `cvbody`, as soon as the columns fill — before a `\lastupdated` written after `\end{cvbody}` is ever reached. A two-column build therefore got no stamp at all, unless it opened a second page to put one on.

That last point is why the macro does not act on the spot. It records itself in the `.aux`, and the next pass reads it back and arms the hook before anything ships — the mechanism `\label` and `lastpage` use, which is why this needs no extra package. `build.sh` already runs two passes, so this is invisible in normal use; a single hand-run pass on a fresh directory will not show the stamp. The flag is also set directly when the macro runs, so a call made *before* the page ships (one column, or anywhere in the preamble) stamps on the very first pass.

Two implementation details worth knowing if you touch it. The value read back from the `.aux` is assigned `\global`, because aux files are read inside a group and a `\newif` switch assigns locally — without it the flag is undone before the first page ships. And `\put` inside the shipout hooks takes multiples of `\unitlength` rather than lengths, so each coordinate goes through `\strip@pt`; the hook's origin is one inch in from the top-left corner with *y* running downward as negative, and the box is raised by half the difference of its height and depth so that the stamp itself is centered in the margin rather than its baseline. The y-coordinate is worked out into a length before `\put` sees it: `\put` reads its coordinates as a `)`-delimited argument, so a literal parenthesis in the expression would end the pair early.

### Diagnostics: what the class checks, and what it leaves to the page

The class warns about **one kind of problem only: the one you cannot see.** Every diagnostic it raises marks a document that compiles cleanly and looks right on screen while being wrong in the PDF's structure, in a link, or in what an extractor reads back. Anything whose symptom is visible in the output is left silent, because the page already reports it better than the log can. A `lucidcv` warning therefore always means *look past the rendering*.

**What it warns about** — six warnings and one error, the class's complete set:

| Condition | Why it cannot be seen |
| --- | --- |
| No `\DocumentMetadata` line | The PDF renders identically; PDF/A conformance and real word spaces are simply absent — see *Compiling* |
| `\nametaggap` too small | The header looks fine; the name and tagline fuse into one line only on extraction — see *Line breaks are always inferred* |
| A `\CvInfoField` scheme ending in neither `:` nor `//` | The visible text is correct; only the hyperlink target is malformed |
| `\setcolumnwidth` in force instead of `\columnratio` | No ratio can be read, so the header falls back to `0.65` and drifts out of step with the body |
| The `photo` option set with no `\cvphoto` | The missing photo is obvious, but the cause is not: the option only enables a photo; `\cvphoto` creates it |
| `\cvphoto` placed after `\makecvheader` | Likewise — the ordering requirement is not inferable from an absent photo |
| Not compiled with LuaLaTeX | A fatal `\ClassError`: nothing else in the class can work, so the run stops |

The two photo warnings fire even though their symptom is plain, because the *cause* is a class-specific rule no one can guess from an absent photo. That is the single exception to the rule above.

**What it deliberately does not check.** None of these produce a warning:

* **A missing `\name`, `\fullname` or `\cvpersonalinfo`.** The header renders without a name or without a contact block. (A missing name also leaves `pdfauthor` and `pdftitle` unset, since both are derived from it.)
* **A second `\makecvheader`.** The first call wins and later ones are dropped: you wrote two headers and get one.
* **A typo in a key's value** — `oneline=ture`, `flushdate=yes`, `rule=maybe`. Only a literal `true` is ever true; anything else is `false`, and the entry or group renders in its other shape right where you are looking. An earlier version warned on the first two and raised an error on `rule` — three severities for one class of mistake, each reporting what the entry already showed.
* **An empty or malformed field value.** `\email{}` visibly sets an icon with nothing after it.

A mistyped key *name* is a different matter and still fails loudly: `keyval` raises a LaTeX error for an undefined key, so a stale `\cventry[true]` or a leftover `skip=` stops the build rather than misrendering quietly.

## Customization knobs

Set these in your document, after `\documentclass`. **Most are `\renewcommand`-able; the ones marked [len] are LaTeX lengths and take `\setlength` instead** — `\setlength{\cvdividerskip}{4pt}`, not `\renewcommand`. The distinction is not cosmetic: `\renewcommand` on a length replaces the register with a macro, and the class's own arithmetic then mis-parses it. `-0.5\cvgrouprulewidth` evaluates to `-0.625pt` against the register and to `-0.51pt` plus a stray `.25pt` of literal text on the page against a macro, with no error either time.

**Separators and skips are stated in `em`**, so they scale with the document's base size rather than staying fixed when you move from `[10pt]` to `[11pt]`. At `[10pt]` an `em` is exactly `10pt`, which is how the previous point values map onto the ones below — `1.5pt` became `0.15em`, and the typeset output is unchanged. Three kinds of value deliberately stay as they were. The **rule thicknesses** (`\cvrulewidth`, `\cvdividerwidth`, `\cvgrouprulewidth`) stay in `pt`, because a hairline is a property of the page rather than of the type size. The **stretchable skips** (`\cvheadertrailskip`, `\cventryskip`) keep their `pt` glue, since a `plus`/`minus` component reads better in points than spelled out in `em` three times over. And a few are left as the kernel's named `\smallskipamount` / `\medskipamount`, which are quantities rather than raw measurements.

| Macro | Purpose and default |
| --- | --- |
| `\cvinfowidth` [len] | how wide the contact block may run. Left alone: the left column's width when a photo is shown, and the full `\textwidth` otherwise |
| `\colshift` | the offset the first `\cvcolumnbreak` gives the column it enters, so the two columns do not open on one baseline — see *The body and its columns*. Default `0.25\baselineskip` |
| `\cvinfosep` | gap between two contact items, visible only with icons on. `\cvinfosepamount` is the amount on its own (`0.75em`), and that is now genuinely the whole of the visible gap. Two stray spaces used to be added to it: one `\scantokens` appended to every value inside `\lcv@detokenize` — a bug, since it also landed *inside* `\href{}{}` and so ended up in the link's hot zone and in the text a reader copies out — and one the source file contributed between two field calls, which made the gap depend on how `\cvpersonalinfo` happened to be laid out and left the line with no legal breakpoint of its own. `\endlinechar=-1` removes the first, the `\unskip` at the head of `\cvinfodelim` the second. That matters if you redefine `\cvinfodelim`: it is the public, user-redefinable macro, and a replacement that drops the leading `\unskip` brings the stray space back. Under `noicons` this length does **not** reach the page: `\cvinfodelim` backs it out with a negative kern, so the gap there is `2 ×` `\cvinfodelimgap` whatever is set here — measured 9.19pt at every value from 0.70em to 0.90em |
| `\cvinfodelimmark` | mark set between contact items (`\|`). An en dash or `\textcolor{CVGrey}{\textbullet}` work too — use a real character, not a glyph an extractor has to guess at |
| `\cvinfodelim` | how that mark is set; `\cvinfodelimgap` is the air on either side (`0.4em`) |
| `\cvinfodelimgapicon` | gap between the `\|` separator and the next icon, with icons on (`0.2em`). The `noicons` twin is `\cvinfodelimgap` |
| `\cvinfoicongap` | gap between a contact icon and its value (`0.15em`) |
| `\cvcolumnbreak` | where the left column ends and the right begins — `\switchcolumn` under `twocolumn`, a paragraph break under `onecolumn`. Repeatable |
| `\cventry[oneline]{...}` | see *Entries* above |
| `\cventry[flushdate=false]{...}` | keeps a `oneline` entry's date after the last bar instead of flushing it right, which is otherwise the default, `compressed` included — see *Entries* above |
| `\cvsubentry{...}` | a `oneline` entry by default (`oneline=false` stacks it) inside a `cvgroup`, `0pt` below, and the small `\cventrytopsep` minimum above every one but the group's first; flushes its date right by default like `\cventry` — see *Sub-entries* above |
| `\cvsubentrytitlefont` / `\cvsubentryorgfont` / `\cvsubentrymetafont` | sub-entry title (semibold) and side text/date fonts (light), both `\normalsize`, and the stacked date font (semibold, `\footnotesize`); all unscaled |
| `\begin{cvgroup}[rule]` | wraps the sub-entries of a `\cventry`, indents everything in it and, with `rule`, draws the vertical line — see *Sub-entries* above |
| `\cvgroupindent` | left indent of everything inside a `cvgroup`, `1.2em` of the body font. It narrows the text width rather than setting a `\leftskip`, so wrapped lines and lists are indented alike |
| `\cvgroupsepratio` | the extra minimum air above the `\cventry` that follows a `cvgroup`, as a fraction of `\baselineskip`. `0.5` (`6pt` at `10pt`); `0` under `compressed`. Built into `\cvgroupsep` the same way `\cventrytopsep` is built from `\cventrytopsepratio` |
| `\cvgrouprulewidth` [len] / `\cvgrouprulepos` | thickness of the `rule` (`1.25pt`) and its position as a fraction of the indent (`0.5`, the middle) |
| `\cvsubentry[askip=...]{...}` / `\cvsubentry[bskip=...]{...}` | air above / below one sub-entry: `askip` defaults to the minimum `\cventrytopsep` (`0pt` for the group's first), `bskip` to `0pt`; bare means `\cventrytopsep` / `\cventryskip` |
| `\cventrydatefill` | the filler a `oneline` entry sets between itself and its date by default (`flushdate`): a dotted leader that carries the date to the right margin. Redefinable, but read *What the leader costs* first — an open `\hfill` here is the reading-order defect the leader exists to prevent |
| `\cventrydateleadersep` / `\cventrydateleadergap` | that leader's pitch (`0.333em`) and the air before its first dot and after its last (`0.35em`). **Measured, not chosen**: at a pitch of `0.4em` or looser, pdfminer starts splitting the entry line, and so does a gap of `0.4em`, on the titles whose width puts the first dot at the top of the grid (see *What the leader costs*). Loosen either and re-check the extracted text |
| `\cventry[askip=...]{...}` / `\cventry[bskip=...]{...}` | air above / below one entry — see *Entries* above. Defaults `\cventrytopsep` / `\cventryskip` |
| `\cventryskip` [len] | the space below an entry, which `bskip=...` overrides; before a list, the gap to its first item also involves the list's own `\cvitemtopsep`. `\smallskipamount` normally, `1.5pt plus 0.5pt minus 0.5pt` under `compressed` |
| `\cventrytopsep` | the air above an entry that `askip=...` overrides. Not a length — a macro resolved where the entry is set, because `\baselineskip` is not yet the body's when the class is read. Tune it through `\cventrytopsepratio` (`0.25`, `0.1667` under `compressed`) and `\cventrytopsepgluefrac` (`0.3333`, the share of the natural size the stretch and shrink take). At `10pt` that is `3pt plus 1pt minus 1pt`. Placed with `\addvspace`, so it is a **minimum**, never added to the gap already there, and it is skipped for a section's first entry. It is what keeps a `\cvtaglist` or a stray paragraph between two entries attached to the one above it instead of drifting onto the one below |
| `\cventrytopsepratio` / `\cventrytopsepgluefrac` | the two knobs behind it. A fraction of `\baselineskip` rather than of `\smallskipamount`, because `\smallskipamount` is `3pt` at *every* class size — LaTeX's `size*.clo` files all set it the same — while the itemize closing skip this has to sit level with does track the size option (`8/10/13/16pt` at `8/10/12/14pt`). Pinning it to a constant made the two diverge as the document grew |
| `\cvitemlastskipratio` / `\cvitemlastskiptrim` [len] | how much of a list's own closing skip to keep: `0.4` less `0.2em` normally, `0.25` less `0.15em` under `compressed`. LaTeX's tagging `block` code ignores the keyed `topsep` for that last skip, so it is scaled in a hook instead of configured. The hook is registered for `itemize`, `enumerate` **and** `description`, so a document mixing list types gets the same gap below each; the result is clamped at zero, since a negative skip would pull the following content up |
| `\cvitemsep` / `\cvitemtopsep` | `itemize`'s `itemsep`/`topsep` (`0.15em`/`0.2em` normally, `0.1em`/`0.1em` under `compressed`) |
| `\cvitemmarker` | `{\small\textbullet}` (uncolored) |
| `\cventryseparator` | `│` between title and side text, and between side text and a `oneline` date — under `flushdate=false` the date takes a second bar instead of the right margin |
| `\cventrytitlefont` / `\cventryorgfont` / `\cventrymetafont` | `\normalsize` / `\normalsize` / `\footnotesize`, each multiplied by `\cventryfontscale` |
| `\cventryfontscale` | `1.111` — the measured ratio that makes the Source Sans 3 entry line match Inter's body optically (Inter's x-height is 11% larger at equal point size). Set to `1` for equal point sizes instead |
| `\nametaggap` / `\tagcontactgap` | extra space added under the name (`0.1em`) and under the tagline (`0.25em`) in the header. Negative tightens; the class warns below roughly −6pt — see *Line breaks are always inferred* |
| `\cvheaderskip` [len] / `\cvheadertrailskip` [len] | header base gaps: name→tagline & tagline→contact (`\smallskipamount`), header→body (`1pt plus 1pt minus 1pt`); `0.15em` and `0em` under `compressed` |
| `\cvsectionsize` / `\cvsubsectionsize` | section and subsection heading sizes as bare point numbers — `16` / `11`, and `13` / `10` under `compressed`. Absolute, like `\cvnamesize`: they do **not** follow the class size option |
| `\cvsectionleading` / `\cvsubsectionleading` | line leading for a heading that wraps, as a multiple of its font size — `1.25` / `1.25`, and `1.2` / `1.2` under `compressed`. These pair with `\cvsectionsize` / `\cvsubsectionsize`: if you change a size, revisit these too |
| `\cvsectiongapratio` | the air **above** a `\cvsection` heading, as a multiple of the **class size option** — `1.0` normally, `0.7` under `compressed`, so `10pt`/`7pt` at `\documentclass[10pt]` and `12pt`/`8.4pt` at `[12pt]`. It is a guaranteed *minimum*: the glue carries `plus` but deliberately no `minus`, and the descender compensation can only add to it. **Re-check the extracted text after changing it** — a small enough value has cost poppler a phrase to column interleaving in `twocolumn`, see *What the LuaLaTeX migration cost* |
| `\cvsectionbelowgap` [len] | the air **below** a `\cvsection` heading, measured from the rule to the top of whatever follows (`0.7em`, `0.39em` under `compressed`). `\cvsection` drops the follower's interline glue and lays this skip down instead, so every section opens at the same distance whatever construct comes next. Rigid on purpose — see *Typography the options do not reach*. Re-check the extracted text after changing it, as above |
| `\cvrulewidth` [len] | thickness of the hairline under a `\cvsection` (`0.4pt`, `headingrule` only) |
| `\cvrulegaptrim` | extra trim around the heading rule (`headingrule` only) — `0em` normally, `0.25em` under `compressed` |
| `\cvsubsectionskip` [len] | gap above/below `\cvsubsection` (bibliography headings) — `\smallskipamount` normally, `0.15em` under `compressed` |
| `\cvnamesize` / `\cvtaglinesize` | header display sizes as bare point numbers — `38` and `15`. Absolute: they do **not** follow the class size option, see the note under this table |
| `\cvnameleading` / `\cvtaglineleading` | their leading, as a multiple of size — `1.105` and `1.2` |
| `\namefont`, `\taglinefont`, `\personalinfofont`, `\cvsectionfont`, `\cvsubsectionfont` | the header and heading font hooks. `\cvsectionfont`/`\cvsubsectionfont` are `16/20`/`11/14` normally, `13/16`/`10/12` under `compressed`. `\personalinfofont` is `\cvinfofontscale` × the class size option (`0.9`, so 9pt at `[10pt]`) on `\cvinfoleading` × that (`1.4`, so 12.6pt) — the **one** header element that tracks the size option. See the note under this table |
| `\cvphotogutter` | the gap between the name block and the photo (`1ex`). Read twice — once to reserve it out of the name block's width, once to emit it — so it has to be one value or the two halves of the header disagree about how wide it is |
| `\cvaccent` | the template's one accent color — name, section headings, the rule under them, every icon/chip/marker. `\cvaccent{B03A2E}` takes HTML by default; `\cvaccent[RGB]{29,118,226}` and `\cvaccent[named]{OliveGreen}` take any other xcolor model (loaded with `dvipsnames`, so `named` reaches 19 base names plus 68 classic ones). Prefer it to redefining `CVBlue` directly: `\colorlet` copies, so a bare redefinition leaves the five derived slots (`accent`, `name`, `heading`, `headingrule`, `grouprule`) holding the old value |
| `CVBlue`, `CVPrimary`, `CVSubheading`, `CVGrey`, `CVDate` | the five base color constants the semantic names (`accent`, `body`, `heading`, …) resolve to. Redefine one directly, or `\colorlet` a semantic name to something else entirely |
| `entryorg` | color of the organization after the job title — `CVSubheading`. `\colorlet{entryorg}{accent}` makes it the accent color |
| `entryleader` | color of the flush-right dot leader (`flushdate`, on by default for a `oneline` entry) — `CVGrey!30`. The one part of the leader that is safe to restyle, because color never reaches an extractor; `!20` or lighter costs OCR, which reads the page rather than the text layer |
| `divider` | color of the `\cvdivider` rule — `CVGrey!30`, the same faint tint as `entryleader`, the class's other hairline mark |
| `taglistmark` | color of the `\cvtaglist` delimiter — `CVGrey` |
| `quote` | color of the pull-quote — defaults to `CVSubheading` but has its own name, so recoloring one leaves the other alone |
| `\cvquoteskip` [len] | gap before a `quote` block — `\medskipamount` normally, `0.3em` under `compressed` |
| `\cvdividerwidth` [len] / `\cvdividerdash` | the `\cvdivider` rule's thickness and its dash rhythm. Thickness is `0.6pt`, a touch heavier than the `\cvrulewidth` hairline under a heading so the divider reads as a separator rather than a second rule; the dash defaults to `0.35em` (`3.5pt` at `[10pt]`), matching the `em` rhythm `\cventryseparator` uses. One value sets dash and gap alike — give two for an uneven pattern, so `0.4pt 3pt` reads as dotted rather than dashed |
| `\cvdividerskip` [len] | air above **and** below a `\cvdivider` — `0.7em` normally, `0.3em` under `compressed`. Set symmetrically; whatever follows the rule adds its own leading skip on top (a `\cvref` adds `\cvrefskip`), so the gap below reads slightly larger than the gap above |
| `\cvrefskip` [len] | gap above each `\cvref` entry — `\smallskipamount` normally, `0.15em` under `compressed` |
| `\cvrefindent` [len] | hanging indent of a `\cvref` block's wrapped lines, and the width of its icon column (`1.9em`) |
| `\cvrefnamefont` | the referee's name in `\cvref` (`\bfseries`, set in `emphasis`). The name inherits the ambient body font, so this sets weight rather than family |
| `\cvtaglist` / `\cvtaglistmark` / `\cvtaglistgap` | comma-separated chips and their delimiter — an en dash in `taglistmark` (`CVGrey`), with `0.2em` either side. Only top-level commas split, so brace an item to keep a comma inside it: `\cvtaglist{{C, C++}, Python}` sets two chips. **The mark must be a stroke, not a dot** — see *Chips* |
| `\cvtagspace` / `\cvtagsep` | a chip's leading space glyph and its trailing gutter (`0.2em`). Both are extraction-critical — see *Chips* before changing either |
| `\cvtagfontscale` / `\cvtagleading` | chip text size as a fraction of the class size option (`0.9`, matching the contact line) and its leading (`1.2`). The `ex`-based node padding scales with it, so the whole chip shrinks rather than just its text — see *Chips* |
| `\cvtagysep` | a chip's vertical padding per side, the `inner ysep` of its border (`0.35ex`) |
| `\cvtagheight` / `\cvtagdepth` | a chip's text height and depth, the node's `text height` (`1.45ex`) and `text depth` (`0.4ex`). Fed to both the node and its strut so the two cannot drift apart |
| `\cvtaglinegap` | extra room reserved **below** a chip, so that wrapped chip rows keep their borders apart (`0.3ex`). With `\cvtagheight`, `\cvtagdepth` and `\cvtagysep` it sets the strut each chip carries. It is kept below rather than above deliberately: the strut's top has to stay level with the chip border, or a chip row opening a section would sit lower than every other construct — see `\cvsectionbelowgap` |
| `\cvlastupdatedtext` | the `\lastupdated` label (`Last update:`). The class contributes no other typeset prose, so this is the one string a non-English document has to change; `\today`'s format comes from LaTeX, or from `babel`/`polyglossia` if the document loads one |
| `\cvstampwidth` / `\cvstampvshift` | the `\lastupdated` date stamp: block width (`60mm`), measured back from the right text edge, and a nudge from the middle of the bottom margin (`-0.1em`, so the shipped stamp sits about 1pt above that midpoint — positive moves it toward the foot of the paper). It is set in `\personalinfofont` and `CVDate`, so it matches the contact line's size and the tagline's color |
| `\cvtitle{…}` / `\cvauthor{…}` / `\cvsubject{…}` / `\cvkeywords{…}` | PDF metadata. Defaults: title *name* – Curriculum Vitae, author *name*, subject the tagline ("Curriculum Vitae" when no tagline is set), keywords empty. Keywords are comma-separated |
| the `\location` icon | `\faMapMarker`, set in the field's own declaration; change it with `\cvfieldicon{location}{…}` |

**What scales with `\documentclass[Npt]` and what does not.** The body scales, and so does the contact line — `\personalinfofont` is `0.9` × the size option, a step below body text. **Do not raise that `0.9` casually**: the item text *and* the `em`-based gap between items both grow with it, and at `1.0` the shipped sample's contact block no longer fits three rows and takes a fourth, costing ~10pt of vertical space and hurting extraction order (see *If you do drop it, pin the contact width too*). The `\lastupdated` stamp tracks it too, since it is set in `\personalinfofont`. Everything else in the header is deliberately an absolute point size and stays put: the name (`38`), the tagline (`15`) and `\cvsectionfont`/`\cvsubsectionfont` (`16/20`, `11/14`). The design is drawn for `10pt`, which is what `main.tex` ships; at `12pt` and up the body grows into a header that does not, so retune the sizes above rather than expecting them to follow.

## Origins

`lucidcv.cls` takes its color palette and font pairing from [PlushCV](https://github.com/cystema/PlushCV), credited in the class file's header comment and under *Licenses*. What is borrowed is small and specific:

* **Colors and font choice** — PlushCV's blue/gray palette and its Inter + Source Sans Pro pairing (here Source Sans 3, the same family under its current name, loaded from their TrueType build rather than PlushCV's OpenType one; see *Copying out of pdf.js viewers* for why). PlushCV's own layout code, icons, and fixed-size fonts were not kept — they broke on real content: overflowed the page once a column ran long, froze `\large`/`\small` by pinning an optical size, or produced icons a text extractor could never see.
* **Everything else is this class's own**, mostly because the ATS/PDF-tagging goal it is built around needed a different approach than that source took — the entry system, the header and photo layout, the chips, the sub-entry and group machinery, and the two-column split's page-break handling. There is no sidebar, no infographic charting and no bibliography management: this is a hand-written CV with no citations to manage.

The engine is fixed to LuaLaTeX with no pdfLaTeX or XeLaTeX fallback: the fonts are `.ttf` files loaded by path, and the real-space-glyph tagging this class relies on is LuaTeX-only. The class fails fast with a clear message under any other engine, and requires a `2026-06-01` format or newer — that is TeX Live 2026 with its kernel updates applied, which current Overleaf runs; distro packages may lag behind it. An older kernel only draws a warning, but the list spacing then drifts: the 2026-06 kernel builds lists itself and emulates `enumitem`, which is what the class's list spacing is tuned against.

## ATS and accessibility notes

Verified by compiling `main.tex` and reading it back with several independent extraction engines — poppler, MuPDF, pdfium (Chrome), pdfminer.six, pdf.js (Firefox, and the viewer embedded in most editors), Apache PDFBox/Tika, and Ghostscript `txtwrite`. Every phrase in the sample comes back intact in every engine that rebuilds word gaps from font geometry. The exceptions, and the design choice made to address each, follow.

The harness that produced every number in this file is at `tests/`: `src/tests/check.py` scores whether a phrase survived and `src/tests/order.py` whether it survived *in sequence*, across 9 extraction engines in 13 configurations. From `tests/`, run `./setup.sh` once, then `./pipeline.sh ../main.tex` to generate the phrase list, build and check the document; append `--opt twocolumn` or `--opt compressed` to score another layout without editing it. This section is about *why*; `tests/README.md` is about *how much*.

* **Two columns can extract out of reading order — the one real limitation left.** Engines that preserve the PDF's own content-stream order (`pdftotext -raw`, MuPDF, pdfium, pdfminer.six) return a clean résumé, left column then right. Engines that re-sort by geometry (`pdftotext`, hence Okular's select-all; Ghostscript `txtwrite`) interleave the two. This is inherent to any multi-column PDF, not specific to this class — no in-file change fixes it. This is why `onecolumn` is the default: for maximum safety, simply do not pass `twocolumn`. Dropping it needs no edit to the body file and does not change the header. The cost of one column is page length.
* **A flush-right date needs a leader, and the class ships one.** The `flushdate` key on `\cventry` (and `\cvsubentry`) restores the right-margin date this class started with, and is the default for every `oneline` entry — `flushdate=false` switches back to the inline form. What it sets is a dotted leader rather than open space: an open gap there runs ~23× the entry font, well past the ~1.5× poppler will join two runs across, and the date parts company with its employer — one flushed entry was enough to fail `order.py` in `onecolumn`. With the leader every engine returns the entry as one line and the body in document order. The price is the dots themselves, which reach the parser as text. Numbers, and the pitch and glyph size that make it work, are under *Entries*.
* **Linked fields extract as their display text**, not their target. Wrapping `\href` in an ActualText holding the URL — so that `your_name@email.com` reaches a parser as `mailto:your_name@email.com` — is deliberately not done; see *Never label an icon with ActualText* for why that shape is a trap. The URL is still a link annotation, and `hyper` still makes it clickable. **One character cannot appear in a link target at all: `$`.** A bare `$` leaks hyperref's `\ifx…\hyper@hash…\fi` into the URI and an escaped `\$` is dropped from it silently — in a prefix-derived target (`\email`, `\homepage`, …) and in a starred field's explicit target alike, so neither form is a way around the other. It is safe in the **display text**, which is detokenized: declare the field with no prefix, leaving it nothing to link to (`\CvInfoField{oddsite}{\faGlobe}`, then `\oddsite{ex.com/a$b}`), and it typesets and extracts correctly, just unlinked.
* **The photo is a tagged `Figure` with alt text, and a `quote` is a real `BlockQuote`.** `tikz` suspends tagging, so a picture drawn inside it reaches the structure tree as neither content nor an artifact — assistive technology cannot tell a photograph is there. The class opens the `Figure` element outside the picture, where tagging is still live, and fills its `/Alt` from `\name`: *Photograph of Adrian Castellanos*, or *Placeholder avatar in place of a photograph* for the drawn avatar. There is no knob for the text; it follows the name so it cannot fall out of step with it. The `quote` environment is likewise restyled full-measure rather than kept at LaTeX's margins, which drops LaTeX's own `BlockQuote`, so the class re-emits that element by hand — a pull-quote reads back as a quotation and not as one more paragraph.

### Why not small caps

Small-cap glyphs are OpenType alternates outside the font's `cmap`, and `\MakeUppercase` changes the characters outright, so neither reaches an extractor as the string you typed. The class used to correct for that with `accsupp` ActualText on every heading, job title and organization — declaring the original string as the "actual text" behind the transformed glyphs.

**Do not put that back.** poppler 22.02 honors only the first ~30 ActualText spans on a page and then drops the rest *including the glyphs they cover* — with one span per heading and per entry the sample reached 54 spans, and `pdftotext` returned a résumé missing its entire Education section and seven of nine section headings, invisible unless you diff against another engine. Drawing the characters directly removes the dependency.

The class ships no small-caps or uppercase styling hooks at all, for this reason. All-caps section headings are conventional on a résumé, but wrapping `\cvsection` in `\textsc` or `\MakeUppercase` means the heading no longer extracts as the word you typed — and correcting that with ActualText walks straight back into the bug above. `\MakeUppercase` additionally hard-fails on `\cvsubsection` if a bibliography heading contains an icon macro, expanding, for example, `\faBook` into a lookup for an icon literally named `BOOK`.

### Ghostscript and word spacing

**Solved, by switching the engine.** Kept here because the reasoning is what keeps it solved.

TeX does not put a space *character* between words — it puts **glue**, a stretchable amount of horizontal space, which the driver writes as a positioning instruction (a `TJ` numeric offset). Nothing in the file says "word ends here"; every extractor has to guess from the offset, and they guess differently. Most guess well. Ghostscript's `txtwrite` used to guess **per glyph pair** rather than by width, and the fusing gaps were exactly as wide as the surrounding gaps that extracted fine — width was never the variable, so no `WordSpace` tweak could reach it. (The class used to widen the fonts as an extraction crutch, at a real cost in typography.)

**LuaLaTeX with `\DocumentMetadata{tagging=on}` emits a real space glyph instead**, and shrinks the following offset to compensate so nothing moves on the page:

```text
before:  <029402640345>      -261 <01F80246...>      the gap is a number
after:   <0294026403450692>   -12 <01F80246...>      0692 is the space glyph
```

Every extractor now reads a plain U+0020. This is also why the class refuses to build under XeLaTeX: its driver cannot do this, and the failure is silent — the PDF looks perfect and reads back with words run together. A build-time check on the space glyphs catches it if they stop appearing, and spot-checking the extracted text catches any engine that returns something other than U+0020 for a word gap (a literal U+00A0 in particular, which `java.util.regex`'s `\s` does not match).

**What the LuaLaTeX migration cost.** LaTeX's tagging replaces `enumitem` with its own `block` list implementation, and a few class idioms had to change: `nosep` now *wins* over later `itemsep`/`topsep` keys instead of being overridden by them, so the keys are set individually; `after=\vspace{...}` is not implemented by `block`, so it is an `\AddToHook{env/itemize/after}` instead; and `\cvref`'s description list used `style=multiline`, also unimplemented, replaced by a `\hangindent`. The section skip moved away from PlushCV's value for the same reason — `block` list spacing shifts the body enough to bring a main-column sentence level with the right column's pull-quote, costing poppler a phrase in `twocolumn`. **This is measured, not reasoned about**: re-check the extracted text after touching either section-gap ratio.

### Thin spaces: write `\:`, not `\,`

**Between a number and its unit, write `850\:ms` or `850~ms`. Avoid `850\,ms`.** All three render as an unbreakable gap, but only the first two read back as `850 ms` in every engine.

Tagging inserts its space glyph only at *glue*, and the kernel sets the text-mode `\,` `\:` `\;` (and `\thinspace`, `\medspace`, `\thickspace`) as a *kern*. So `\,` used to leave no space character at all, and the engines split on the bare 1/6 em gap: poppler, MuPDF, pdfium and PDFBox read `850 ms`, while `pdftotext -raw`, Ghostscript `txtwrite` and pdf.js 2.5 read `850ms`. The class therefore redefines these three as unbreakable glue of the same width. The page is unchanged, but each gap now gets a real U+0020. That fixed Ghostscript and pdf.js 2.5. Negative spaces (`\!`) stay kerns, since they are not word gaps, and math mode is untouched.

`pdftotext -raw` still fused `\,`, because poppler discards U+0020 before it measures word gaps (see *Entries*), so only the gap width counts. Measured on the shipped sample's 10pt body: a gap of **0.19em fuses and 0.20em splits**. `\,` is 0.1667em, below that threshold; `\:` is 0.2222em and `~` a full word space, both above it. A literal thin space (U+2009) does not help either: `-raw` drops it as well, and `txtwrite` passes it through verbatim, so a parser that splits only on U+0020 still sees one word.

The cost of `\:` is a gap a few hundredths of an em wider than a typographic thin space, which is not visible at body size. The phrase generator (`tests/src/init-phrases.py`) reads `\,` `\:` `\;` as a space either way, so a `\,` that slips back in fails only `poppler-raw`, and that single-engine failure tells you the gap is too narrow, not that a phrase was lost.

### Copying out of pdf.js viewers

**This is why both font families are loaded as `.ttf`.** It looks like a packaging detail and it is not.

Same missing-space problem, different threshold. Old pdf.js (≤2.x) does not measure a gap against the font size; it measures it against the font's own space width, and when the embedded subset has no space glyph to consult it falls back to `/DW`, the CID font dictionary's default width. `/DW` is written by the PDF-writing step, and *which flavor of font file you hand it decides the number*: from a `.ttf` it takes the modal advance of the embedded subset (a real typographic width); from an `.otf` build of the same Inter release it took a width held by exactly one glyph in the font, well above the actual word gap, so old pdf.js's threshold sailed past real gaps and body text copied as `Loremipsumdolorsitamet`. Loading the identical Inter 3.019 release from its hinted TrueType build instead fixes it with no other change — same render, same word gaps, only the threshold moves.

Current pdf.js switched to font-size-relative thresholds years ago and is not affected, but plenty of embedded viewers still ship a 2.x-era copy, VS Code's among them — hence the one-line difference of loading `.ttf` over `.otf`. **If you swap the body font, check it first**: a font is safe if and only if, after TrueType embedding, `space_advance × 0.95 > 0.3 × modal_advance` — with the mode taken over the characters a résumé actually sets, not the whole font (Inter's whole-font mode is 1.389 em, held by circled letters and geometric shapes no CV ever reaches, and screening on that would reject the font this class ships, which demonstrably works).

### Why the fonts are bundled, not loaded from CTAN

**TeX Live already ships all three families — `inter`, `sourcesans`, `sourcecodepro` — and the class still bundles its own copies, because the CTAN Inter fails poppler.** Switching the class over to the CTAN fonts was built and tested in full; the page looked the same and the PDF read back worse.

The CTAN packages ship OpenType (CFF) builds: Inter 4.0 and Source Sans 3.052. With both loaded, poppler's default `pdftotext` mode lost **5 of 111** phrases in the default layout, and every other engine stayed intact. Swapping one family at a time isolated the cause:

| Body (Inter) | Display (Source Sans) | poppler |
| --- | --- | --- |
| CTAN 4.0, `.otf` | bundled, `.ttf` | broken |
| bundled 3.019, `.ttf` | CTAN 3.052, `.otf` | intact |

The mechanism is Inter's units-per-em, not its shapes:

1. **The OpenType Inter 4.0 is drawn on a 2048-unit grid**; Source Sans 3, like most CFF fonts, uses 1000, the unit PDF text is measured in.
2. **LuaTeX compensates by shrinking the font size it writes, not the outlines.** For a CFF font off the 1000 grid it embeds the outlines unscaled, forces the FontMatrix to 0.001, and divides the size by units/1000 — `4.86 Tf` instead of `9.96 Tf`. The render is correct, but to anything reading the PDF, Inter body text is 4.9pt and chip text 4.4pt. This is hard-coded in LuaTeX (`pdfglyph.c`, `writecff.c`), an old workaround for an Acrobat bug, with no switch to turn it off; `Renderer=HarfBuzz` writes the same `4.86 Tf`.
3. **poppler takes the size literally.** Its rules for joining words into lines and blocks are multiples of the font size, so an ordinary 5pt gap — about 0.5em at the real size — measures about 1em at the reported one and reads as a column gap. Each bullet and each chip became its own block, and phrases spanning them were lost.

TrueType is not affected: LuaTeX rescales a `.ttf` properly whatever its grid, and the bundled Inter is on 2816 units. The problem is specifically **OpenType Inter under LuaTeX**.

No clean all-CTAN alternative was found:

* `\usepackage[type1]{inter}` writes the right size, but LuaLaTeX cannot put Unicode text into those 8-bit fonts: `–`, `•` and curly quotes are dropped, so `2020–2022` extracts as `20202022`.
* Loading the package's `.pfb` files through `fontspec` fails, because the package ships no `.afm` metrics.
* Rescaling Inter's outlines to the 1000 grid while the PDF is written was prototyped (about 45 lines of Lua on LuaTeX's `glyph_stream_provider` hook) and passed every test, but it relies on luaotfload internals that are not a public API and drops Inter's hinting. Rewriting the finished PDF in `build.sh` would not reach Overleaf or `latexmk` users. Shrinking every gap below about 4.9pt would bend the design to one extractor's bug.

A mixed setup — CTAN Source Sans 3, bundled Inter — passes too, but it was rejected in favor of one consistent source: either every family comes from CTAN or none does. The regular fix belongs upstream: if the CTAN `inter` package also shipped the TrueType files that upstream Inter releases include, the class could load them with no hack and no bundling.

**The bundled Inter is 3.019, not 4.0, by choice.** Inter 4.0 sets visibly darker at the same nominal weight, and the lighter 3.019 was preferred for body text. Source Sans and Source Code Pro are current releases (3.052 and 2.042).

### Icons and ToUnicode

Icon fonts live in Unicode's Private Use Area (`U+E000`–`U+F8FF`), which promises never to carry a public meaning — a font and its user privately agree that, say, `U+F0E0` draws an envelope. A `ToUnicode` map for such a glyph can only assert something meaningless, so historically the PDF writer declined to write one at all. Without a map, extractors fall back to reading the raw glyph *index* as a codepoint — plausible-looking Latin letters injected into the contact line (`Ɵ your_name@email.com × 000-00-0000`) rather than an obvious unknown-character marker.

**LuaLaTeX fixes this at the source.** `luaotfload` builds its own `ToUnicode` per font at load time, so the class patches every FontAwesome glyph's entry to a space right there, with a `\directlua` `luaotfload.patch_font` callback (see the note beside `\RequirePackage{fontawesome5}` in `lucidcv.cls`). *At load time* is also why the callback is registered **before** `fontawesome5` is loaded: a font is patched once, as it is instantiated at a given size, and loading the package instantiates the icon font immediately at the document's normal size. Register the callback after the package and that first instance is already built and never patched — icons set at `\normalsize` then extract as their glyph *names* (`LINKEDIN`, `Github`), while icons at any other size still come out as spaces, so the bug hides wherever the contact line happens not to be `\normalsize`. An icon-inventory check against the class's field table (`tests/src/tests/icon-check.py`) is what catches it. There is no post-processing step to run after `lualatex` finishes — the map is already in the PDF it writes, and icons then extract as a plain space everywhere:

```text
 your_name@email.com 000-00-0000 Address, Street, 00000 Country
```

It is still not the whole story — see *Copy-paste fidelity* for why the class needs a *second*, independent mechanism on top of this one.

### Poppler's default reading order can move a contact field — accepted

`pdftotext` **with no flags** reconstructs a reading order of its own, and on the contact block it sometimes gets it wrong. With icons on and three fields set to the full text width:

```text
pdftotext (default)  : J R | T | a@b.c | | Kosice | | S | Body text here. | github.com/xGoldy
pdftotext -raw       : J R | T | a@b.c | Kosice | github.com/xGoldy | S | Body text here.
pdftotext -layout    : a@b.c |   Kosice |   github.com/xGoldy
mutool draw -F txt   : J R | T | a@b.c | Kosice | github.com/xGoldy | S | Body text here.
```

The last field lands *after* the body. Only poppler's default mode does this: `-raw`, `-layout`, `mupdf`, `pdfium`, PDFBox, pdfminer, Tika and pdf.js all return the declared order. The content stream and the physical layout are both correct, so **this is poppler's heuristic, not a malformed PDF** — which is why it is accepted rather than fixed. The likely trigger is the empty-`ActualText` AccSupp span wrapped around each icon: zero-width marked content the heuristic mis-sorts. Under `noicons` the reordering disappears entirely.

Two things to know rather than worry about:

* **The shipped variants keep every field ahead of the body**, so no résumé in this repository is currently affected. It is a layout-dependent accident, not a property of the class — the block wrapping onto two lines does *not* prevent it. What default mode does not guarantee even here is the order *within* the block: in `1c1p` it returns `linkedin` last though it is declared fourth.
* **The harness already covers this mode.** `tests/out/*/poppler.txt` is flagless `pdftotext`, so a layout change that starts relocating a field shows up as a regression without anything being added.

If it ever matters for a specific target, `noicons` removes the cause outright and is the option built for exactly that kind of parser.

### Copy-paste fidelity

A PDF has no line breaks and no notion of "this glyph is decoration" — viewers reconstruct both, and they disagree with each other.

**Icons extract as a space, and it takes two mechanisms, not one.** Every icon carries an *empty* `accsupp` ActualText, which poppler, PDFBox and Tika honor. pdfium, pdf.js and Ghostscript ignore ActualText and read the font's `ToUnicode` instead — which is exactly what the `\directlua` patch above supplies. Neither mechanism alone covers every engine; together they do.

**An icon must never carry a label.** The ActualText is empty and the ToUnicode patch maps to a space — never to `email:` or `Envelope`. A word in the extracted CV that the author never wrote is worse than no word at all (see *Never label an icon with ActualText*). The practical consequence: write contact values that speak for themselves — `linkedin.com/in/your_id`, not a bare `your_id`. The field system does this for you, which is why a declared prefix is split into a hidden scheme and a shown remainder: `\linkedin{your_id}` prints `linkedin.com/in/your_id` and links the whole URL, and `[noprefix]` is there for the cases where you deliberately want the short form. The underscore needs no escaping either — see *Escaping in a contact value*.

A `|` marks the boundary between contact items, both with and without `noicons` — `\cvinfodelim` draws it unconditionally, and the mode changes only the gap on the icon side (`\cvinfodelimgapicon`, `0.2em`, against `\cvinfodelimgap`, `0.4em`). It extracts as part of the contact line, so a parser sees `a@b.com | Bratislava, Slovakia | …` whichever mode you build in. It is an explicit boundary rather than a fix for anything — the ToUnicode patch already makes every engine read icons as plain space — and `\cvinfodelimmark` changes the character if you want a different one.

### Never label an icon with ActualText

Worth writing down, because it is the obvious thing to try and it is a trap. Giving each contact icon an ActualText of `email:`, `github:` and so on reads like pure benefit. poppler 22.02 computes the *position* of ActualText replacement text incorrectly, drifting further right and down the page with each span — in this layout `mailaddress:` landed inside the right-hand column and `github:` below the header entirely, scattering a select-all through the whole document. Empty ActualText contributes no text, so it has no position to get wrong. This is the same poppler defect as *Why not small caps*, showing a different face: there it deletes spans past a count limit, here it misplaces the ones it keeps. The rule that falls out of both: **ActualText is safe for suppressing a glyph, and unsafe for carrying content.**

### Line breaks are always inferred, never encoded

A PDF stores glyphs and positions and nothing else. Every line break a reader shows you was reconstructed by the viewer, and so was every word gap — neither is encoded in the file. The header is where that bites hardest, because it is the one place in the document where three elements (first name, last name, tagline) sit on stacked lines with **no space token anywhere between them**: each is placed by the class, not typed as running text. Left alone, extractors returned `FirstnameLastname` and `Firstname LastnameTagline`.

The header therefore carries **three U+00A0 glyphs**, each fixing a different failure. U+00A0 is a real space *character*, so it is content an extractor reads rather than geometry it has to infer — that is the whole idea. They are marked in the source as `Hacky fix -- part 1` (glyph 3, in `\lcv@headerbreak`) and `part 2` (glyphs 1 and 2, in `\makecvheader`).

| # | Placed | Box width | Sized in | Fixes |
| - | ------ | --------- | -------- | ----- |
| 1 | between first and last name | one interword space (`\fontdimen2`) | the name font | `FirstnameLastname` fusing into one word |
| 2 | closing the name block | zero (`\makebox[0pt]`) | the **tagline's** font | the name/tagline break in untagged readers |
| 3 | opening the tagline | zero (`\makebox[0pt]`) | tagline font **minus 1pt** | the same break in tagged readers |

**Glyph 1 — word fusion.** The gap between the first and last name would normally be TeX glue, which is positioning, and positioning is exactly what an extractor has to guess at. Replacing it with a real space character of the same width (`\fontdimen2` of the name font, so the rendered gap is unchanged) turns the guess into a read. This is the same rule the chips rely on — see *Chips*, where the glyph must **replace** the glue rather than sit beside it.

**Glyph 2 — the break, untagged.** pdf.js decides a line has ended when the vertical move between text runs exceeds the height of *the run being left*. The glyph closing the name block is therefore sized in the tagline's font, not the name's: it is the run being left, and the tagline's leading is what decides the vertical drop. Zero-width, so it adds no advance.

**Glyph 3 — the break, tagged.** In a tagged document the tagline is its own structure element, so the break flag lands on a marked-content boundary instead of on a text run, and the viewer discards it. A zero-width U+00A0 **one point smaller** than the tagline opens a new text run *inside* that marked content for the flag to land on. The size delta is the mechanism, and it is narrow in both directions: at equal size no new run starts and no break appears; much smaller and `txtwrite` re-indents its output.

Because glyphs 2 and 3 have zero advance and glyph 1 replaces glue of its own width, the rendered page is pixel-identical with or without all three.

Two limits worth knowing. `\nametaggap` set too negative (below roughly −6pt) undoes glyph 2 by shrinking the vertical drop back under pdf.js's threshold; the class measures this at `begindocument` and warns rather than silently shipping a fused header. And viewers on pdf.js 2.5 or older cannot be helped from the document side at all — their text layer carries no line-break markup, tagged or not. No ATS runs a browser text layer, so that one is a cosmetic viewer issue and nothing more.

### Chips

**If you want chips, `\cvtaglist` is the way to set them** — it takes a comma-separated list and inserts the delimiters itself:

```latex
\textbf{Technical:} \cvtaglist{C++, Embedded Systems, Statistical Analysis}
```

extracts as `C++ – Embedded Systems – Statistical Analysis` — an explicit delimiter between every pair, no stray spaces, in all thirteen configurations. Empty items are skipped, so a trailing comma costs nothing. `\cvtaglistmark` is the delimiter, `taglistmark` (`CVGrey`) its color and `\cvtaglistgap` the air around it (`0.2em`).

**The delimiter must be a stroke, not a dot, and that is a measured constraint rather than a matter of taste.** The mark used to be `\textbullet`, and it cost one phrase on the OCR path in every layout: Tesseract read the `•` as `«`, so the delimited string never matched even though every skill *word* was recovered. Sixteen candidates were built and OCR'd at 300 dpi against the real sample, and the split is clean:

| Mark | Tesseract returns | Usable |
| --- | --- | --- |
| `–` en dash, `—` em dash | `—` | **yes** — `check.py`'s dash folding treats the two as one character |
| `\|` bar | `\|` | **yes**, glyph for glyph |
| `•` bullet — plain, large, bold, black | `«`, `¢`, `e`, `*` | no |
| `·` middot — plain, large, bold | `-`, `+`, `*`, `°` | no |
| `/`, `;` | `\/`, `):` | no |

Every round mark fails and every stroke survives, at every size and weight tried.

**There is a second, independent cause, and it only shows in `compressed`.** With the en dash in place the plain builds came back clean while both compressed ones returned `C++ )— Embedded Systems` — the `)` is the first chip's own right border. The chip is not built differently in that mode: measured in both, the box is `91.0674 × 11.9822pt` at `8.9663pt` either way, and every one of the class's `compressed` branches touches vertical spacing alone. What changes is where the line lands. `compressed` tightens a dozen skips above it, so the chip sits at `291.84pt` plain and `243.29pt` compressed — sub-pixel phase `0.997` against `0.718` on the 300 dpi raster. A hairline stroke antialiases differently at a different phase, and at the old `draw=accent!35` there was enough ink left for Tesseract to resolve a character out of it.

Widening the *gap* does not help — at `\cvtaglistgap` `0.45em` the `)` is still there. What helps is lowering the border's **contrast** or its **stroke width**, and those two are separate knobs rather than one. Seventeen combinations were built and OCR'd in both compressed variants:

| tint \ width | 0.15pt | 0.20pt | 0.25pt | 0.30pt | 0.40pt | 0.60pt |
| --- | --- | --- | --- | --- | --- | --- |
| `accent!15` | | | | | pass | |
| `accent!20` | | | | | pass | |
| `accent!25` | | | | | pass | pass |
| `accent!30` | | | **pass** | pass | pass | |
| `accent!35` | | pass | pass | pass | **FAIL** | |
| `accent!40` | pass | | **FAIL** | | | |
| `accent!45` | pass | | | | | |
| `accent!50` | pass | | | | | |
| `accent!60` | | **FAIL** | | | | |
| `accent!70` | | **FAIL** | | | | |

The shipped setting is `draw=accent!30,line width=0.25pt` — the one cell with a measured pass on *both* sides of it: raising the tint to `accent!35` or widening to `0.40pt` each still pass, so it is an interior point rather than one riding a cliff. `accent!30` at the default `0.40pt` and `accent!35` at `0.25pt` both pass too, but each sits one step from a failure.

**Do not try to interpolate this table with a formula.** Two were tried and both were falsified by their own predictions: `tint × width` (broken by `accent!25` @ 0.6pt passing while `accent!60` @ 0.2pt failed) and `tint × min(1, width in px)` (broken by `accent!50` @ 0.15pt and `accent!35` @ 0.25pt both passing when it predicted failure). The table is measurement, not model. The one generalization that holds across all seventeen points is that thinning the stroke raises the tint you can afford, and widening past about one pixel costs nothing.

Re-measure rather than reason if you restyle the chip: this is one engine (Tesseract 4.1.1) at one resolution, and the effect depends on where the line happens to fall on the raster. If you change the mark, re-check the extracted text in both `onecolumn` and `compressed` variants with `tests/pipeline.sh` (`--opt compressed` for the second) — nothing else will remind you if it drifts.

**Chip text is set at `\cvtagfontscale` (`0.9`) of the class size option**, the same factor and the same mechanism as the header's contact line: `\normalsize` first, so the scale comes from the declared size rather than from whatever font the chip is dropped into. A drawn rectangle reads as extra visual weight, so a chip set at body size looks *larger* than the text around it; at `0.9` the chip and its padding come out to 90% of the body-size box (measured: `12.77pt` tall → `11.49pt`) and sit level with the running text. The node's paddings are in `ex`, and TikZ resolves those against the font in force when it parses the node's options — so the size switch happens *before* the node opens rather than through the node's own `font=` key, which would leave body-size padding around smaller text and make the chip look emptier instead of smaller. `\cvtagleading` (`1.2`) is its baselineskip factor.

The box is not padded symmetrically. The node's `text height` (`1.45ex`) sets the height it assumes *above* the baseline and `text depth` (`0.4ex`) the part below, and the top gets the larger share on purpose: a capital is flat and full width where a descender is thin and rounded, so an equal numeric gap reads tighter over a capital. Measured at the shipped size, the clearance is `1.78pt` above the caps against `1.62pt` under the descenders. The extra `0.24pt` is absorbed by the line's existing leading — the chip line and everything after it stay exactly where they were.

**If you set chips by hand with `\cvtag`, write nothing between them but a space.**

```latex
\cvtag{C++} \cvtag{Embedded Systems}    % yes
\cvtag{C++}, \cvtag{Embedded Systems}   % no -- extracts as `C++ , Embedded Systems'
```

A chip is a TikZ node, and a node pads its text by `inner xsep`. That padding sits between the last glyph and whatever follows the closing brace, so a comma written outside the chip reads to a geometry-based extractor as a word break, leaving a stray space before every mark. This is not specific to TikZ; any construct that pads a box does the same. `\cvtaglist` exists precisely so you do not have to think about it.

**How the internals defend extraction**, since two of them are easy to undo by accident. `\cvtag` inserts a real space-character glyph on each chip's leading edge — old pdf.js will not synthesize a word gap across a TikZ node's own PDF text object, and returned `C++Embedded Systems` without it. It also rewrites its own argument, splitting on spaces and rejoining with an explicit space glyph, because LaTeX suspends tagging inside a `pgfpicture`: without that, a multi-word chip falls back to a bare positioning offset and Ghostscript fuses it to `EmbeddedSystems`. The glyph must *replace* the glue rather than sit beside it — doing both was tried: it fixed Ghostscript but broke poppler and current pdf.js, which then read a doubled space.

Both are exposed, because they are real trade-offs rather than settings with one right answer: `\cvtagspace` (the leading glyph) and `\cvtagsep` (the gutter after each chip, `0.2em`). `\renewcommand{\cvtagspace}{}` gives single spacing everywhere at the cost of old pdf.js fusing unpunctuated chips together.

## Files

```text
lucidcv.cls       the class -- self-contained, only stock TeX Live packages (`framed` among them)
main.tex          document settings and the header -- compile this one
contents.tex      the body, \input inside main.tex's cvbody -- a sample software
                  engineering CV that uses every body macro; README.md
                  documents each of them
photo.jpg         the header photo main.tex points \cvphoto at
README.md         overview, setup, usage and ATS testing -- start here
resources/        docs.md -- this file, the class reference behind that
                  README -- report.html, the latest test-suite report, and
                  examples/, page renders of the three layout variants shown in
                  README.md
build.sh          builds main.tex into resume.pdf here -- see *Compiling*
package.sh        builds dist/lucidcv.zip, the CTAN/Overleaf package: class,
                  fonts, sample, README and both compiled to PDF -- no tests/,
                  resources/ or build.sh
.github/          workflows/release.yml -- runs package.sh on a v* tag and attaches
                  the zip to a draft GitHub Release
latexmkrc         selects LuaLaTeX, for Overleaf and any local latexmk build
                  (must sit at the project root to take effect on Overleaf;
                   `latexmk -c` leaves .fdb_latexmk behind)
fonts/            Inter, Source Sans 3, Source Code Pro (SIL OFL, see each OFL.txt)
tests/            the thirteen-configuration extraction harness every measurement in this
                  file came from -- not needed to build, see *ATS and accessibility
                  notes*
LICENSE           the full license texts, see *Licenses*
```

`framed` is a **hard dependency**, not an optional one. Every `cvgroup` goes through `\MakeFramed`, whether or not `rule` is given: the package owns the indent, the rule and the page split that lets a long group break across pages, and the `rule` key only chooses which `\FrameCommand` is installed. Drop it and no `cvgroup` works at all — which is also why a TeX Live install missing `framed.sty` cannot build this class, worth knowing before reporting that as a class bug.

`graphicx` is the one that really is optional: tikz pulls it in anyway, and it is kept loaded so a document can rely on `\includegraphics` being available without asking for it. Deferring it to first use would trade one package load for a conditional-loading mechanism to maintain, and the "stock TeX Live packages only" claim above holds either way. `hyperref` is loaded **last**, after `geometry`, by the usual convention: it patches internals belonging to packages loaded before it.

The compiled PDF lands in the project root as `resume.pdf`. Three typefaces, thirteen files: Inter Light/SemiBold plus their real italics for body text, Source Sans 3 Light/Semibold/Bold/Italic/SemiboldItalic for all display text — name, headings, entry titles, tagline, contact line — and Source Code Pro Light/Semibold plus their italics for `\texttt`. All thirteen are `.ttf` deliberately, for the reason in *Copying out of pdf.js viewers*. These are the official Inter 3.019, Source Sans 3.052 and Source Code Pro 2.042 hinted TrueType files. PlushCV's third face, Office Code Pro D, is a Source Code Pro derivative; the upstream face replaces it, at Light rather than Regular so code matches the weight of the Inter Light body. If you repoint a `UprightFont=`/`BoldFont=` at another weight, copy that `.ttf` in from the upstream family.

## Licenses

* PlushCV — © Shubham Mazumder, Apache License 2.0 (itself derived from Deedy-Resume by Debarghya Das)
* Inter, Source Sans 3 and Source Code Pro — SIL Open Font License, text in `fonts/inter/OFL.txt`, `fonts/sourcesans3/OFL.txt` and `fonts/sourcecodepro/OFL.txt`

`lucidcv.cls` itself is under the LaTeX Project Public License, version 1.3c or later, with the maintenance status `maintained` and Patrik Goldschmidt as Current Maintainer. Its header carries that notice, the PlushCV attribution and the note on the bundled font licenses. The Work the notice covers is the template — `lucidcv.cls`, `main.tex`, `latexmkrc`, `README.md` and this file — while all other files, including the scripts (`build.sh`, `package.sh`) and the test suite in `tests/`, are under the MIT License, and the bundled fonts keep their own OFL terms. `LICENSE` holds the full texts.

What LPPL asks of a fork: a modified class has to identify itself as modified where it announces itself (the `\ProvidesClass` line), say what was changed, and ship or point at an unmodified copy of the original.

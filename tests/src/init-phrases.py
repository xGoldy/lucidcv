#!/usr/bin/env python3
"""Derive the phrase list from the document that is supposed to contain it.

Author: Patrik Goldschmidt
Date: 2026-09-06, last rev. 2026-10-05

The phrase list says what has to survive extraction. Kept by hand it
drifts: an edit to the body that renames an entry leaves the old string in
the list, where it fails as a regression that is really a stale fixture -- or,
worse, the new string is never added and simply goes untested. This reads the
sources and writes the list, so the two cannot disagree.

    ./src/init-phrases.py <main.tex>                write the list to stdout
    ./src/init-phrases.py <main.tex> --out=FILE     ... to FILE instead
    ./src/init-phrases.py <main.tex> <body.tex> ... read those bodies instead

The body is whatever main.tex \\input's, resolved from main.tex's own folder --
the root main.tex names the contents.tex beside it, and so does a main.tex in
a subfolder. Name a body file explicitly only to score one
main.tex does not use.

The list goes to STDOUT by default, so it can be read, piped or diffed against
the current one without touching anything:

    ./src/init-phrases.py <main.tex> | diff out/<label>/phrases.txt -

Only `--out' writes. Progress goes to stderr either way, so redirecting stdout
gets the list and nothing else.

The SOURCES are the input, not the built PDF, and that is the whole point. The
phrase list states what the document is supposed to say; the PDF is the thing
under test. Deriving the list from the PDF's own text layer would make the
suite tautological -- a heading the class silently failed to draw would never
enter the list, so nothing would ever miss it. Reading the .tex is what lets
run.sh answer "did this build lose something".

What it reads:

  main.tex      \\name/\\fullname, \\tagline, and every field inside
                \\cvpersonalinfo -- the header group order.py reports but never
                fails on. Also \\addbibresource, to find the .bib below.
  the .cls      the \\CvInfoField declarations, for each field's shown prefix.
                \\linkedin{id} draws `linkedin.com/in/id', not a bare `id', so
                the prefix belongs in the phrase and only the class knows it.
  the body      (what main.tex \\input's) every \\cvsection, \\cvsubsection,
                \\cventry, \\cvsubentry, \\cvref, \\cvtag and \\cvtaglist, the
                items of every itemize, and the
                running paragraphs between them.
  the .bib      the title of each entry, because \\printbibliography renders
                those into the document and nothing in the .tex names them.

What it leaves out, and why:

  the wheelchart   its labels are set on a rotated arc. They extract, but in an
                   order no engine agrees on, so scoring them measures the
                   renderer rather than the document. run.sh has never covered
                   them, and the file header has always said "outside the
                   wheelchart".
  empty arguments  \\cventry{Third achievement}{}{} contributes one phrase.

What it keeps: every phrase, in source order, repeats included. A location
listed under three jobs is three phrases, and a heading that also occurs inside
a bullet is still a phrase of its own. The scorers give each listing a separate
occurrence in the extraction, so neither is found for free -- see locate() in
common.py.

This is a source-level approximation of what LaTeX will draw, not a renderer.
It handles the class's own macros and the TeX spellings the sample uses; it
does not expand arbitrary macros, and it cannot know what a package you add
will put on the page. After regenerating, run the suite: a phrase this got
wrong shows up as every engine losing exactly that phrase.
"""

import pathlib
import re
import sys
import unicodedata

from common import HEADER_GROUP, norm

#: Set on a rotated arc; see the module docstring.
SKIP_MACROS = {"wheelchart"}

#: Structural macros that draw no text of their own.
IGNORE_MACROS = {
    "cvdivider", "cvcolumnbreak", "newpage", "clearpage", "par",
    "smallskip", "medskip", "bigskip", "vspace", "hspace", "vfill", "hfill",
    "nocite", "mynames", "addbibresource", "bibliography", "centering",
    "noindent", "makecvheader", "cvphoto", "lastupdated",
}

#: Macros taking one group that must be swallowed rather than read as text.
IGNORE_WITH_ARG = {"nocite", "mynames", "addbibresource", "bibliography",
                   "vspace", "hspace", "cvphoto"}

#: \cmd{text} that sets `text' in a different font but still draws it. Matched
#: as one alternation and applied until it stops changing, so nesting unwraps.
FONT_MACROS = ("textbf", "textit", "textsc", "texttt", "emph", "underline",
               "textnormal", "textsuperscript", "textsubscript", "mbox")
_FONT_RE = re.compile(r"\\(?:" + "|".join(FONT_MACROS) + r")\s*\{")

#: TeX spellings -> the character the engine actually draws.
LITERALS = [
    (r"---", "\u2014"), (r"--", "\u2013"),
    # Each pattern is a REGEX: a TeX control sequence needs two backslashes
    # here. `\;' would match a bare semicolon and silently eat it.
    # \, \: \; draw a real space glyph: the class sets them as glue, not kern.
    (r"\\ ", " "), (r"\\,", " "), (r"\\:", " "), (r"\\;", " "), (r"~", " "),
    (r"\\&", "&"), (r"\\%", "%"), (r"\\#", "#"), (r"\\_", "_"),
    (r"\\\$", "$"), (r"\\\{", "{"), (r"\\\}", "}"),
    (r"``", "\u201c"), (r"''", "\u201d"), (r"\\\\", " "),
    (r"\\LaTeX\b\s*", "LaTeX "), (r"\\TeX\b\s*", "TeX "),
]

#: TeX accent commands -> the Unicode combining mark that composes with the
#: letter they sit on. `\v{c}' is a c with a caron, drawn as one glyph.
ACCENTS = {"'": "\u0301", "`": "\u0300", "^": "\u0302", '"': "\u0308",
           "~": "\u0303", "=": "\u0304", ".": "\u0307", "v": "\u030C",
           "u": "\u0306", "H": "\u030B", "c": "\u0327", "k": "\u0328"}

#: Symbol accents take the letter with or without braces (`\'a', `\'{a}'); the
#: letter-named ones (`\v', `\c') need the braces, or `\vspace' would match.
_ACCENT_RE = re.compile(
    r"\\(?:([`'^\"~=.])\s*\{?\s*([A-Za-z])\s*\}?"
    r"|([vucHk])\s*\{\s*([A-Za-z])\s*\})")

#: A control word and the blanks after it, and a blank line (paragraph end).
_MACRO_RE = re.compile(r"\\([A-Za-z@]+)\*?\s*")
_HREF_RE = re.compile(r"\\href(?![A-Za-z@])\s*")
_FIELD_RE = re.compile(r"\\([A-Za-z@]+)\s*")
_PARAGRAPH_RE = re.compile(r"\n\s*\n")


def _accent(m):
    if m.group(1):
        mark, letter = m.group(1), m.group(2)
    else:
        mark, letter = m.group(3), m.group(4)

    return unicodedata.normalize("NFC", letter + ACCENTS[mark])


# ---- Reading TeX -----------------------------------------------------------
def strip_comments(text):
    """Drop everything after an unescaped `%', keeping the line structure."""
    out = []

    for line in text.splitlines():
        i, esc = 0, False

        while i < len(line):
            if esc:
                esc = False
            elif line[i] == "\\":
                esc = True
            elif line[i] == "%":
                line = line[:i]
                break
            i += 1

        out.append(line)

    return "\n".join(out)


def read_group(s, i, open_c="{", close_c="}"):
    """Balanced group starting at s[i]; returns (content, index past it)."""
    if i >= len(s) or s[i] != open_c:
        return None, i

    depth, j = 0, i

    while j < len(s):
        if s[j] == "\\":
            j += 2
            continue

        if s[j] == open_c:
            depth += 1
        elif s[j] == close_c:
            depth -= 1

            if depth == 0:
                return s[i + 1:j], j + 1
        j += 1

    return None, i


def read_args(s, i, spec):
    """Read a macro's arguments. `spec' is a string of `o' (optional) and `m'."""
    args = []

    for kind in spec:
        while i < len(s) and s[i] in " \n\t":
            i += 1

        arg, i = (read_group(s, i, "[", "]") if kind == "o"
                  else read_group(s, i))
        args.append(arg)

    return args, i


def unlink(s):
    """`\\href[opts]{url}{text}' draws `text'; the URL is only the link target.

    Left to the generic macro strip below, both groups would survive and the
    phrase would read `https://host/path host/path' -- a phrase no engine can
    find. The text keeps its braces, so it stays a group of its own.
    """
    while True:
        m = _HREF_RE.search(s)

        if not m:
            return s

        (_opt, url, text), end = read_args(s, m.end(), "omm")

        if url is None or text is None:   # malformed: leave it to the strip
            return s

        s = s[:m.start()] + "{" + text + "}" + s[end:]


def detokenize(raw):
    """The visible text of a source fragment, as closely as we can tell."""
    s = unlink(raw or "")

    # \textbf{x} and friends draw x; take the content and drop the wrapper.
    while True:
        s, n = _FONT_RE.subn("{", s)

        if not n:
            break

    s = _ACCENT_RE.sub(_accent, s)

    for pattern, repl in LITERALS:
        s = re.sub(pattern, repl, s)

    # Whatever macros remain draw nothing we can predict; drop the control
    # sequence and keep any text it was wrapping.
    s = re.sub(r"\\[A-Za-z@]+\*?", " ", s)
    s = s.replace("{", " ").replace("}", " ")
    s = re.sub(r"\s+", " ", s).strip()

    # A group boundary is not a word gap: `\textit{IM 2021}, pp.' draws
    # `IM 2021, pp.', and the space the braces left would fail every engine.
    s = re.sub(r"\s+([,;:.!?)\u201d])", r"\1", s)

    return re.sub(r"([(\u201c])\s+", r"\1", s)


# ---- The header, from main.tex ---------------------------------------------
def class_source(main_path, main_src):
    """The .cls main.tex loads, beside it or in a folder above it.

    The eight built-in contact fields are declared in the class, not in the
    document, so their shown prefixes are only readable from there. A main.tex
    in a subfolder of the template finds the class in a folder above it through
    TEXINPUTS, so looking only beside it would quietly score
    `linkedin.com/in/id' as a bare `id'.
    """
    m = re.search(r"\\documentclass\s*(?:\[[^\]]*\])?\s*\{([^}]*)\}",
                  strip_comments(main_src))

    if not m:
        return ""

    name = m.group(1).strip() + ".cls"
    here = main_path.resolve().parent

    for folder in (here, *here.parents):
        if (folder / name).exists():
            return (folder / name).read_text(encoding="utf-8")

    print(f"init-phrases.py: {name} not found beside or above "
          f"{main_path.name}; built-in contact fields will be scored "
          "without their shown prefixes", file=sys.stderr)

    return ""


def parse_info_fields(*sources):
    """Map each declared contact field to (shown prefix, takes a target).

    \\CvInfoField[*][scheme][shown]{name}{icon} splits the link prefix in two
    and prints only the second half, so `shown' is the part that reaches the
    page ahead of the value. The starred form takes its target as a second
    mandatory argument, which callers of the map have to skip.
    """
    fields = {}

    for src in sources:
        s = strip_comments(src or "")

        for m in re.finditer(r"\\CvInfoField(\*?)", s):
            (_scheme, shown, name, _icon), _ = read_args(s, m.end(), "oomm")

            if name:
                fields[name.strip()] = (shown or "", bool(m.group(1)))

    return fields


def parse_header(text, fields=None):
    """The contact block: name, tagline and every \\cvpersonalinfo field."""
    out = []
    s = strip_comments(text)

    m = re.search(r"\\name\s*\{", s)

    if m:
        (first,), i = read_args(s, m.end() - 1, "m")
        (last,), _ = read_args(s, i, "m")
        out.append(f"{detokenize(first)} {detokenize(last)}".strip())
    else:
        m = re.search(r"\\fullname\s*\{", s)

        if m:
            (full,), _ = read_args(s, m.end() - 1, "m")
            out.append(detokenize(full))

    m = re.search(r"\\tagline\s*\{", s)

    if m:
        (tag,), _ = read_args(s, m.end() - 1, "m")
        out.append(detokenize(tag))

    # Everything inside \cvpersonalinfo. A field draws its shown prefix and
    # then its value, so the phrase is the two joined: \github{xGoldy} draws
    # `github.com/xGoldy'. \<field>[noprefix]{value} keeps the prefix in the
    # link but drops it from the page, so the phrase drops it too. A macro no
    # declaration covered contributes its first argument, which is what an
    # unrecognised one would have drawn anyway.
    fields = fields or {}
    m = re.search(r"\\cvpersonalinfo\s*\{", s)

    if m:
        block, _ = read_group(s, m.end() - 1)
        i = 0

        while i < len(block):
            hit = _FIELD_RE.search(block, i)

            if not hit:
                break

            name, i = hit.group(1), hit.end()
            shown, starred = fields.get(name, ("", False))
            (keys, value), i = read_args(block, i, "om")

            if starred:                       # skip the explicit target
                _target, i = read_group(block, i)

            if value is None:
                continue

            if keys is not None and "noprefix" in keys:
                shown = ""

            out.append(detokenize(shown + value))

    return [p for p in out if p]


# ---- The body, from the file main.tex inputs --------------------------------
def body_files(main_path, main_src):
    """The files main.tex \\input's, in order -- its body."""
    found = re.findall(r"\\(?:input|include)\s*\{([^}]*)\}",
                       strip_comments(main_src))

    return [main_path.parent / (n if pathlib.Path(n).suffix else n + ".tex")
            for n in found]


def bib_titles(main_path, text):
    """Titles of every .bib entry, newest first -- what biblatex renders."""
    if "\\printbibliography" not in text and "\\bibliography" not in text:
        return []

    entries = []

    for name in re.findall(r"\\addbibresource\s*\{([^}]*)\}", text):
        f = main_path.parent / name
        f = f if f.suffix else f.with_suffix(".bib")

        if not f.exists():
            print(f"init-phrases.py: no such bibliography: {f}", file=sys.stderr)
            continue

        bib = strip_comments(f.read_text(encoding="utf-8"))

        for block in re.split(r"\n@", "\n" + bib)[1:]:
            title = re.search(r"\btitle\s*=\s*\{", block)
            year = re.search(r"\byear\s*=\s*\{?\s*(\d{4})", block)

            if not title:
                continue

            body, _ = read_group(block, title.end() - 1)
            entries.append((int(year.group(1)) if year else 0, detokenize(body)))

    entries.sort(key=lambda e: -e[0])

    return [t for _, t in entries if t]


def split_sidetext(raw):
    """`{Company 1 | Location 1}' is two fields drawn with a bar between."""
    return [detokenize(part) for part in raw.split("|")] if raw else []


def render_taglist(items, mark="\u2013"):
    """\\cvtaglist{a, b, c} draws as `a <mark> b <mark> c'.

    The delimiter is \\cvtaglistmark, an en dash in the shipped class. The three
    items on their own would each collide with the Skills paragraph, so the
    whole rendered string is scored as one phrase -- which is why this has to
    track the class. Change \\cvtaglistmark, change the default here.
    """
    out, depth, cur = [], 0, ""

    for ch in items:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        elif ch == "," and depth == 0:
            out.append(cur)
            cur = ""
            continue

        cur += ch

    out.append(cur)

    return f" {mark} ".join(detokenize(p) for p in out if detokenize(p))


def parse_body(text, pubs):
    """[(section name, [phrase])] in document order."""
    s = strip_comments(text)
    groups, current, pending = [], [], []
    section = None

    def flush():
        """Emit whatever running text has accumulated as one phrase."""
        raw = "".join(pending)
        pending.clear()

        if not raw.strip():
            return

        # A paragraph opening in bold is a label followed by its value --
        # `\textbf{Technical:} C++, ...' draws as one line but reads as two
        # fields, and scoring them separately is what catches losing either.
        m = re.match(r"\s*\\textbf\s*\{", raw)

        if m:
            label, rest = read_group(raw, m.end() - 1)
            value = raw[rest:]

            # Only a `Label:' is split off. A bold author in a citation --
            # `\textbf{P. Goldschmidt}, D. Chuda, ...' -- is part of the line.
            if detokenize(label).endswith(":") or value.lstrip().startswith(":"):
                for part in (label, value.lstrip().lstrip(":")):
                    if detokenize(part):
                        current.append(detokenize(part))

                return

        current.append(detokenize(raw))

    def close_section():
        flush()

        # Text before the first \cvsection is drawn too -- a one-page body may
        # open with a bold `About:' paragraph rather than an About section -- so
        # it is a group of its own (named None, as it has no heading) rather
        # than discarded.
        if section is not None or current:
            groups.append((section, list(current)))

        current.clear()

    i = 0

    while i < len(s):
        if s[i] != "\\":
            # A blank line ends a paragraph; anything else is running text.
            if s[i] == "\n" and _PARAGRAPH_RE.match(s, i):
                flush()

            pending.append(s[i])
            i += 1
            continue

        m = _MACRO_RE.match(s, i)

        if not m:                       # \& and the like: running text
            pending.append(s[i:i + 2])
            i += 2
            continue

        name, after = m.group(1), m.end()

        if name == "cvsection":
            flush()
            (title,), i = read_args(s, after, "m")
            close_section()
            section = detokenize(title)
            continue

        # A sub-heading inside the current section, not a new one: it groups
        # entries (publications by type) rather than opening a section, so it
        # contributes its own phrase and leaves `section' alone.
        if name == "cvsubsection":
            flush()
            (title,), i = read_args(s, after, "m")
            current.append(detokenize(title))
            continue

        # \cventry and \cvsubentry take the same shape -- [keys]{title}{side}
        # {date} -- and draw the same three fields, so they read the same way.
        # A sub-entry is the one inside a cvgroup; nothing here depends on that.
        if name in ("cventry", "cvsubentry"):
            flush()
            (_opt, title, side, date), i = read_args(s, after, "ommm")
            current.append(detokenize(title))
            current.extend(split_sidetext(side))
            current.append(detokenize(date))
            continue

        if name == "cvref":
            flush()
            (who, mail, addr), i = read_args(s, after, "mmm")
            current.extend(detokenize(a) for a in (who, mail, addr))
            continue

        if name == "cvtaglist":
            flush()
            (items,), i = read_args(s, after, "m")
            current.append(render_taglist(items or ""))
            continue

        if name == "cvtag":
            flush()
            (tag,), i = read_args(s, after, "m")
            current.append(detokenize(tag))
            continue

        if name == "printbibliography":
            flush()
            (_opt,), i = read_args(s, after, "o")
            current.extend(pubs)
            continue

        if name == "item":
            flush()
            i = after
            continue

        # `o' after the name so an environment's optional argument is consumed
        # rather than left in the running text: \begin{cvgroup}[rule] would
        # otherwise contribute a phrase reading `rule', and enumitem's
        # \begin{itemize}[...] the whole key list.
        if name in ("begin", "end"):
            flush()
            (_env, _opt), i = read_args(s, after, "mo")
            continue

        if name in SKIP_MACROS:
            flush()
            _args, i = read_args(s, after, "mmm")
            continue

        if name in IGNORE_MACROS:
            flush()
            i = after

            if name in IGNORE_WITH_ARG:
                _args, i = read_args(s, i, "m")

            continue

        # Not ours: leave it in the running text for detokenize to deal with.
        pending.append(s[i:after])
        i = after

    close_section()

    return [(name, [p for p in ph if p]) for name, ph in groups]


# ---- Assembling the file ---------------------------------------------------
def render(groups, main_path, body_paths):
    """The phrase file, section comments and all."""
    lines = [
        "# Visible phrases in lucidcv's document, outside the wheelchart.",
        "# One per line; blank lines and # comments are ignored.",
        "#",
        f"# GENERATED by tests/src/init-phrases.py from {main_path.name} and",
        f"# {', '.join(b.name for b in body_paths)}. Re-run it after editing",
        "# either, rather than editing this file -- a hand-edit is lost the",
        "# next time it runs.",
        "#",
        "# The section comments group the list for reading, with one exception:",
        f"# `{HEADER_GROUP}' is read by order.py, which scores that group but",
        "# never fails on it. See tests/README.md.",
        "",
    ]

    for name, phrases in groups:
        if not phrases:
            continue

        lines += ["", f"# {name}"] + phrases

    return "\n".join(lines) + "\n"


def summarise(groups, total, dest):
    """Where the list went and what is in it -- on stderr, never stdout.

    stdout carries the list itself, so anything else written there would end up
    inside the file a caller redirects it into.
    """
    print(f"init-phrases.py: {dest} -- {total} phrases in "
          f"{sum(1 for _, p in groups if p)} groups", file=sys.stderr)

    for name, phrases in groups:
        if phrases:
            print(f"  {name:<26} {len(phrases):>3}", file=sys.stderr)


def main(main_arg, body_args, out_path):
    main_path = pathlib.Path(main_arg)

    if not main_path.exists():
        print(f"init-phrases.py: no such file: {main_path}", file=sys.stderr)
        return 2

    main_src = main_path.read_text(encoding="utf-8")
    body_paths = ([pathlib.Path(a) for a in body_args]
                  or body_files(main_path, main_src))

    if not body_paths:
        print(f"init-phrases.py: {main_path.name} inputs no body -- name the "
              "body file(s) after it", file=sys.stderr)
        return 2

    for f in body_paths:
        if not f.exists():
            print(f"init-phrases.py: no such file: {f}", file=sys.stderr)
            return 2

    body_src = "\n\n".join(f.read_text(encoding="utf-8") for f in body_paths)

    # The class first, so its built-ins are in place before main.tex adds any.
    fields = parse_info_fields(class_source(main_path, main_src), main_src)
    header = parse_header(main_src, fields)
    pubs = bib_titles(main_path,
                      strip_comments(main_src) + "\n" + strip_comments(body_src))
    body = parse_body(body_src, pubs)

    groups = [(HEADER_GROUP, header),
              ("section headings", [name for name, _ in body if name])]
    groups += [((name or "before the first section").lower(), phrases)
               for name, phrases in body]
    # Every phrase stays, repeats and phrases inside longer ones included: the
    # scorers give each listing an occurrence of its own (locate() in
    # common.py). Only a phrase that folds to nothing is dropped -- there is
    # nothing in it to find.
    groups = [(name, [p for p in phrases if norm(p)]) for name, phrases in groups]

    text = render(groups, main_path, body_paths)
    total = sum(len(p) for _, p in groups)

    if out_path is None:
        sys.stdout.write(text)
        summarise(groups, total, "wrote to stdout")
        return 0

    out = pathlib.Path(out_path)
    old = out.read_text(encoding="utf-8") if out.exists() else None
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")

    what = "unchanged" if old == text else ("updated" if old else "created")
    summarise(groups, total, f"{what} {out}")

    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    target = None                      # None = stdout

    for f in flags:
        if f == "--out" or f.startswith("--out="):
            target = f.partition("=")[2]

            # No default target: overwriting a phrase list is the one thing this
            # must never do without being told where. A bare `--out' and an
            # empty `--out=' are the same mistake, and an empty one would
            # otherwise reach pathlib as `.' and fail with a traceback.
            if not target:
                print("init-phrases.py: --out needs a path -- use --out=FILE",
                      file=sys.stderr)
                sys.exit(2)
        else:
            print(f"init-phrases.py: unknown option {f} -- expected --out=FILE",
                  file=sys.stderr)
            sys.exit(2)

    if not args:
        print("init-phrases.py: usage: init-phrases.py <main.tex> [<body.tex> ...] "
              "[--out=FILE]", file=sys.stderr)
        sys.exit(2)

    sys.exit(main(args[0], args[1:], target))

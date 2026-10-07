#!/usr/bin/env python3
"""Generate the phrase list for one document, build it, and test it.

Author: Patrik Goldschmidt
Date: 2026-09-26, last rev. 2026-10-04

    ./pipeline.sh MAIN                      the document MAIN
    ./pipeline.sh MAIN --opt twocolumn ...  ... with class options appended

MAIN is the document's top-level .tex file -- ../main.tex for the root
document, or a main.tex in its own subfolder of the template. The body is
whatever that file \\input's, resolved from its own folder, so the pipeline
needs to know nothing about either layout.

run.sh is only the test stage: it scores the PDF and the phrase list it is
handed. A score is meaningful only when the two come from the same document,
and this is what guarantees that. In order:

  1. phrases  init-phrases.py MAIN -> out/<label>/phrases.txt
  2. build    build.sh MAIN        -> out/<label>/<label>.pdf
  3. score    run.sh that PDF against that list, under the variant the
              \\documentclass options name
  4. report   out/<label>/pipeline.json, and the verbatim out/<label>/run.log

<label> is the name of MAIN's folder when MAIN is a main.tex -- `lucidcv'
for the root, the subfolder's name otherwise -- and MAIN's own name without
.tex for any other file, with any --opt appended: `lucidcv+twocolumn', so a layout
override never overwrites the plain run's results. The build goes to out/ as
well rather than beside the sources: the PDFs in the template tree are the ones
that ship, and an --opt build is not one of them.

--opt is handed to build.sh, which appends it to the \\documentclass list. The
class takes its options last-wins, so --opt twocolumn overrides a declared
onecolumn, and the variant is worked out from the same list in the same order.

Every check is run through run.sh rather than reimplemented here, so "all the
tests" is defined in exactly one place. Exits non-zero if any stage failed.
"""

import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

from common import ENGINES, OUT_DIR, TESTS_DIR, load_phrases

#: The template under test, which this suite ships inside. Its build.sh compiles
#: every document, and its root goes on TEXINPUTS so a main.tex in a subfolder
#: finds the class.
TEMPLATE_DIR = TESTS_DIR.parent

#: run.sh, which owns the list of checks, and the template's own builder.
RUN_SH = TESTS_DIR / "run.sh"
BUILD_SH = TEMPLATE_DIR / "build.sh"
INIT_PHRASES = TESTS_DIR / "src" / "init-phrases.py"

#: run.sh prints one of these ahead of each check. Splitting the log on them is
#: what lets a gate's verdict be read back without teaching this script how any
#: individual check talks.
SECTION = re.compile(r"^=== (.+) ===$")

#: `poppler          48/80   MISSING 32  <-- REGRESSION' and friends, from
#: check.py's table. The note decides strict vs advisory, which check.py derives
#: rather than lists -- so this reads it off the output instead of guessing.
COVERAGE_ROW = re.compile(r"^(\S+)\s+(\d+)/(\d+)\s+(.*\S)\s*$")


def run(argv, log, env=None):
    """Run a command, tee its output into `log', and return its exit status."""
    proc = subprocess.Popen([str(a) for a in argv], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True,
                            encoding="utf-8", errors="replace", bufsize=1,
                            env=env)

    for line in proc.stdout:
        log.append(line.rstrip("\n"))
        print(line, end="")
        sys.stdout.flush()

    return proc.wait()


def class_options(main_tex):
    """The \\documentclass option list of main_tex, as a list of strings."""
    src = re.sub(r"(?<!\\)%.*", "", main_tex.read_text(encoding="utf-8"))
    m = re.search(r"\\documentclass\s*\[([^\]]*)\]", src)

    return [o.strip() for o in m.group(1).split(",") if o.strip()] if m else []


def variant(options):
    """The run.sh variant a class option list builds, read last-wins.

    lucidcv declares its options with \\DeclareKeys, so each takes an
    explicit value as well -- `compressed=false' is a plain build.
    """
    onecolumn, compressed = True, False

    for option in options:
        key, _, value = option.partition("=")
        on = value.strip() != "false"

        if key.strip() == "onecolumn":
            onecolumn = on
        elif key.strip() == "twocolumn":
            onecolumn = not on
        elif key.strip() == "compressed":
            compressed = on

    return ("onecolumn" if onecolumn else "twocolumn") + \
           ("-compr" if compressed else "")


def build_env():
    """The environment build.sh runs in.

    The source folder first, then the template root, so a subfolder document's
    own files win and the class is still found from a subfolder.
    luaotfload caches each font with the path it was first loaded from, and
    from another folder finds it again only through TTFONTS.
    """
    env = dict(os.environ)
    env["TEXINPUTS"] = f".:{TEMPLATE_DIR}:{env.get('TEXINPUTS', '')}"
    env["TTFONTS"] = f"{TEMPLATE_DIR / 'fonts'}//:{env.get('TTFONTS', '')}"

    return env


def page_count(pdf):
    """Pages in the built PDF, or None without a pdfinfo to ask."""
    if not shutil.which("pdfinfo"):
        return None

    out = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True)
    m = re.search(r"^Pages:\s+(\d+)", out.stdout, re.M)

    return int(m.group(1)) if m else None


def read_gates(log):
    """{check: pass|fail|skipped|report} for each `=== section ===' in a log.

    A check's own last word is its verdict -- every one of them prints a line
    opening `PASS:' or `FAIL:', or `SKIP:' when this machine lacks what it
    needs. whitespace-report.py prints none of them, because it reports rather
    than judges, and comes back as `report'. A FAIL is never overwritten.
    """
    verdicts = {"PASS": "pass", "FAIL": "fail", "SKIP": "skipped"}
    gates, section = {}, None

    for line in log:
        m = SECTION.match(line.strip())

        if m:
            section = m.group(1)
            gates[section] = "report"
        elif section and line[:4] in verdicts and gates[section] != "fail":
            gates[section] = verdicts[line[:4]]

    return gates


def read_coverage(log):
    """{engine: {found, total, mode, note}} from check.py's table in the log."""
    found = {}

    for line in log:
        m = COVERAGE_ROW.match(line)

        if not m or m.group(1) not in ENGINES:
            continue

        engine, n, total, note = m.group(1), *map(int, m.group(2, 3)), m.group(4)

        # An engine already read is check.py's table; a second sighting would be
        # order.py's, which does not use this shape. Keep the first either way.
        found.setdefault(engine, {
            "found": n, "total": total, "note": note,
            "mode": "advisory" if note.startswith("advisory") else "strict",
        })

    return found


def read_order(outdir):
    """order.py's own JSON for this run, or None if it did not get there."""
    f = outdir / "order.json"

    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else None


def pipeline(main_tex, opts):
    """Phrases, build, score, report. Returns the exit status."""
    # Every document is a main.tex in its own folder, so the folder is the
    # only part of the path that tells two of them apart.
    name = main_tex.parent.name if main_tex.name == "main.tex" else main_tex.stem
    label = "+".join([name, *opts])
    outdir = OUT_DIR / label
    pdf = outdir / f"{label}.pdf"
    phrases = outdir / "phrases.txt"
    options = class_options(main_tex) + list(opts)
    log = []

    record = {
        "generated": datetime.datetime.now().astimezone().isoformat(
            timespec="seconds"),
        "label": label, "main": str(main_tex), "options": options,
        "variant": variant(options), "pdf": pdf.name,
    }

    print("#" * 72)
    print(f"##  {label}  --  {main_tex}")
    print(f"##  [{','.join(options)}]  scored as {record['variant']}")
    print("#" * 72)

    # A stale extraction is a green run waiting to happen: an engine that has
    # since stopped working leaves its last .txt behind, and check.py reads
    # whatever is in the directory. The same goes for an old PDF or list.
    if outdir.exists():
        shutil.rmtree(outdir)

    outdir.mkdir(parents=True)

    try:
        # ---- 1. The phrase list, from the document about to be built --------
        if run([sys.executable, INIT_PHRASES, main_tex, f"--out={phrases}"],
               log):
            record.update(stage="phrases", exit=1)
            return 1

        counted = load_phrases(phrases)
        record["phrases"] = {"total": len(counted.all),
                             "body": len(counted.body),
                             "header": len(counted.header)}

        # ---- 2. Build -------------------------------------------------------
        print()
        argv = [BUILD_SH]

        for opt in opts:
            argv += ["--opt", opt]

        if run(argv + [main_tex, pdf], log, env=build_env()):
            record.update(stage="build", exit=1)
            return 1

        record["pages"] = page_count(pdf)

        # ---- 3. Every check, through run.sh ---------------------------------
        print()
        status = run([RUN_SH, pdf, record["variant"], label,
                      f"--phrases={phrases}"], log)

        record.update(stage="score", exit=status, gates=read_gates(log),
                      coverage=read_coverage(log), order=read_order(outdir))

        return status
    finally:
        # ---- 4. Report ------------------------------------------------------
        (outdir / "run.log").write_text("\n".join(log) + "\n",
                                        encoding="utf-8")
        (outdir / "pipeline.json").write_text(json.dumps(record, indent=1),
                                              encoding="utf-8")
        summary(record, outdir)


def summary(r, outdir):
    """One line for the whole run, and where its files went."""
    gates = r.get("gates", {})
    failed = [g for g, v in gates.items() if v == "fail"]
    skipped = [g for g, v in gates.items() if v == "skipped"]
    detail = (", ".join(failed) if failed
              else f"stopped in {r['stage']}" if r.get("exit") else "")

    if skipped:
        detail += f"{'; ' if detail else ''}skipped: {', '.join(skipped)}"

    print("\n=== summary ===")
    print(f"{'FAIL' if r.get('exit') else 'PASS'}  {r['label']}  "
          f"{r['variant']}, {r.get('pages', '?')} pp, "
          f"{r.get('phrases', {}).get('total', '?')} phrases"
          f"{'  --  ' + detail if detail else ''}")
    print(f"\npipeline: {outdir}/")


def usage(msg):
    print(f"pipeline.py: {msg}", file=sys.stderr)
    print("  usage: pipeline.sh MAIN.tex [--opt NAME ...]", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    args, opts, argv = [], [], sys.argv[1:]

    while argv:
        a = argv.pop(0)

        if a == "--opt":
            if not argv or not argv[0]:
                usage("--opt needs a class option name")
            opts.append(argv.pop(0))
        elif a.startswith("--opt="):
            opts.append(a.partition("=")[2])
        elif a.startswith("-"):
            usage(f"unknown option {a}")
        else:
            args.append(a)

    if len(args) != 1:
        usage("name exactly one .tex file")

    main_tex = pathlib.Path(args[0]).resolve()

    if not main_tex.is_file():
        usage(f"no such file: {main_tex}")

    sys.exit(pipeline(main_tex, opts))

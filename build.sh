#!/usr/bin/env bash
#
# Build the résumé: main.tex -> resume.pdf (both next to this script).
# Engine: LuaLaTeX
#
# Author: Patrik Goldschmidt
# Date: 2026-08-27, last update 2026-10-30
#
#   ./build.sh                      build main.tex -> resume.pdf
#   ./build.sh path/to.tex          build something else instead
#   ./build.sh path/to.tex out.pdf  ... and put it somewhere else
#   ./build.sh --opt NAME ...       add a class option for this build only,
#                                   repeatable: --opt twocolumn --opt compressed

set -euo pipefail

# Obtain the script directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Configuration ----------------------------------------------------------
# Local paths to search for the LuaLaTeX binary, in order of preference. Own
# .texenv installation -> user installation -> default install-tl path. Quoted
# so they expand at search time, where each pattern's newest year goes first.
TEXLIVE_BIN_GLOBS=(
  "$ROOT/.texenv/bin/*"
  "$HOME/texlive/*/bin/*"
  "/usr/local/texlive/*/bin/*"
)
# Source/output used when $1/$2 are not given on the command line.
DEFAULT_SRC="$ROOT/main.tex"
DEFAULT_OUT="$ROOT/resume.pdf"
# Warnings of a healthy build to filter out using regex.
WARN_IGNORE=(
  'Neither unicode-math nor lua-unicode-math'
)

# ---- Functions --------------------------------------------------------------
# A Function for one LuaLaTeX pass. Quiet on success, prints errors on failure.
run_pass() {
  if ! lualatex -halt-on-error -interaction=nonstopmode "$1.tex" >/dev/null 2>&1; then
    echo "build.sh: lualatex failed on $1.tex" >&2

    if [[ -f "$1.log" ]]; then
      echo "--- error from $SRCDIR/$1.log ---" >&2
      # Each error from its `!' line up to the first blank line, which keeps
      # multi-line class and package errors whole, plus its `l.N' line.
      awk '/^!/ { err = 1 }
           /^$/ { err = 0 }
           err || /^l\.[0-9]/' "$1.log" | head -30 >&2
      echo "--- full log: $SRCDIR/$1.log ---" >&2
    fi
    if [[ -f "$OUT" ]]; then
      echo "build.sh: $OUT was NOT updated (previous file kept)" >&2
    fi

    exit 1
  fi
}

# Report the log's warnings, and nothing else.
report_warnings() {
  # Save the log into variable and return if it's empty
  local log="$1"
  [[ -f "$log" ]] || return 0

  # Flatten the ignore array into a single regex alternation string
  local ignore="" pat

  for pat in "${WARN_IGNORE[@]}"; do
    ignore+="${ignore:+|}$pat"
  done

  # Collect each warning together with the lines under it, drop the ignored
  # blocks, print the rest. Warnings run until the next blank line.
  local found
  found="$(awk -v ignore="$ignore" -v width=79 '
    function flush() {
      if (buf != "" && (ignore == "" || buf !~ ignore)) printf "%s", buf
      buf = ""; n = 0; inw = 0
    }
    function add(line) {
      # glue onto the previous line when that one was wrapped
      if (prevlen == width) { sub(/\n$/, "", buf); buf = buf line "\n" }
      else                  { buf = buf line "\n"; n++ }
      prevlen = length(line)
    }
    /Warning:|validation failure/ {
      flush(); buf = $0 "\n"; n = 1; inw = 1; prevlen = length($0); next
    }
    inw {
      # blank line ends the warning; the cap is a guard against a runaway block
      if ($0 ~ /^[[:space:]]*$/ || n >= 12) { flush(); next }
      add($0); next
    }
    END { flush() }
  ' "$log")"

  if [[ -n "$found" ]]; then
    echo "build.sh: warnings from $SRCDIR/$(basename "$log") (log kept):" >&2
    printf '%s\n' "$found" | sed 's/^/  /' >&2
    return 1
  fi
}

# ---- Main -------------------------------------------------------------------
# Prepend the first TeX Live binaries found to PATH (else keep the default PATH).
# Globs expand in ascending order, so `sort -r' tries 2026 ahead of 2025.
for glob in "${TEXLIVE_BIN_GLOBS[@]}"; do
  while IFS= read -r d; do
    [[ -x "$d/lualatex" ]] && { PATH="$d:$PATH"; break 2; }
  done < <(compgen -G "$glob" | sort -r)
done

# Parse command line arguments -- particularly focus on document options
OPTS=()

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --opt)
      [[ -n "${2:-}" ]] || { echo "build.sh: --opt needs a name" >&2; exit 1; }
      OPTS+=("$2"); shift 2 ;;
    --opt=*)   OPTS+=("${1#--opt=}"); shift ;;
    --) shift; break ;;
    -*) echo "build.sh: unknown flag: $1  (class options go through --opt)" >&2
        exit 1 ;;
    *) break ;;
  esac
done

# Set the path for source or outputs (args $1/$2 or defaults).
# The output dir has to exist before the source file is resolved.
SRC="${1:-$DEFAULT_SRC}"
OUT="${2:-$DEFAULT_OUT}"
[[ -d "$(dirname "$OUT")" ]] || {
  echo "build.sh: no such directory: $(dirname "$OUT")" >&2; exit 1; }
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

# Test the source file existence and switch to its directory
[[ -f "$SRC" ]] || { echo "build.sh: no such file: $SRC" >&2; exit 1; }
SRCDIR="$(cd "$(dirname "$SRC")" && pwd)"
JOB="$(basename "$SRC" .tex)"

cd "$SRCDIR"

# Adds the requested class options to a temporary wrapper .tex document.
# The wrapper is named after the options, so two concurrent builds of different
# variants cannot overwrite each other's files.
if (( ${#OPTS[@]} )); then
  OPTLIST="$(IFS=,; echo "${OPTS[*]}")"
  WRAP="$JOB-$(IFS=-; echo "${OPTS[*]}")"
  trap 'rm -f "$SRCDIR/$WRAP".{tex,pdf,aux,bbl,bcf,blg,out,run.xml}' EXIT
  # `0,/re/s//../' rewrites only the FIRST match, others documentclass are left.
  sed "0,/\\\\documentclass\(\[[^]]*\)\]/s//\\\\documentclass\1,$OPTLIST]/" "$JOB.tex" > "$WRAP.tex"
  grep -q "\\\\documentclass\\[.*$OPTLIST" "$WRAP.tex" || {
    echo "build.sh: could not add the options ($OPTLIST) to $JOB.tex" >&2
    echo "  the document needs a \\documentclass[...] with brackets" >&2
    exit 1; }
  JOB="$WRAP"
fi

# Clear the output file
rm -f "$JOB.pdf"

# Build the document: JOB is a wrapped source file with additional options
if command -v lualatex >/dev/null; then
  echo "build.sh: lualatex -> $OUT"
  # 3 passes: 1) .bcf for biber, 2) reference resolving, 3) pdf typesetting
  run_pass "$JOB"

  # Reference resolving (only when references exist)
  if [[ -f "$JOB.bcf" ]] && command -v biber >/dev/null; then
    biber --quiet "$JOB"
    run_pass "$JOB"
  fi

  # Final build and determine the number of pages
  run_pass "$JOB"

  PAGES="$(sed -n 's/^Output written on .* (\([0-9]*\) pages\{0,1\},.*/\1/p' "$JOB.log")"

  # Clean up, but keep the log when it has warnings worth reading.
  if report_warnings "$JOB.log"; then
    rm -f "$JOB.log"
  fi

  rm -f "$JOB".{aux,bbl,bcf,blg,out,run.xml}
else
  # No LuaLaTeX found
  echo "build.sh: no lualatex found." >&2
  echo "  TeX Live:  sudo apt install texlive-luatex texlive-latex-extra texlive-fonts-extra biber" >&2
  echo "  No root:   install-tl -texdir ~/texlive/2026  (https://tug.org/texlive/quickinstall.html)" >&2
  echo "  Or compile this directory on Overleaf with Menu > Compiler > LuaLaTeX." >&2

  exit 1
fi

# Check for successful build and move the result
if [[ ! -f "$JOB.pdf" ]]; then
  echo "build.sh: the engine produced no $JOB.pdf" >&2
  exit 1
fi

# Compare device+inode with the output (`-ef'), so the file is not overwritten.
[[ "$SRCDIR/$JOB.pdf" -ef "$OUT" ]] || mv -f "$JOB.pdf" "$OUT"

# Place PDF post processing steps here
# ...

echo "build.sh: wrote $OUT ($PAGES pages)"

#!/usr/bin/env bash

# Package the class for a publication, e.g., for CTAN and Overleaf.
#
# Author: Patrik Goldschmidt
# Date: 2026-10-06, last update 2026-10-30

# The script creates a dist/lucidcv.zip, holding a single lucidcv/ folder
# with the class, fonts, sample, docs and the compiled sample. The test suite
# and resources/ are excluded
#
#   ./package.sh                  build dist/lucidcv.zip
#   ./package.sh --tag v1.0.0     ... and fail unless the class version matches

set -euo pipefail

# Obtain the script directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Configuration ----------------------------------------------------------
NAME=lucidcv

# PDF metadata author of the documentation PDF (not printed on the title page).
AUTHOR="Patrik Goldschmidt"

# Links to files left out of the package point here, at the release's tag.
REPO_URL=https://github.com/xGoldy/lucidcv

# Shipped files and folders, relative to ROOT. Anything not listed stays out.
FILES=(
  lucidcv.cls
  main.tex
  contents.tex
  photo.jpg
  latexmkrc
  LICENSE
  README.md
  fonts
)

SAMPLE_PDF="$NAME-sample.pdf"       # Compiled sample
DOC_PDF="$NAME-doc.pdf"             # Documentation (README converted to PDF)
DIST="$ROOT/dist"                   # Destination folder

# ---- Functions --------------------------------------------------------------
# Write the packaged README $2 from the repository's $1 for release $3: the
# example subsections go (their screenshots are not shipped) and links into
# resources/ and tests/ point at the GitHub copy.
package_readme() {
  local src="$1" dst="$2" blob="$REPO_URL/blob/$3"

  awk -v examples="$blob/README.md#2-examples" '
    /^For additional inspiration, / {
      print "For additional inspiration, three real-world resume variants are" \
            " shown in the [README on GitHub](" examples ")."
      skip = 1; next
    }
    skip && /^## / { skip = 0; print "" }
    !skip
  ' "$src" |
    sed -E "s#\]\((resources|tests)/#]($blob/\1/#g" > "$dst"

  if grep -qE '\]\((resources|tests)/|^### Example' "$dst"; then
    echo "package.sh: README.md still links into resources/ or tests/," \
         "or the examples were not removed -- update package_readme" >&2
    exit 1
  fi
}

# Convert README $1 to the documentation PDF $2 for release $3: pandoc to
# LaTeX, compiled by build.sh like the sample. $4 is a scratch folder.
readme_to_pdf() {
  local readme="$1" pdf="$2" version="$3" work="$4"
  local tex
  tex="$work/$(basename "$pdf" .pdf).tex"

  mkdir -p "$work"
  cat > "$work/filter.lua" <<'LUA'
-- Images and links are dropped (badges are remote, screenshots not shipped).
function Image() return {} end
function Link(link) if #link.content == 0 then return {} end end

-- GFM tables keep natural column widths, which LaTeX never wraps. A table wider
-- than a line gets fixed widths: each column its longest word at least, the
-- rest of the line shared out by how much text the column holds.
local LINE = 85  -- characters per line, a little under body text to fit code

function Table(tbl)
  local len, word = {}, {}
  local function measure(rows)
    for _, row in ipairs(rows) do
      for i, cell in ipairs(row.cells) do
        local text = pandoc.utils.stringify(cell.contents)
        len[i] = math.max(len[i] or 0, utf8.len(text) or #text)
        for w in text:gmatch("%S+") do
          word[i] = math.max(word[i] or 0, utf8.len(w) or #w)
        end
      end
    end
  end
  measure(tbl.head.rows)
  for _, body in ipairs(tbl.bodies) do measure(body.body) end

  local total, least, rest = 0, 0, 0
  for i = 1, #tbl.colspecs do
    len[i], word[i] = len[i] or 0, word[i] or 0
    total, least = total + len[i], least + word[i]
    rest = rest + len[i] - word[i]
  end
  if total <= LINE then return nil end

  local spare, scale = math.max(LINE - least, 0), math.max(LINE, least)
  for i, spec in ipairs(tbl.colspecs) do
    local share = rest > 0 and spare * (len[i] - word[i]) / rest or 0
    tbl.colspecs[i] = {spec[1], (word[i] + share) / scale}
  end
  return tbl
end
LUA

  pandoc "$readme" --from gfm --standalone \
    --lua-filter "$work/filter.lua" --shift-heading-level-by=-1 \
    --metadata subtitle="Version ${version#v}" \
    --variable author-meta="$AUTHOR" \
    --variable papersize=a4 --variable geometry:margin=2cm \
    --variable colorlinks=true \
    --output "$tex"
  "$ROOT/build.sh" "$tex" "$pdf"
}

# ---- Main -------------------------------------------------------------------
# Obtain the tag from command line, if any.
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ -n "${2:-}" ]] || { echo "package.sh: --tag needs a value" >&2; exit 1; }
      TAG="$2"; shift 2 ;;
    *) echo "package.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Obtain version from \ProvidesClass{lucidcv}[YYYY/MM/DD vX.Y.Z ...].
VERSION="$(sed -n 's/^\\ProvidesClass{lucidcv}\[[^ ]* \(v[^ ]*\) .*/\1/p' \
  "$ROOT/lucidcv.cls")"
[[ -n "$VERSION" ]] || { echo "package.sh: no version in lucidcv.cls" >&2; exit 1; }

# Checks: 1) if tag and version match; 2) tool availability
if [[ -n "$TAG" && "$TAG" != "$VERSION" ]]; then
  echo "package.sh: tag $TAG does not match class version $VERSION" >&2
  exit 1
fi

for tool in zip pandoc; do
  command -v "$tool" >/dev/null || { echo "package.sh: no $tool found" >&2; exit 1; }
done

# Stage the package in a temporary folder, removed on exit.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PKG_DIR="$TMP/$NAME"
mkdir -p "$PKG_DIR"

(cd "$ROOT" && cp -r --parents "${FILES[@]}" "$PKG_DIR/")

# Compile the sample
cp -r "$PKG_DIR" "$TMP/build"
"$ROOT/build.sh" "$TMP/build/main.tex" "$PKG_DIR/$SAMPLE_PDF"

# Modify the readme and convert it to a documentation PDF
package_readme "$ROOT/README.md" "$PKG_DIR/README.md" "$VERSION"
readme_to_pdf "$PKG_DIR/README.md" "$PKG_DIR/$DOC_PDF" "$VERSION" "$TMP/doc"

# Normalize permissions; nothing in the package is executable.
find "$PKG_DIR" -type d -exec chmod 755 {} +
find "$PKG_DIR" -type f -exec chmod 644 {} +

# Create the zip file and place it in the dist folder
mkdir -p "$DIST"
rm -f "$DIST/$NAME.zip"
(cd "$TMP" && zip -qrX "$DIST/$NAME.zip" "$NAME")

echo "package.sh: $NAME $VERSION -> $DIST/$NAME.zip"

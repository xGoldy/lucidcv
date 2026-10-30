#!/usr/bin/env bash
#
# Prepare environment (i.e., Python, Java) for running the test suite.
#
# Author: Patrik Goldschmidt
# Date: 2026-09-06, last rev. 2026-10-30
#
#   ./setup.sh                install everything
#   ./setup.sh --no-system    skip the system packages, install the rest
#                             (--no-apt is accepted as the old spelling)
#
# Five stages, in dependency order:
#
#   system   poppler, Ghostscript, Tesseract, a JRE, and the tools the stages
#            below need, through apt-get on Debian and its derivatives or dnf
#            on Fedora and RHEL ones. Touches the system and requires root.
#   venv     a virtualenv at env/python with the three Python extractors in it
#            -- PyMuPDF, pypdfium2 and pdfminer.six.
#   pdfjs    a Node runtime, two pdf.js builds, and the three driver scripts.
#   java     the PDFBox and Tika jars, plus Tika 4 and iText for the two JVM
#            engines that read the structure tree, and their drivers.
#   verapdf  the reference PDF/A validator.
#
# Everything except the system stage lands under tests/env/. Each stage is
# idempotent and skips what is already there, so re-running costs nothing.
# Every stage is optional; an engine whose stage was skipped reports as
# `not run'.
set -euo pipefail

# ---- Configuration ----------------------------------------------------------
PDFJS_OLD=2.5.207          # the vintage embedded in editor viewers
PDFJS_NEW=4.10.38          # 5.x and 6.x need a DOMMatrix that Node gained in 22
NODE=v20.18.1
PDFBOX=3.0.5               # PDFBox 3 and Tika 3 both need Java 11 or newer
TIKA=3.2.3
TIKA_STRUCT=4.2.0          # 3.x skips /MCR kids, i.e. all of LaTeX's; needs Java 17
ITEXT=9.8.0
SLF4J=2.0.16               # the slf4j-api iText $ITEXT is built against
VERAPDF=1.30.2
VERAPDF_SERIES=1.30

PY_PKGS=(pymupdf==1.28.2 pypdfium2==5.13.0 pdfminer.six==20260107)
# The JDK only for its jdk.compiler module, which runs the iText driver from
# source; Fedora's headless JRE already carries it, Debian's does not.
APT_PKGS=(poppler-utils ghostscript tesseract-ocr default-jre default-jdk-headless
          python3-venv curl unzip xz-utils)
# Fedora ships venv inside python3 and names the JRE and Tesseract differently.
DNF_PKGS=(poppler-utils ghostscript tesseract java-latest-openjdk-headless
          python3 curl unzip xz)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$HERE/env"
VENV="$ENV_DIR/python"
MAVEN=https://repo1.maven.org/maven2/org/apache
MAVEN_ROOT=https://repo1.maven.org/maven2
# Tika 4 ships tika-app as a jar plus lib/ only in the release zip; the jar on
# Maven Central is the bare CLI. The archive keeps every release, the mirrors
# only the latest.
APACHE_ARCHIVE=https://archive.apache.org/dist

DO_SYSTEM=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-system|--no-apt) DO_SYSTEM=0; shift ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) echo "setup.sh: unknown flag: $1  (expected --no-system)" >&2; exit 1 ;;
  esac
done

stage() { echo; echo "=== $* ==="; }

# ---- 1. System packages -----------------------------------------------------
# The only stage that leaves tests/env/. Everything here is a released distro
# package; nothing is pinned, because the suite is written against whatever
# poppler and Ghostscript a real machine happens to ship -- that variation is
# part of what it measures.

# Which package manager this distribution uses: /etc/os-release says which
# family it belongs to (ID_LIKE covers Ubuntu, Mint, Rocky, Alma, ...), and
# whichever installer is on PATH settles a system that does not say.
detect_pm() {
  local ids=""

  if [[ -r /etc/os-release ]]; then
    ids=" $(. /etc/os-release; echo "${ID:-} ${ID_LIKE:-}") "
  fi

  case "$ids" in
    *" debian "*|*" ubuntu "*)                 PM=apt ;;
    *" fedora "*|*" rhel "*|*" centos "*)      PM=dnf ;;
    *) if   command -v apt-get >/dev/null; then PM=apt
       elif command -v dnf     >/dev/null; then PM=dnf
       else PM=""; fi ;;
  esac

  if [[ -n "$PM" ]] && ! command -v "${PM/apt/apt-get}" >/dev/null; then
    echo "setup.sh: this looks like a $PM distribution but $PM is not on PATH" >&2
    PM=""
  fi
}

install_system() {
  stage "system packages"

  local PM pkgs sudo=""
  detect_pm

  case "$PM" in
    apt) pkgs=("${APT_PKGS[@]}") ;;
    dnf) pkgs=("${DNF_PKGS[@]}") ;;
    *)
      echo "setup.sh: neither apt-get nor dnf -- install these yourself and" \
           "re-run --no-system:"
      echo "  Debian family:  ${APT_PKGS[*]}"
      echo "  Fedora family:  ${DNF_PKGS[*]}"
      return 0 ;;
  esac

  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null; then
      sudo=sudo
      echo "setup.sh: $PM needs root; using sudo"
    else
      echo "setup.sh: not root and no sudo -- skipping $PM. Install these and" >&2
      echo "          re-run with --no-system:" >&2
      printf '          %s\n' "${pkgs[@]}" >&2
      return 0
    fi
  fi

  if [[ "$PM" == apt ]]; then
    $sudo apt-get update -qq
    $sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}"
  else
    $sudo dnf install -y -q "${pkgs[@]}"
  fi

  echo "setup.sh: installed ${#pkgs[@]} packages with $PM"
}

# ---- 2. The Python environment ----------------------------------------------
# A virtualenv of its own rather than the user's: the three extractors are a
# test dependency, and a suite that installs into whatever Python happens to be
# active is one that breaks somebody's unrelated project. run.sh prefers this
# interpreter and falls back to PATH when it is absent.
install_venv() {
  stage "python virtualenv"

  if [[ ! -x "$VENV/bin/python3" ]]; then
    python3 -m venv "$VENV"
    echo "setup.sh: created $VENV"
  else
    echo "setup.sh: $VENV already present"
  fi

  # Through the interpreter rather than bin/pip: pip's own script hard-codes
  # the path the venv was created at, so it breaks once tests/ is moved.
  "$VENV/bin/python3" -m pip install --quiet --upgrade pip
  "$VENV/bin/python3" -m pip install --quiet "${PY_PKGS[@]}"
  echo "setup.sh: $("$VENV/bin/python3" -V), ${PY_PKGS[*]}"
}

# ---- 3. pdf.js: a Node, two builds, and the two drivers ---------------------
# The drivers are written from here rather than kept in the repository so that
# env/ stays entirely reconstructible from this one file. Edit them here.
write_pdfjs_drivers() {
  cat > "$ENV_DIR/pdfjs/extract-old.cjs" <<'JSEOF'
// Text extraction through pdf.js 2.5.207 -- the vintage still embedded in
// editor viewers, the VS Code PDF extension among them. Its word gaps come from
// SPACE_FACTOR * font.spaceWidth, which falls back to the CID font's /DW, so
// this is the engine that catches a bad /DW -- see "Copying out of pdf.js
// viewers" in ../../../README.md.
//
// Items are joined the way a text layer copy is: nothing between items on the
// same row, a newline when the baseline moves.
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "vendor", "pdfjs-old", "es5", "build");
const pdfjsLib = require(path.join(ROOT, "pdf.js"));
pdfjsLib.GlobalWorkerOptions.workerSrc = path.join(ROOT, "pdf.worker.js");

(async () => {
  const data = new Uint8Array(fs.readFileSync(process.argv[2]));
  const doc = await pdfjsLib.getDocument({ data, disableFontFace: true }).promise;
  let out = "";
  for (let p = 1; p <= doc.numPages; p++) {
    const tc = await (await doc.getPage(p)).getTextContent();
    // 2.5.207 predates hasEOL, so recover rows from each item's baseline.
    let lastY = null;
    for (const it of tc.items) {
      const y = it.transform[5];
      if (lastY !== null && Math.abs(y - lastY) > 0.5) out += "\n";
      out += it.str;
      lastY = y;
    }
    out += "\n";
  }
  process.stdout.write(out);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
JSEOF

  cat > "$ENV_DIR/pdfjs/extract-new.mjs" <<'JSEOF'
// The same harness against current pdf.js -- i.e. what Firefox does today. It
// replaced the spaceWidth-relative heuristic with font-size-relative thresholds
// (TRACKING_SPACE_FACTOR = 0.102), so it is insensitive to /DW and should return
// every phrase whatever the fonts are embedded as.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// pdf.js reports its missing-canvas and missing-DOMMatrix warnings through
// console.log, i.e. on STDOUT, which is the channel this script uses for the
// extracted text. Left alone they land in pdfjs-new.txt and are scored as
// document content -- the banner carries this checkout's path, so the case
// folded word `projects' turned up ahead of `Name Surname' and cost the
// engine a phrase in the reading-order test. Send every console channel to
// stderr before pdf.js is imported; extract.py discards it there.
for (const k of ["log", "info", "warn", "debug"]) {
  console[k] = (...a) => process.stderr.write(a.join(" ") + "\n");
}

const here = path.dirname(fileURLToPath(import.meta.url));
const pdfjsLib = await import(
  path.join(here, "vendor", "pdfjs-new", "legacy", "build", "pdf.mjs")
);

const data = new Uint8Array(fs.readFileSync(process.argv[2]));
const doc = await pdfjsLib.getDocument({ data, disableFontFace: true }).promise;
let out = "";
for (let p = 1; p <= doc.numPages; p++) {
  const tc = await (await doc.getPage(p)).getTextContent();
  for (const it of tc.items) out += it.str + (it.hasEOL ? "\n" : "");
  out += "\n";
}
process.stdout.write(out);
JSEOF

  cat > "$ENV_DIR/pdfjs/extract-struct.mjs" <<'JSEOF'
// Text in STRUCTURE-TREE order, through the same current pdf.js -- what Firefox
// builds its accessibility tree from, and so what a screen reader there reads.
// Each page's text is collected per marked-content id (getTextContent with
// includeMarkedContent) and written in the order the page's structure tree
// references those ids. Nothing else is written: an artifact, or text nobody
// tagged, is never referenced, so it never comes out.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// pdf.js warns on STDOUT; see extract-new.mjs.
for (const k of ["log", "info", "warn", "debug"]) {
  console[k] = (...a) => process.stderr.write(a.join(" ") + "\n");
}

const here = path.dirname(fileURLToPath(import.meta.url));
const pdfjsLib = await import(
  path.join(here, "vendor", "pdfjs-new", "legacy", "build", "pdf.mjs")
);

// Standard inline-level types (ISO 32000-1, 14.8.4.4), after the role map,
// which pdf.js applies. They continue the line; every other element is a
// block and starts one, as a screen reader would break it.
const INLINE = new Set(["Span", "Quote", "Note", "Reference", "BibEntry",
  "Code", "Link", "Annot", "Ruby", "RB", "RT", "RP", "Warichu", "WT", "WP",
  "Lbl", "Em", "Strong", "Sub"]);
const ARTIFACT = Symbol("artifact");

const data = new Uint8Array(fs.readFileSync(process.argv[2]));
const doc = await pdfjsLib.getDocument({ data, disableFontFace: true }).promise;
let out = "";
for (let p = 1; p <= doc.numPages; p++) {
  const page = await doc.getPage(p);
  const tc = await page.getTextContent({ includeMarkedContent: true });
  // A glyph belongs to the innermost enclosing sequence that has an id; an
  // Artifact in between claims it for nobody.
  const byId = new Map();
  const stack = [];
  for (const it of tc.items) {
    if (it.type === "beginMarkedContent" || it.type === "beginMarkedContentProps") {
      stack.push(it.tag === "Artifact" ? ARTIFACT : (it.id ?? null));
    } else if (it.type === "endMarkedContent") {
      stack.pop();
    } else {
      const id = stack.findLast((x) => x !== null);
      if (id === undefined || id === ARTIFACT) continue;
      byId.set(id, (byId.get(id) ?? "") + it.str + (it.hasEOL ? "\n" : ""));
    }
  }
  const walk = (node) => {
    if (node.type === "content") { out += byId.get(node.id) ?? ""; return; }
    if (node.type) return;  // "object" or "annotation": no text of its own
    const block = !INLINE.has(node.role);
    if (block) out += "\n";
    for (const kid of node.children ?? []) walk(kid);
    if (block) out += "\n";
  };
  const tree = await page.getStructTree();
  if (tree) walk(tree);
}
process.stdout.write(out);
JSEOF
}

install_pdfjs() {
  stage "pdf.js"

  local vendor="$ENV_DIR/pdfjs/vendor" arch
  mkdir -p "$vendor"

  case "$(uname -m)" in
    x86_64)        arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "setup.sh: no Node build for $(uname -m); install node yourself" >&2
       return 0 ;;
  esac

  if [[ ! -x "$vendor/node/bin/node" ]]; then
    echo "setup.sh: fetching Node $NODE ($arch)"
    curl -fsSL -o "$vendor/node.tar.xz" \
      "https://nodejs.org/dist/$NODE/node-$NODE-linux-$arch.tar.xz"
    tar xf "$vendor/node.tar.xz" -C "$vendor"
    rm "$vendor/node.tar.xz"
    mv "$vendor/node-$NODE-linux-$arch" "$vendor/node"
  fi

  # Unpacked beside the destination and moved into place only when complete,
  # so an interrupted download is retried rather than taken as present.
  fetch_pdfjs() {   # <version> <destination>
    [[ -d "$2" ]] && { echo "setup.sh: $(basename "$2") already present"; return; }
    echo "setup.sh: fetching pdfjs-dist $1 -> $(basename "$2")"
    rm -rf "$2.part"
    mkdir -p "$2.part"
    curl -fsSL "https://registry.npmjs.org/pdfjs-dist/-/pdfjs-dist-$1.tgz" \
      | tar xz -C "$2.part" --strip-components=1
    mv "$2.part" "$2"
  }

  fetch_pdfjs "$PDFJS_OLD" "$vendor/pdfjs-old"
  fetch_pdfjs "$PDFJS_NEW" "$vendor/pdfjs-new"

  write_pdfjs_drivers
  echo "setup.sh: $("$vendor/node/bin/node" --version), pdf.js $PDFJS_OLD and $PDFJS_NEW"
}

# ---- 4. The JVM extractors --------------------------------------------------
# The JRE is NOT vendored -- at ~180 MB it dwarfs both jars, and any `java' on
# PATH will do. The system stage installs one.
#
# The two structure-tree drivers are written from here for the same reason as
# the pdf.js ones: env/ stays reconstructible from this file. Edit them here.
write_java_drivers() {
  # Tika 4 reads the structure tree by default, but under AUTO a page whose
  # tags it distrusts quietly falls back to the plain stripper -- which is
  # the `tika' engine over again. TAGS follows the tree on every tagged page,
  # so a structure problem shows as a loss instead of being papered over. The
  # PDF parser is excluded from the default parser and declared on its own,
  # so this configuration is the one it runs with; Tesseract is excluded so
  # the photo is not OCR'd into the text.
  cat > "$ENV_DIR/java/tika-struct.json" <<'JSONEOF'
{
  "parsers": [
    {"default-parser": {"exclude": ["pdf-parser", "tesseract-ocr-parser"]}},
    {"pdf-parser": {"markedContent": {"strategy": "TAGS"}}}
  ]
}
JSONEOF

  # Run from source by the java launcher, so no compiler is needed beyond the
  # JDK's jdk.compiler module. TaggedPdfReaderTool dumps the structure tree as
  # XML with every element's marked content as text; extract.py strips the
  # markup. The dump names elements by their own type -- `text-unit', `Em' --
  # so the role map goes ahead of it, one comment per entry, for extract.py to
  # tell an inline element from a block. The one override: for an object
  # reference (a link's annotation) the tool writes the annotation's /Subtype
  # -- `/Link' -- where content would go. That is the dump's notation, not
  # text in the PDF, and left in it glues `/Link' onto every contact field.
  cat > "$ENV_DIR/java/ItextStruct.java" <<'JAVAEOF'
import com.itextpdf.kernel.pdf.PdfDictionary;
import com.itextpdf.kernel.pdf.PdfDocument;
import com.itextpdf.kernel.pdf.PdfName;
import com.itextpdf.kernel.pdf.PdfReader;
import com.itextpdf.kernel.pdf.tagging.PdfMcr;
import com.itextpdf.kernel.utils.TaggedPdfReaderTool;

public class ItextStruct {
    public static void main(String[] args) throws Exception {
        try (PdfDocument doc = new PdfDocument(new PdfReader(args[0]))) {
            PdfDictionary roleMap = doc.getStructTreeRoot().getRoleMap();
            for (PdfName key : roleMap.keySet()) {
                PdfName type = roleMap.getAsName(key);
                if (type != null) {
                    System.out.println("<!-- role " + key.getValue() + " "
                                       + type.getValue() + " -->");
                }
            }
            System.out.flush();
            new TaggedPdfReaderTool(doc) {
                @Override
                protected void parseTag(PdfMcr kid) {
                    if (kid.getMcid() != -1) {
                        super.parseTag(kid);
                    }
                }
            }.convertToXml(System.out, "UTF-8");
        }
    }
}
JAVAEOF
}

install_java() {
  stage "PDFBox, Tika and iText"

  local vendor="$ENV_DIR/java/vendor"
  mkdir -p "$vendor"

  if ! command -v java >/dev/null; then
    echo "setup.sh: no java on PATH -- skipping. Install a JRE 17+ and re-run." >&2
    return 0
  fi

  fetch_jar() {   # <url> <destination>
    [[ -f "$2" ]] && { echo "setup.sh: $(basename "$2") already present"; return; }
    echo "setup.sh: fetching $(basename "$2")"
    curl -fsSL -o "$2.part" "$1"
    mv "$2.part" "$2"
  }

  fetch_jar "$MAVEN/pdfbox/pdfbox-app/$PDFBOX/pdfbox-app-$PDFBOX.jar" \
            "$vendor/pdfbox-app.jar"
  fetch_jar "$MAVEN/tika/tika-app/$TIKA/tika-app-$TIKA.jar" \
            "$vendor/tika-app.jar"

  # Tika 4: a jar, lib/ and plugins/, from the release zip.
  local tika_dir="$vendor/tika-struct" zip="tika-app-$TIKA_STRUCT.zip"

  if [[ -d "$tika_dir" ]]; then
    echo "setup.sh: tika-struct already present"
  else
    echo "setup.sh: fetching $zip"
    rm -rf "$tika_dir.part"
    mkdir -p "$tika_dir.part"
    curl -fsSL -o "$tika_dir.part/$zip" "$APACHE_ARCHIVE/tika/$TIKA_STRUCT/$zip"
    curl -fsSL -o "$tika_dir.part/$zip.sha512" \
         "$APACHE_ARCHIVE/tika/$TIKA_STRUCT/$zip.sha512"
    (cd "$tika_dir.part" && sha512sum -c --quiet <(echo "$(cut -d' ' -f1 "$zip.sha512")  $zip"))
    unzip -q "$tika_dir.part/$zip" -d "$tika_dir.part"
    rm "$tika_dir.part/$zip" "$tika_dir.part/$zip.sha512"
    mv "$tika_dir.part/tika-app-$TIKA_STRUCT.jar" "$tika_dir.part/tika-app.jar"
    mv "$tika_dir.part" "$tika_dir"
  fi

  # iText: the kernel, which holds TaggedPdfReaderTool, and what it needs on
  # the class path to read a PDF -- no layout, no signing provider.
  mkdir -p "$vendor/itext"
  for a in kernel io commons bouncy-castle-connector; do
    fetch_jar "$MAVEN_ROOT/com/itextpdf/$a/$ITEXT/$a-$ITEXT.jar" \
              "$vendor/itext/$a.jar"
  done
  fetch_jar "$MAVEN_ROOT/org/slf4j/slf4j-api/$SLF4J/slf4j-api-$SLF4J.jar" \
            "$vendor/itext/slf4j-api.jar"

  write_java_drivers

  if ! java --list-modules 2>/dev/null | grep -q '^jdk\.compiler@'; then
    echo "setup.sh: this java has no jdk.compiler module, so the iText driver" \
         "cannot run from source -- install a JDK (default-jdk-headless)" >&2
  fi

  echo "setup.sh: $(java -version 2>&1 | head -1), PDFBox $PDFBOX, Tika $TIKA" \
       "and $TIKA_STRUCT, iText $ITEXT"
}

# ---- 5. veraPDF -------------------------------------------------------------
# pdfa-check.py and pdfua-check.py work without this: they test the conformance
# rules this document can plausibly break, and that is what runs when veraPDF
# is absent. What
# veraPDF adds is authority -- it is the validator the PDF/A standard's own test
# corpus is maintained against, so it decides the question rather than
# approximating it, and it reports the ISO clause behind a failure:
#
#     ISO 19005-2:2011, clause 6.8, test 5
#     A file specification dictionary [...] may contain the EF key, provided
#     that the embedded file is compliant with either ISO 19005-1 or this part
#     of ISO 19005
#
# -- which is the rule the latex-lab CSS attachments broke in this project.
#
# On a machine whose root filesystem is short of space, point VERAPDF_PREFIX at
# a roomier volume and tell pdfa-check.py where it went with VERAPDF=<path>.
install_verapdf() {
  stage "veraPDF"

  local prefix="${VERAPDF_PREFIX:-$ENV_DIR/verapdf/vendor}"

  if [[ -x "$prefix/verapdf" ]]; then
    echo "setup.sh: $("$prefix/verapdf" --version 2>/dev/null | head -1) already present"
    return 0
  fi

  if ! command -v java >/dev/null; then
    echo "setup.sh: no java on PATH -- veraPDF needs a JRE 11 or newer" >&2
    return 0
  fi

  local work zip url installer
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN

  zip="verapdf-greenfield-$VERAPDF-installer.zip"
  url="https://software.verapdf.org/releases/$VERAPDF_SERIES/$zip"

  echo "setup.sh: fetching veraPDF $VERAPDF"
  curl -sSL --fail -o "$work/$zip" "$url"
  unzip -q -o "$work/$zip" -d "$work"

  installer="$work/verapdf-greenfield-$VERAPDF/verapdf-izpack-installer-$VERAPDF.jar"
  [[ -f "$installer" ]] || {
    echo "setup.sh: installer jar not found in $zip" >&2; return 1; }

  # IzPack drives the install from this answer file. Docs and sample plugins
  # are left out; the CLI and the validation model are all pdfa-check.py needs.
  cat > "$work/auto-install.xml" <<XML
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<AutomatedInstallation langpack="eng">
  <com.izforge.izpack.panels.htmlhello.HTMLHelloPanel id="welcome"/>
  <com.izforge.izpack.panels.target.TargetPanel id="install_dir">
    <installpath>$prefix</installpath>
  </com.izforge.izpack.panels.target.TargetPanel>
  <com.izforge.izpack.panels.packs.PacksPanel id="sdk_pack_select">
    <pack index="0" name="veraPDF GUI" selected="true"/>
    <pack index="1" name="veraPDF Mac and *nix Scripts" selected="true"/>
    <pack index="2" name="veraPDF Validation model" selected="true"/>
    <pack index="3" name="veraPDF Documentation" selected="false"/>
    <pack index="4" name="veraPDF Sample Plugins" selected="false"/>
  </com.izforge.izpack.panels.packs.PacksPanel>
  <com.izforge.izpack.panels.install.InstallPanel id="install"/>
  <com.izforge.izpack.panels.finish.FinishPanel id="finish"/>
</AutomatedInstallation>
XML

  java -jar "$installer" "$work/auto-install.xml" >/dev/null

  [[ -x "$prefix/verapdf" ]] || {
    echo "setup.sh: install produced no $prefix/verapdf" >&2; return 1; }

  echo "setup.sh: $("$prefix/verapdf" --version 2>/dev/null | head -1) -> $prefix/verapdf"

  [[ "$prefix" == "$ENV_DIR/verapdf/vendor" ]] || \
    echo "setup.sh: installed outside env/ -- run the tests with VERAPDF=$prefix/verapdf"
}

# ---- Main -------------------------------------------------------------------
mkdir -p "$ENV_DIR"/{pdfjs,java,verapdf}

if (( DO_SYSTEM )); then
  install_system
fi

install_venv
install_pdfjs
install_java
install_verapdf

echo
echo "=== ready ==="
echo "env/ is disposable: delete it and re-run this script to rebuild it."
echo "Run the suite with ./pipeline.sh <main.tex>; it picks up env/ automatically."

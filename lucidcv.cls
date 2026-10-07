%% lucidcv.cls -- Lucid CV, an ATS-friendly résumé class.
%%
%% Author: Patrik Goldschmidt
%% Date: 2026-08-19, last rev. 2026-10-07
%%
%% A LuaLaTeX class built around real-word-space PDF tagging, so the compiled
%% résumé reads back correctly in ATS parsers and text extractors, not just on
%% screen. Inspired by PlushCV.cls design, but most of it was fully rewritten.
%%
%% Requires LuaLaTeX and a LaTeX format of 2026-06-01 or newer. The fonts are
%% loaded as .ttf files via fontspec from the fonts/ dir beside this class file,
%% or through kpathsea when installed in a TeX distribution.
%%
%% Design inspired by PlushCV.cls
%%  (c) Shubham Mazumder <http://mazumder.me>, Apache License 2.0
%%
%% --- LICENSE ---
%%
%% lucidcv.cls
%% Copyright (c) 2026 Patrik Goldschmidt <goldschmidt.patrik@gmail.com>
%%
%% This work may be distributed and/or modified under the conditions of the
%% LaTeX Project Public License, either version 1.3c of this license or (at
%% your option) any later version. The latest version of this license is in
%% http://www.latex-project.org/lppl.txt and version 1.3c or later is part
%% of all distributions of LaTeX version 2008 or later.
%%
%% This work has the LPPL maintenance status `maintained'.
%%
%% The Current Maintainer of this work is Patrik Goldschmidt.
%%
%% This work consists of the following files:
%%   - main.tex
%%   - lucidcv.cls
%%   - README.md
%%   - resources/docs.md
%%   - latexmkrc
%%
%% Bundled fonts (Inter, Source Sans 3, Source Code Pro) are under the SIL
%% Open Font License.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\NeedsTeXFormat{LaTeX2e}[2026-06-01]
\ProvidesClass{lucidcv}[2026/10/07 v1.0.0 Lucid CV resume class]

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Class options
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Declared options via modern LaTeX \DeclareKeys. Accept explicit values.
\newif\if@lcv@hyper      \@lcv@hyperfalse
\newif\if@lcv@icons      \@lcv@iconstrue
\newif\if@lcv@photo      \@lcv@photofalse
\newif\if@lcv@rule       \@lcv@ruletrue
\newif\if@lcv@onecolumn  \@lcv@onecolumntrue
\newif\if@lcv@compressed \@lcv@compressedfalse

\DeclareKeys{
  hyper          .if    = @lcv@hyper,       % clickable hyperlinks
  photo          .if    = @lcv@photo,       % show header photo
  compressed     .if    = @lcv@compressed,  % tighter fonts and spacing
  noicons        .ifnot = @lcv@icons,       % strip every icon glyph, for ATS
  headingrule    .if    = @lcv@rule,        % hairline under a \cvsection
  noheadingrule  .ifnot = @lcv@rule,        % disable the rule
  onecolumn      .if    = @lcv@onecolumn,   % one body column, the ATS-safe default
  twocolumn      .ifnot = @lcv@onecolumn,   % two body columns, opt in explicitly
}

%% Anything else (10pt, a4paper, ...) goes to extarticle. #1 is the key name.
\DeclareUnknownKeyHandler{\PassOptionsToClass{#1}{extarticle}}
\ProcessKeyOptions

\LoadClass{extarticle}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Engine check
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% LuaLaTeX requirement. Kept FIRST, ahead of \directlua and fontspec.
\RequirePackage{iftex}
\ifLuaTeX\else
  \ClassError{lucidcv}{lucidcv requires LuaLaTeX}{%
    The fonts are .ttf loaded through fontspec, and real word spaces\MessageBreak
    need LuaTeX's tagging support.\MessageBreak
    On Overleaf: Menu > Compiler > LuaLaTeX.}
  \@@end
\fi

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Packages & their settings
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Determine tagging presence, set its flag and disable CSS-attachment (PDF/A)
\newif\if@lcv@tagging
\AddToHook{begindocument}{%
  \@ifpackageloaded{tagpdf}{%
    \@lcv@taggingtrue
    \tagpdfsetup{attach-css=false}%
  }{%
    \ClassWarning{lucidcv}{%
      No \string\DocumentMetadata\space seen, so this PDF has neither PDF/A\MessageBreak
      metadata nor real word spaces between words. Put\MessageBreak
      \string\DocumentMetadata{pdfstandard=A-2b,tagging=on,lang=en-US}\MessageBreak
      as the FIRST line of your .tex, before \string\documentclass}%
  }%
}

%% Load icons and make them extract as a SPACE for ATS parsing.
%% Some parsers fall back to ToUnicode instead of ActualText, hence Lua code.
%% This callback must be registered before fontawesome5 package is loaded.
\directlua{
  luatexbase.add_to_callback("luaotfload.patch_font", function(fontdata)
    local name = fontdata.psname or fontdata.fullname or ""
    if name:find("FontAwesome") then
      for _, char in pairs(fontdata.characters or {}) do
        char.tounicode = "0020"
      end
    end
  end, "lucidcv.iconspace")
}

\RequirePackage[fixed]{fontawesome5}

\RequirePackage{etoolbox}
\RequirePackage{keyval}             % keyword arguments for macros
\RequirePackage[dvipsnames]{xcolor} % `dvipsnames' for \cvaccent[named]
\RequirePackage{fontspec}           % custom fonts
\RequirePackage{tikz}
\usetikzlibrary{fill.image}         % `fill overzoom image' in \cvphoto
\RequirePackage{enumitem}
\RequirePackage{graphicx}           % for the DOCUMENT's \includegraphics
\RequirePackage{dashrule}           % \cvdivider
\RequirePackage{paracol}            % the two body columns
\RequirePackage{ragged2e}           % the `justify' environment
\RequirePackage{framed}             % the cvgroup rule, via \MakeFramed

%% Margins and the gutter between the two body columns
\RequirePackage[left=1.2cm,right=1.2cm,top=1.2cm,bottom=1.2cm,columnsep=1.1cm]{geometry}

%% Reset to one-column mode, as paracol refuses to run inside the kernel's
%% page-level two-column mode. Both extarticle and geometry set that mode from
%% a GLOBAL `twocolumn' class option, so this must come after both of them.
\@twocolumnfalse
\onecolumn

%% Load hyperref last as a convention
\RequirePackage{hyperref}
\RequirePackage{accsupp}

%% Avoid 'Token not allowed' when \\ is used together with accsupp
%% The % after the brace is load-bearing -- do not tidy it away.
\pdfstringdefDisableCommands{%
  \let\\\space
}

%% Link styling. Applied whether or not `hyper' is set.
\hypersetup{hidelinks}
\urlstyle{same}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Colors
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\definecolor{CVBlue}{HTML}{1D76E2}
\definecolor{CVPrimary}{HTML}{2B2B2B}       % body text
\definecolor{CVSubheading}{HTML}{333333}
\definecolor{CVGrey}{HTML}{6A6A6A}          % meta lines
\definecolor{CVDate}{HTML}{2B2B2B}          % \lastupdated stamp; = tagline

%% Define template color theme; driven by \cvaccent.
%%     \cvaccent{B03A2E}            % HTML -- the default model
%%     \cvaccent[RGB]{29,118,226}
%%     \cvaccent[named]{OliveGreen} % any name xcolor knows
\newcommand{\lcv@deriveaccent}{%
  \colorlet{accent}{CVAccent}%
  \colorlet{name}{CVAccent}%
  \colorlet{heading}{CVAccent}%
  \colorlet{headingrule}{CVAccent!30}%
  \colorlet{grouprule}{CVAccent!45}%
}
\newcommand{\cvaccent}[2][HTML]{%
  \definecolor{CVAccent}{#1}{#2}%
  \lcv@deriveaccent
}
%% The default goes through the same path a user's own call takes.
\colorlet{CVAccent}{CVBlue}
\lcv@deriveaccent

\colorlet{subheading}{CVSubheading}
\colorlet{emphasis}{CVSubheading}
\colorlet{body}{CVPrimary}
\colorlet{tagline}{CVPrimary}
\colorlet{meta}{CVGrey}
\colorlet{entryorg}{CVSubheading}
\colorlet{entryleader}{CVGrey!30}
\colorlet{divider}{CVGrey!30}       % the other faint hairline; matches above
\colorlet{taglistmark}{CVGrey}
\colorlet{quote}{CVSubheading}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Fonts
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% .ttf fonts for better ATS parsability; .otf tend to fuse words together
%% Font dirs: \cvfontdir if defined before \documentclass, else fonts/ beside
%% this class (not the working dir), else kpathsea (TeX distribution install).
\directlua{
  lucidcv = lucidcv or {}
  function lucidcv.fontdir(sub, file)
    local cls = kpse.find_file("lucidcv.cls", "tex") or ""
    local dir = cls:gsub("[^/]*$", "") .. "fonts/" .. sub
    local found = lfs.isfile(dir .. file) and dir .. file
      or kpse.find_file(file, "truetype fonts")
    tex.sprint(-2, found and found:gsub("[^/]*$", "") or dir)
  end
}
\ifdefined\cvfontdir
  \edef\lcv@interdir{\cvfontdir inter/}
  \edef\lcv@sspdir{\cvfontdir sourcesans3/}
  \edef\lcv@scpdir{\cvfontdir sourcecodepro/}
\else
  \edef\lcv@interdir{\directlua{
    lucidcv.fontdir("inter/", "Inter-Light.ttf")}}
  \edef\lcv@sspdir{\directlua{
    lucidcv.fontdir("sourcesans3/", "SourceSans3-Light.ttf")}}
  \edef\lcv@scpdir{\directlua{
    lucidcv.fontdir("sourcecodepro/", "SourceCodePro-Light.ttf")}}
\fi
\defaultfontfeatures{Ligatures=TeX}

%% Body: Inter Light / SemiBold
\setmainfont{Inter}[
  Path=\lcv@interdir,
  Extension=.ttf,
  WordSpace=1.0,
  UprightFont=*-Light,
  BoldFont=*-SemiBold,
  ItalicFont=*-LightItalic,
  BoldItalicFont=*-SemiBoldItalic
]
%% Inter is the sans face too, for packages that select \sffamily internally.
\renewcommand{\sfdefault}{\rmdefault}

%% Monospace (\texttt): Source Code Pro, Light / Semibold to match the body.
\setmonofont{SourceCodePro}[
  Path=\lcv@scpdir,
  Extension=.ttf,
  UprightFont=*-Light,
  BoldFont=*-Semibold,
  ItalicFont=*-LightIt,
  BoldItalicFont=*-SemiboldIt
]

%% Name, headings, entry titles, tagline, contact line: Source Sans 3.
%% Manually set WordSpace=1.15 for ATS parsability.
\newfontfamily\lcv@titlefont{SourceSans3}[
  Path=\lcv@sspdir,
  Extension=.ttf,
  WordSpace=1.15,
  UprightFont=*-Semibold,
  BoldFont=*-Bold,
  ItalicFont=*-SemiboldIt,
  BoldItalicFont=*-SemiboldIt
]
%% Lighter Source Sans 3 variant
\newfontfamily\lcv@lightfont{SourceSans3}[
  Path=\lcv@sspdir,
  Extension=.ttf,
  WordSpace=1.15,
  UprightFont=*-Light,
  BoldFont=*-Semibold,
  ItalicFont=*-It,
  BoldItalicFont=*-SemiboldIt
]

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Heading tagging
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% LaTeX \DocumentMetadata{tagging=on} tags every paragraph as `text' (par),
%% so headings would be considered `text' too, making the document structure
%% flat. A new command \lcv@taggedpar tags the heading's own paragraph.

%% #1 = structure tag (H1, H2, H3), #2 = the heading paragraph itself
\newcommand{\lcv@taggedpar}[2]{%
  \begingroup
    \if@lcv@tagging\tagpdfsetup{para/tag=#1}\fi
    #2%
  \endgroup
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Real spaces at thin spaces
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Tagging inserts a real space glyph only at GLUE, but the kernel sets the
%% text-mode \, \: \; (and \thinspace, \medspace, \thickspace) as a KERN, so
%% parsers guess from the gap and may read `850\,ms' as `850ms'. This makes
%% them unbreakable glue of the same width: the line looks and breaks the
%% same, but the gap gets a space glyph. Negative spaces (\!) are unaffected.
\AddToHook{begindocument}{%
  \DeclareRobustCommand\tmspace[3]{%
    \ifmmode\mskip#1#2\else\leavevmode@ifvmode
      \if-#1\kern#1#3\else\nobreak\hskip#3\fi
    \fi\relax}%
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Document defaults
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Defaults are set via a hook, so they override any preamble setting.
%% This is deliberate (contrast to \hypersetup) for better ATS compatibility.
%% Body text is ragged right and hyphenation disabled to prevent word breaks.
\AddToHook{begindocument/before}{%
  \pagestyle{empty}%      % Disable LaTeX headers, footers & page numbers
  \color{body}%           % Default text color
  \raggedright%           % Left-aligned text, zeroes \parindent
  \hyphenpenalty=10000%   % Disable hyphenation for ATS parsability
  \exhyphenpenalty=10000%
  \emergencystretch=3em%
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Markers and dividers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\newcommand{\cvitemmarker}{{\small\textbullet}}   % Default item marker

%% Item divider (dashed line)
%% The gap around the rule is static and gaps of delimited items are ignored:
%% exactly \cvdividerskip on both sides, whatever the neighbours add.
\newlength{\cvdividerskip}

\if@lcv@compressed
  \setlength{\cvdividerskip}{0.3em}
\else
  \setlength{\cvdividerskip}{0.7em}
\fi

\newlength{\cvdividerwidth}
\setlength{\cvdividerwidth}{0.6pt}
\newcommand{\cvdividerdash}{0.35em}

\newcommand{\cvdivider}{%
  \par\removelastskip
  \vskip\cvdividerskip
  \nointerlineskip
  {\parskip=0pt\noindent
   {\color{divider}\hdashrule{\linewidth}{\cvdividerwidth}{\cvdividerdash}}\par}%
  \vskip\cvdividerskip
  \nointerlineskip
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Block environments: lists, justified text, quotes
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Redefinition of LaTeX environments to adjust their spacing (glue) and looks.

%% ---- Lists ------------------------------------------------------------------
%% Set list environment spacing, lower in the compressed mode
\if@lcv@compressed
  \newcommand{\cvitemsep}{0.1em}
  \newcommand{\cvitemtopsep}{0.1em}
\else
  \newcommand{\cvitemsep}{0.15em}
  \newcommand{\cvitemtopsep}{0.2em}
\fi

\setlist{leftmargin=1.4em,labelsep=0.5em,itemsep=\cvitemsep,
  topsep=\cvitemtopsep,parsep=0pt,partopsep=0pt}
\setlist[itemize]{label=\cvitemmarker}

%% Reduce the list env CLOSING skip by scaling. Requires a hook: LaTeX's
%% tagging ignores the keyed `topsep', so it cannot be set with \setlist.
\newcommand{\cvitemlastskipratio}{0.4}
\newlength{\cvitemlastskiptrim}
\setlength{\cvitemlastskiptrim}{0.2em}

\if@lcv@compressed
  \renewcommand{\cvitemlastskipratio}{0.25}
  \setlength{\cvitemlastskiptrim}{0.15em}
\fi

%% Scale the closing skip for list environments; never negative
\newcommand{\lcv@listlastskip}{%
  \skip@=\lastskip
  \removelastskip
  \skip@=\cvitemlastskipratio\skip@
  \advance\skip@-\cvitemlastskiptrim
  \ifdim\skip@<\z@ \skip@=\z@ \fi
  \vskip\skip@\relax}

\AddToHook{env/itemize/after}{\lcv@listlastskip}
\AddToHook{env/enumerate/after}{\lcv@listlastskip}
\AddToHook{env/description/after}{\lcv@listlastskip}

%% ---- Justified text --------------------------------------------------------
%% Bound space shrinking in justified blocks: heavily squeezed spaces can read
%% as no spaces at all, while `minus 0pt' can cause double spacing.
%% Re-pinned after every \selectfont; the flag confines that to `justify'.
\newif\if@lcv@pinspace
\newcommand{\lcv@pinspace}{%
  \spaceskip=\fontdimen2\font plus \fontdimen3\font
    minus 0.75\fontdimen4\font\relax}
\AddToHook{cmd/selectfont/after}{\if@lcv@pinspace\lcv@pinspace\fi}

%% Redefine ragged2e's justify environment as a plain block, so it carries no
%% glue and positions itself as an ordinary paragraph. Justifying is opt-in.
\renewenvironment{justify}{%
  \par
  \justifying
  \@lcv@pinspacetrue\lcv@pinspace
  \parindent\z@
}{%
  \par
}

%% ---- Quotes ----------------------------------------------------------------
%% Redefine quote environment: grey font, italics and document's font size.
%% Done via hook, because tagging replaces \quote with its own environment.
\newlength{\cvquoteskip}

\if@lcv@compressed
  \setlength{\cvquoteskip}{0.3em}
\else
  \setlength{\cvquoteskip}{\medskipamount}
\fi
\AddToHook{begindocument}{%
  \renewenvironment{quote}
    {\addvspace{\cvquoteskip}%
     \if@lcv@tagging\tagstructbegin{tag=BlockQuote}\fi
     \color{quote}\itshape}
    {\par\if@lcv@tagging\tagstructend\fi}%
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Personal-information fields
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Contact fields with icons and accsupp ActualText for ATS compatibility.

%% Makes the specials in values printable. UTF-8-safe stand-in for \detokenize,
%% so a contact value can carry  _ & $ ~ ^  without escaping. `%' is not in the
%% catcode list deliberately -- it is already tokenized. Write # as \#.
%% \endlinechar=-1 is crucial for \scantokens to interpret text correctly.
\newcommand{\lcv@detokenize}[1]{%
  \begingroup
    \endlinechar=-1
    \catcode`\_=12 \catcode`\&=12 \catcode`\$=12
    \catcode`\#=12 \catcode`\~=12 \catcode`\^=12
    \scantokens{#1}%
  \endgroup
}

%% Header contact-field infrastructure: \CvInfoField and the fields it makes.
%% \ExplSyntaxOn makes an ordinary space catcode 9 (IGNORED) and `~' catcode 10
%% (a space token). The `~' in \lcv@infoicon below is therefore a real space
%% character, which is what the ActualText and helper code expects to see.
\ExplSyntaxOn

%% Extra visual gap between an icon and its value, on top of a real space char
\newcommand{\cvinfoicongap}{0.15em}

%% The icon, or nothing under `noicons'. The ActualText is deliberately EMPTY,
%% so the glyph extracts as nothing. An icon means nothing to a parser, so its
%% value must be complete -- write `linkedin.com/in/your_id', not a `your_id'.
%% The `~' is a real space character; \cvinfoicongap adds additional visual gap
\NewDocumentCommand{\lcv@infoicon}{m}{%
  \if@lcv@icons
    \textcolor{accent}%
      {\BeginAccSupp{method=escape,ActualText={}}\normalfont #1\EndAccSupp{}}%
    ~\hspace{\cvinfoicongap}%
  \fi
}
\ExplSyntaxOff

%% Gap between two contact items in the `icons' mode.
\newcommand{\cvinfosepamount}{0.75em}
\newcommand{\cvinfosep}{\hspace{\cvinfosepamount}}

%% Flags read by \lcv@infodelim for preventing stray delimiters.
%% 1) Is \makecvheader typesetting the contact block right now?
%% 2) Is this the FIRST item inside the block?
\newif\if@lcv@ininfo
\newif\if@lcv@infoseen

%% Separator ('|') between contact items, both in `icons' and `noicons' modes.
\newcommand{\cvinfodelimmark}{|}

%% A gap between a contact item text and a separator. Symmetric in `noicons'
\newcommand{\cvinfodelimgap}{0.4em}

%% A gap between a separator and an icon. If icons are present, symmetric
%% gaps do not create a visually symmetric layout, so asymmetry is required.
\newcommand{\cvinfodelimgapicon}{0.2em}

%% Info delimiter. Set between two items, never before the 1st/after the last.
%% The negative space backs out the preceding gap, landing the mark in between.
%% Items are \mbox'd, so this is the line's only breakpoint; the mark sits in
%% the no-break slot, so a wrap drops it. `penalty 1' is load-bearing.
\newcommand{\cvinfodelim}{%
  \unskip
  \nobreak
  \hspace{-\dimexpr\cvinfosepamount-\cvinfodelimgap\relax}%
  \discretionary penalty 1 {}{}{%
    \cvinfodelimmark
    \if@lcv@icons\kern\cvinfodelimgapicon\else\kern\cvinfodelimgap\fi}%
}
%% Emitted ahead of each contact item.
\newcommand{\lcv@infodelim}{%
  \if@lcv@ininfo
    \if@lcv@infoseen
      \cvinfodelim
    \fi
    \global\@lcv@infoseentrue
  \fi
}

%% \lcv@refsymbol definition
%% Arguments: #1 = symbol
%% Reference icon symbols, substituting an empty string for ATS parsing
\NewDocumentCommand{\lcv@refsymbol}{m}{%
  \BeginAccSupp{method=escape,ActualText={}}#1\EndAccSupp{}%
}

%% \lcv@infoplain and \lcv@infolinked definitions -- contact item typesetting
%% Kept as plain macros so the expl3 layer can hand them expanded arguments.
%% Arguments: #1 icon, #2 text -- or #1 icon, #2 target, #3 text.
\newcommand{\lcv@infoplain}[2]{%
  \lcv@infodelim
  \mbox{\lcv@infoicon{#1}\lcv@detokenize{#2}\cvinfosep}%
}
\newcommand{\lcv@infolinked}[3]{%
  \lcv@infodelim
  \mbox{\lcv@infoicon{#1}%
    \if@lcv@hyper
      \href{#2}{\lcv@detokenize{#3}}%
    \else
      \lcv@detokenize{#3}%
    \fi
    \cvinfosep}%
}

%% Per-call keys for a declared field. `noprefix' drops the shown prefix
\newif\if@lcv@noprefix
\define@key{lcv@info}{noprefix}[]{\@lcv@noprefixtrue}
\newcommand{\lcv@infokeys}[1]{%
  \@lcv@noprefixfalse
  \setkeys{lcv@info}{#1}%
}

%% Raised when a \CvInfoField scheme slot does not look like a scheme.
\newcommand{\lcv@warnscheme}[2]{%
  \ClassWarning{lucidcv}{%
    Field `#1' gives `#2' as its link scheme, which ends in neither
    `:' nor `//'.\MessageBreak
    \string\CvInfoField\space takes [scheme][shown] -- split it as
    [https://][example.com/]%
  }%
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\ExplSyntaxOn
\prop_new:N \g__lcv_field_prop
\tl_new:N   \l__lcv_field_icon_tl
\tl_new:N   \l__lcv_field_uri_tl
\tl_new:N   \l__lcv_field_text_tl
\tl_new:N   \l__lcv_field_scheme_tl

%% \lcv@infolinked takes 3 arguments which must be expanded, \lcv@detokenize
%% re-reads arguments with `_' to make bare variable names typeset properly
\exp_args_generate:n { VVV }

%% Record or replace one field's icon.
\cs_new_protected:Npn \__lcv_field_seticon:nn #1#2
  { \prop_gput:Nnn \g__lcv_field_prop { #1 / icon } {#2} }

%% Fetch one field's icon into #2; empty when the field was never declared.
\cs_new_protected:Npn \__lcv_field_geticon:nN #1#2
  { \prop_get:NnNF \g__lcv_field_prop { #1 / icon } #2 { \tl_clear:N #2 } }

%% Render a declared field. #1 name, #2 value, #3 explicit target
%% Blank -- build one from the stored link prefix or emit unlinked if none
%% Typeset text --  prefix ahead of the value, making item self-describing
%% `noprefix' -- print the value alone
\cs_new_protected:Npn \__lcv_field_emit:nnn #1#2#3
  {
    \__lcv_field_geticon:nN {#1} \l__lcv_field_icon_tl
    \tl_clear:N \l__lcv_field_text_tl
    \legacy_if:nF { @lcv@noprefix }
      {
        \prop_get:NnNF \g__lcv_field_prop { #1 / show } \l__lcv_field_text_tl
          { \tl_clear:N \l__lcv_field_text_tl }
      }
    \tl_put_right:Nn \l__lcv_field_text_tl {#2}
    %% The target always carries the whole prefix, `noprefix' notwithstanding.
    \tl_clear:N \l__lcv_field_uri_tl
    \tl_if_blank:nTF {#3}
      {
        \prop_get:NnNT \g__lcv_field_prop { #1 / uri } \l__lcv_field_uri_tl
          { \tl_put_right:Nn \l__lcv_field_uri_tl {#2} }
      }
      { \tl_set:Nn \l__lcv_field_uri_tl {#3} }
    \tl_if_empty:NTF \l__lcv_field_uri_tl
      { \exp_args:NVV  \lcv@infoplain  \l__lcv_field_icon_tl
                                       \l__lcv_field_text_tl }
      { \exp_args:NVVV \lcv@infolinked \l__lcv_field_icon_tl
                                       \l__lcv_field_uri_tl
                                       \l__lcv_field_text_tl }
  }

%% A declared field's icon, for code outside the contact block (\cvref).
\NewDocumentCommand{\lcv@fieldicon}{m}
  {
    \__lcv_field_geticon:nN {#1} \l__lcv_field_icon_tl
    \tl_use:N \l__lcv_field_icon_tl
  }

%% Check and raise warning: A scheme has to end in `:' or `//'
\cs_new_protected:Npn \__lcv_field_checkscheme:nn #1#2
  {
    \str_if_eq:eeF { \str_range:nnn {#2} {-1} {-1} } { : }
      {
        \str_if_eq:eeF { \str_range:nnn {#2} {-2} {-1} } { // }
          { \lcv@warnscheme {#1} {#2} }
      }
  }

%% \CvInfoField[*][scheme][shown]{name}{icon} -- declare a contact field.
%% The hyperlink is defined by scheme+shown+user value.
%% A document can redeclare built-in fields (scheme, prefix, args).
%% Only `shown' + user value reach the page, so the item is ATS self-describing
%%   plain   \<name>[keys]{value}          target built from scheme+shown
%%   starred \<name>[keys]{value}{target}  the caller supplies the target
\NewDocumentCommand{\CvInfoField}{s o o m m}
  {
    \__lcv_field_seticon:nn {#4} {#5}
    \IfNoValueF {#3} { \prop_gput:Nnn \g__lcv_field_prop { #4 / show } {#3} }
    \tl_clear:N \l__lcv_field_scheme_tl
    \IfNoValueF {#2} { \tl_set:Nn \l__lcv_field_scheme_tl {#2} }
    \tl_set_eq:NN \l__lcv_field_uri_tl \l__lcv_field_scheme_tl
    \IfNoValueF {#3} { \tl_put_right:Nn \l__lcv_field_uri_tl {#3} }
    %% A field without parts stays plain text, so there is no scheme
    \tl_if_empty:NF \l__lcv_field_uri_tl
      {
        \prop_gput:NnV \g__lcv_field_prop { #4 / uri } \l__lcv_field_uri_tl
        \exp_args:NnV \__lcv_field_checkscheme:nn {#4} \l__lcv_field_scheme_tl
      }
    \IfBooleanTF {#1}
      { \exp_args:Nc \DeclareDocumentCommand {#4} { O{} m m }
          { \lcv@infokeys {##1} \__lcv_field_emit:nnn {#4} {##2} {##3} } }
      { \exp_args:Nc \DeclareDocumentCommand {#4} { O{} m }
          { \lcv@infokeys {##1} \__lcv_field_emit:nnn {#4} {##2} { } } }
  }

%% Restyle a declared field's icon, built-ins included
\NewDocumentCommand{\cvfieldicon}{m m}
  { \__lcv_field_seticon:nn {#1} {#2} }
\ExplSyntaxOff

%% Header text stores.
\newcommand{\tagline}[1]{\def\lcv@tagline{#1}}
\newcommand{\cvpersonalinfo}[1]{\def\lcv@personalinfo{#1}}

%% The built-in fields. More can be declared in the document with \CvInfoField.
\CvInfoField[mailto:]{email}{\faAt}
\CvInfoField[tel:]{phone}{\faPhone}
\CvInfoField{mailaddress}{\faEnvelope}
\CvInfoField{location}{\faMapMarker}
%% Built-in web fields: value = id, shown prefix names the service
\CvInfoField[https://]{homepage}{\faGlobe}
\CvInfoField[https://][linkedin.com/in/]{linkedin}{\faLinkedin}
\CvInfoField[https://][github.com/]{github}{\faGithub}
\CvInfoField[https://][orcid.org/]{orcid}{\faOrcid}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Photo
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%   \cvphoto                      placeholder, default diameter and inset
%%   \cvphoto{myface}              specified image, cropped to a circle
%%   \cvphoto[4cm]{myface}         specified image, its diameter
%%   \cvphoto[4cm][0.6cm]{myface}  specified image, its diameter and inset
%%
%% \cvphoto DECLARES the photo, while \makecvheader draws it.
%% The photo appears only if the `photo' class option is also set.

%% Flatten markup in the alt text to drop commands like \textsc in the name.
\ExplSyntaxOn
\cs_new:Npn \lcv@purify #1 { \text_purify:n {#1} }
\ExplSyntaxOff

%% Tag a drawing as a Figure carrying alt text.
%% Args: #1 = alt text, #2 = the drawing
\newcommand{\lcv@tagfigure}[2]{%
  \if@lcv@tagging
    \expanded{\noexpand\tagstructbegin{tag=Figure,alt={\lcv@purify{#1}}}}%
    \tagmcbegin{tag=Figure}%
    #2%
    \tagmcend\tagstructend
  \else
    #2%
  \fi
}

%% Photo drawing: Create a minipage and a circle with its diameter, and fill it
%% #1 = diameter   #2 = image file
\newcommand{\lcv@makephoto}[2]{%
  \begin{minipage}{#1}%
    \lcv@tagfigure{Photograph of \lcv@name}{%
      \tikz\path[fill overzoom image={#2}]circle[radius=0.5\linewidth];%
    }%
  \end{minipage}%
}

%% The drawn avatar: a photo-shaped mark with no image file to ship or forget.
%% No transparency, so it stays PDF/A-safe.   #1 = diameter
\newcommand{\lcv@makephotoplaceholder}[1]{%
  \begin{minipage}{#1}%
    \lcv@tagfigure{Placeholder avatar in place of a photograph}{%
      \begin{tikzpicture}[x=0.5\linewidth,y=0.5\linewidth]
        \clip (0,0) circle[radius=1];
        \fill[accent!12] (-1,-1) rectangle (1,1);
        \fill[accent!45] (0,0.28) circle[radius=0.34];
        \fill[accent!45] (0,-0.95) ellipse[x radius=0.68,y radius=0.62];
      \end{tikzpicture}%
    }%
  \end{minipage}%
}

%% Definitions
\def\lcv@photodefaultdiam{3cm}      % default diameter for \cvphoto
\newcommand{\cvphotogutter}{1ex}    % Gap between the name block and the photo
\newlength{\lcv@photodiam}          % \makecvheader draws these lengths
\newlength{\lcv@photoinset}
\newlength{\lcv@sidecolwidth}       % used for automatic inset comp
\def\lcv@photofile{}                % image file

%% Flags
\newif\if@lcv@photodeclared         % was \cvphoto ever called?
\newif\if@lcv@photoinsetgiven       % did the user supply own [inset]
\newif\if@lcv@headerdone            % has \makecvheader already run

%% \cvphoto definition
%% Arguments:
%% #1 = optional diameter, #2 = optional inset, #3 = path to image
%% Caution: `g' peeks ahead, so a bare \cvphoto swallows a following {...} as
%% its filename -- causes LaTeX Error: File `<the swallowed text>' not found.
\NewDocumentCommand{\cvphoto}{o o g}{%
%% If the header was already built, warn and stop
  \if@lcv@headerdone
    \ClassWarning{lucidcv}{%
      \string\cvphoto\space came after \string\makecvheader\space and was
      ignored.\MessageBreak
      It declares the header photo, so it has to be read before the\MessageBreak
      header is built -- put it beside \string\name\space and
      \string\tagline}%
  \else
    \@lcv@photodeclaredtrue
    %% Reset fields to their defaults, so nothing leaks from the prev state
    \setlength{\lcv@photodiam}{\lcv@photodefaultdiam}%
    \@lcv@photoinsetgivenfalse
    \def\lcv@photofile{}%
    \IfNoValueF{#1}{\setlength{\lcv@photodiam}{#1}}%
    \IfNoValueF{#2}{\@lcv@photoinsetgiventrue
                    \setlength{\lcv@photoinset}{#2}}%
    \IfNoValueF{#3}{\def\lcv@photofile{#3}}%
  \fi
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Header
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Firstname and lastname are typeset with different font weights.
%% \name{Firstname}{Lastname} or \fullname{Firstname Lastname} are public API.
\def\lcv@firstname{}
\def\lcv@lastname{}
\def\lcv@name{}
\def\lcv@personalinfo{}
\def\lcv@tagline{}

\newcommand{\name}[2]{\def\lcv@firstname{#1}\def\lcv@lastname{#2}\def\lcv@name{#1 #2}}
\newcommand{\fullname}[1]{\def\lcv@firstname{}\def\lcv@lastname{#1}\def\lcv@name{#1}}

%% PDF document metadata -- the Title, Author, Subject and Keywords.
%% Metadata are extracted from the set text, i.e., \name and \tagline
%% Only \cvkeywords needs to be specified manually.
\def\lcv@title{}
\def\lcv@author{}
\def\lcv@subject{}
\def\lcv@keywords{}
\newcommand{\cvtitle}[1]{\def\lcv@title{#1}}
\newcommand{\cvauthor}[1]{\def\lcv@author{#1}}
\newcommand{\cvsubject}[1]{\def\lcv@subject{#1}}
\newcommand{\cvkeywords}[1]{\def\lcv@keywords{#1}}  % Comma-separated

%% Write the metadata to the document at the end via hook, because \name and
%% \tagline are set AFTER \begin{document} in this class.
\AddToHook{enddocument}{%
  \ifdefempty{\lcv@author}{\let\lcv@author\lcv@name}{}%
  %% The default title is built FROM the name; leave unset when no \name is set
  \ifdefempty{\lcv@title}%
    {\ifdefempty{\lcv@name}{}%
       {\protected@edef\lcv@title
          {\lcv@name\space--\space Curriculum Vitae}}}{}%
  \ifdefempty{\lcv@subject}%
    {\ifdefempty{\lcv@tagline}{\def\lcv@subject{Curriculum Vitae}}%
                          {\let\lcv@subject\lcv@tagline}}{}%
  \hypersetup{%
    pdftitle={\lcv@title},
    pdfauthor={\lcv@author},
    pdfsubject={\lcv@subject},
    pdfkeywords={\lcv@keywords},
    pdfcreator={lucidcv.cls}%
  }%
}

%% The header's two display sizes as bare point numbers, so a document can
%% tune them on demand:
%%     \renewcommand{\cvnamesize}{34}
%%     \renewcommand{\cvtaglinesize}{13}
%%
%% Specifies the baselineskip (leading) as a multiple of the size, private to
%% the class, so a gap between a header/tagline and tagline/contact info can
%% be changed from a document via \nametaggap and \tagcontactgap. The leadings
%% give each gap a natural size-proportional BASE, so changing a size keeps the
%% header in proportion, and the gap macros then add/subtract from that base.
\newcommand{\cvnamesize}{38}
\newcommand{\cvnameleading}{1.105}
\newcommand{\cvtaglinesize}{15}
\newcommand{\cvtaglineleading}{1.2}

%% While the tagline above stays absolute, the contact line is scaled by 0.9
%% relative to the class font size option. The leading (baselineskip) of it
%% is 1.4 relative to the contact text font.
\newcommand{\cvinfofontscale}{0.9}
\newcommand{\cvinfoleading}{1.4}

%% Define actual header and tagline fonts
\newlength{\lcv@hdrsize}
\newcommand{\lcv@sizeleading}[2]{%
  \setlength{\lcv@hdrsize}{#1pt}%
  \fontsize{\lcv@hdrsize}{#2\lcv@hdrsize}\selectfont}
\newcommand{\namefont}{%
  \lcv@titlefont\lcv@sizeleading{\cvnamesize}{\cvnameleading}}
\newcommand{\taglinefont}{%
  \lcv@lightfont\lcv@sizeleading{\cvtaglinesize}{\cvtaglineleading}}
\newlength{\lcv@infofontsize}
\newcommand{\personalinfofont}{%
  \lcv@lightfont\normalsize
  \setlength{\lcv@infofontsize}%
    {\cvinfofontscale\dimexpr\f@size pt\relax}%
  \fontsize{\lcv@infofontsize}
           {\cvinfoleading\lcv@infofontsize}\selectfont}

%% Extra header gaps, configurable from the caller. Can also be negative
%% Warning: ATS parsers might fuse the name and tagline upon small gaps (<0pt).
\newcommand{\nametaggap}{0.1em}
\newcommand{\tagcontactgap}{0.25em}

%% Header's own internal gaps
\newlength{\cvheaderskip}         % name -> tagline, tagline -> contact
\newlength{\cvheadertrailskip}    % header -> body

\if@lcv@compressed
  \setlength{\cvheaderskip}{0.15em}
  \setlength{\cvheadertrailskip}{0em}
\else
  \setlength{\cvheaderskip}{\smallskipamount}
  \setlength{\cvheadertrailskip}{1pt plus 1pt minus 1pt}
\fi

%% Add a warning upon empirically-inferred dangerous header-tagline break ratio
%% that could fuse the name and tagline in ATSs. 0.993 is empirically measured.
\newcommand{\lcv@headerbreakratio}{0.993}
\AddToHook{begindocument}{%
  \begingroup
    \@tempdima=\cvtaglineleading\dimexpr\cvtaglinesize pt\relax
    \advance\@tempdima by \cvheaderskip
    \advance\@tempdima by \dimexpr\nametaggap\relax
    \@tempdimb=\lcv@headerbreakratio\dimexpr\cvtaglinesize pt\relax
    \advance\@tempdimb by 0.5pt
    \ifdim\@tempdima<\@tempdimb
      \ClassWarning{lucidcv}{%
        \string\nametaggap\space is \nametaggap, leaving the name-to-tagline drop\MessageBreak
        at \the\@tempdima, under the \the\@tempdimb\space that some parsers need to infer\MessageBreak
        the line break. The name and tagline may extract as ONE line in\MessageBreak
        editor viewers. See "Line breaks are always inferred" in the README}%
    \fi
  \endgroup
}

%% Hacky fix -- part 1 of 2 (part 2 in \makecvheader; README: "Line breaks are
%% always inferred"). A zero-width U+00A0 one point SMALLER than the tagline
%% opens a new text run in its marked content, so a TAGGED reader has a text
%% item to hang the inferred break on. The size delta IS the mechanism.
\newcommand{\lcv@headerbreak}{%
  \begingroup
    \@tempdima=\dimexpr\f@size pt-1pt\relax % f@size - current tagline font-1pt
    \edef\@tempa{\strip@pt\@tempdima}%    % strip <num>pt to <num> integer
    \fontsize{\@tempa}{0}\selectfont%     % switch the font to <num>pt
    \makebox[0pt][l]{\symbol{"00A0}}%     % empty space "00A0" at the start
  \endgroup}

%% Is a photo actually drawn? Set by \makecvheader once the `photo' option and
%% a \cvphoto declaration have both been seen.
\newif\if@lcv@showphoto

%% How wide the contact block can be. Zero = "decide for me":
%% - One column width with a photo, full \textwidth without.
\newlength{\cvinfowidth}
\newcommand{\lcv@setinfowidth}{%
  \lcv@setcolratio
  \ifdim\cvinfowidth=0pt
    \if@lcv@showphoto
      \setlength{\cvinfowidth}{\lcv@onecolumnwidth}%
    \else
      \setlength{\cvinfowidth}{\textwidth}%
    \fi
  \fi
}

%% The left paracol column's width. Computed on demand because \columnratio
%% may be changed in the document preamble.
\newcommand{\lcv@onecolumnwidth}{%
  \dimexpr\lcv@colratio\dimexpr\textwidth-\columnsep\relax\relax
}

%% Column ratio computation, token is unresolved until it is used.
\def\lcv@colratio{\lcv@defaultcolratio}
\newcommand{\lcv@setcolratio}{%
  \def\lcv@colratio{\lcv@defaultcolratio}%
  \ifcsname pcol@columnratioleft\endcsname
    \ifx\pcol@columnratioleft\relax
      %% \setcolumnwidth is in force, so no ratio can be read
      \ClassWarning{lucidcv}{%
        \string\setcolumnwidth\space is in force, so there is no column
        ratio to read.\MessageBreak
        The contact block and the photo inset fall back to
        \lcv@defaultcolratio.\MessageBreak
        Use \string\columnratio\space instead to keep the header in step
        with the body}%
    \else
      \ifdefempty{\pcol@columnratioleft}{}%
        {\let\lcv@colratio\pcol@columnratioleft}%
    \fi
  \fi
}

%% Width left for the name, tagline and contact block after the photo.
\newlength{\lcv@nameblockwidth}

%% \makecvheader definition -- runs only once; a second call is silently
%% ignored, because the page shows one header where two were asked for.
%% Header shape: the name block and the photo beside it.
\newcommand{\makecvheader}{%
  \if@lcv@headerdone
    \expandafter\@gobble
  \else
    \expandafter\@firstofone
  \fi
  {\lcv@makecvheader}%
}

%% A missing \name or \personalinfo is not warned: they are visibly not present
\newcommand{\lcv@makecvheader}{%
  \begingroup
    \@lcv@showphotofalse
    \if@lcv@photo
      \if@lcv@photodeclared
        \@lcv@showphototrue
      \else
        \ClassWarning{lucidcv}{%
          The `photo' option is set but no \string\cvphoto\space was
          found,\MessageBreak
          so the header has no photo. The option only switches a
          photo\MessageBreak
          on and off -- \string\cvphoto\space is what creates one}%
      \fi
    \fi
    %% Needs \if@lcv@showphoto above, and precedes the inset below.
    \lcv@setinfowidth
    %% No inset given: center the photo on the second paracol column's geometry
    \if@lcv@showphoto
      \if@lcv@photoinsetgiven\else
        \setlength{\lcv@sidecolwidth}{\dimexpr\textwidth-\columnsep\relax}%
        \addtolength{\lcv@sidecolwidth}{-\lcv@onecolumnwidth}%
        \setlength{\lcv@photoinset}
          {\dimexpr0.5\dimexpr\lcv@sidecolwidth-\lcv@photodiam\relax\relax}%
        \ifdim\lcv@photoinset<0pt
          \setlength{\lcv@photoinset}{0pt}%
        \fi
      \fi
    \fi
    \setlength{\lcv@nameblockwidth}{\linewidth}%
    \if@lcv@showphoto
      \addtolength{\lcv@nameblockwidth}
        {-\dimexpr\lcv@photodiam+\cvphotogutter+\lcv@photoinset\relax}%
    \fi
    \begin{minipage}{\lcv@nameblockwidth}%
    \raggedright%
    %% Hacky fix -- part 2 of 2; part 1 is \lcv@headerbreak above. Two more
    %% U+00A0 glyphs: one an interword space wide between the name parts, so
    %% extractors do not return "FirstnameLastname"; one zero-width in the
    %% TAGLINE's size closing the block -- the run an untagged reader measures.
    %%
    %% The name is the document's H1.
    \lcv@taggedpar{H1}{\namefont\color{name}%
      \ifdefempty{\lcv@firstname}{}%
      {\lcv@firstname\makebox[\fontdimen2\font][l]{\symbol{"00A0}}}%
      {\lcv@lightfont\lcv@lastname\makebox[0pt][l]{\taglinefont\symbol{"00A0}}}\par}%
    \vspace{\cvheaderskip}\vspace{\nametaggap}%
    %% The tagline is skipped entirely when the document set none (empty)
    \ifdefempty{\lcv@tagline}{}{%
      {\taglinefont\color{tagline}\lcv@headerbreak\lcv@tagline\par}%
      \vspace{\cvheaderskip}\vspace{\tagcontactgap}%
    }%
    %% The contact block, held to \cvinfowidth
    {\personalinfofont
     \@lcv@ininfotrue \global\@lcv@infoseenfalse
     \begin{minipage}[t]{\cvinfowidth}\raggedright\lcv@personalinfo\par\end{minipage}\par}%
    \end{minipage}%
    \hfill%
    \if@lcv@showphoto
      \hspace{\cvphotogutter}%
      %% Header's photo section:
      %% Zero height and depth, so the photo can never set the header's height
      \makebox[\dimexpr\lcv@photodiam+\lcv@photoinset\relax][l]{%
        \raisebox{0pt}[0pt][0pt]{%
          \ifdefempty{\lcv@photofile}
            {\lcv@makephotoplaceholder{\lcv@photodiam}}
            {\lcv@makephoto{\lcv@photodiam}{\lcv@photofile}}}}%
    \fi
    \par%
  \endgroup\vspace{\cvheadertrailskip}
  \global\@lcv@headerdonetrue
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% The body and its columns
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Asymmetric two-column split (65/35). \columnratio is exposed to the user.
\def\lcv@defaultcolratio{0.65}
\columnratio{\lcv@defaultcolratio}

%% Body contents wrapper allowing single- and two-column layouts switching.
%% Not hooked onto the document environment, so the header can be full width.
\newenvironment{cvbody}{%
  \if@lcv@onecolumn\else
    \begin{paracol}{2}%
  \fi
}{%
  \if@lcv@onecolumn\else
    \end{paracol}%
  \fi
}

%% Vertical offset applied to the column switched into (the 2nd), so the two
%% cols don't share the same baseline, making lines less likely to fuse.
%% This is hacky and should not be relied on. Use single col for best parsing.
%% Can be tuned by the caller: \renewcommand{\colshift}{0.4\baselineskip}
\newcommand{\colshift}{0.25\baselineskip}

%% Control switch to prevent applying the offset more than once.
\newif\if@lcv@shifted

%% Column switch command for the body. 2-col: switch; 1-col: new paragraph.
\newcommand{\cvcolumnbreak}{%
  \if@lcv@onecolumn \par \else \switchcolumn
    \if@lcv@shifted\else
      \vspace*{\colshift}%
      \global\@lcv@shiftedtrue
    \fi
  \fi
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Section and subsection headings
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Headings are mixed case for the best ATS parsability. Font sizes are in
%% points, and leadings are a multiple of the size. A document can tune sizes:
%%     \renewcommand{\cvsectionsize}{12}
%%     \renewcommand{\cvsubsectionsize}{9}
\if@lcv@compressed
  \newcommand{\cvsectionsize}{13}
  \newcommand{\cvsectionleading}{1.2}
  \newcommand{\cvsubsectionsize}{10}
  \newcommand{\cvsubsectionleading}{1.2}
\else
  \newcommand{\cvsectionsize}{16}
  \newcommand{\cvsectionleading}{1.25}
  \newcommand{\cvsubsectionsize}{11}
  \newcommand{\cvsubsectionleading}{1.25}
\fi

\newcommand{\cvsectionfont}{%
  \lcv@titlefont\lcv@sizeleading{\cvsectionsize}{\cvsectionleading}}
\newcommand{\cvsubsectionfont}{%
  \lcv@titlefont\lcv@sizeleading{\cvsubsectionsize}{\cvsubsectionleading}}

%% Air ABOVE the section heading -- scaling factor, has a guaranteed minimum.
%% May stretch, never shrink. See \cvsectionbelowgap for air below a heading.
\if@lcv@compressed
  \newcommand{\cvsectiongapratio}{0.7}
\else
  \newcommand{\cvsectiongapratio}{1.0}
\fi

%% Extra trim on top of \cvsection's own -0.7ex rule lift; for `compressed'.
\if@lcv@compressed
  \newcommand{\cvrulegaptrim}{0.25em}
\else
  \newcommand{\cvrulegaptrim}{0em}
\fi

%% Thickness of the rule under a \cvsection heading
\newlength{\cvrulewidth}
\setlength{\cvrulewidth}{0.4pt}

%% Lengths of gaps above section headings. Dynamic to scale with the font size.
\newlength{\lcv@secgap}        % the floor: ratio x the class size option
\newlength{\lcv@secdepth}      % this font's real descender depth
\newlength{\lcv@secprevdepth}  % depth of the line the heading follows

%% Air BELOW a section heading: from the rule to the top of a next element.
%% \cvsection drops the interline glue, elements open at the same distance.
%% Rigid on purpose: a `minus' would be undesirable, `plus' never fires.
\newlength{\cvsectionbelowgap}

\if@lcv@compressed
  \setlength{\cvsectionbelowgap}{0.39em}
\else
  \setlength{\cvsectionbelowgap}{0.7em}
\fi

%% Disarm the first-entry flag: a paragraph between heading and entry means
%% the entry regains its own \cventrytopsep. Headings re-arm the flag below.
\AddToHook{para/before}{\global\@lcv@firstentryfalse}

\newcommand{\cvsection}[1]{%
  \global\@lcv@aftergroupfalse      % Group flag is irrelevant for a new sec
  %% The gap above is absolute: contents leave varying trailing glue, so \par
  %% lands it on the vertical list, \removelastskip drops it, \vskip sets it.
  \par
  \removelastskip
  %% Anchor the gap to the previous baseline: \nointerlineskip stacks on that
  %% box, so subtract its depth and add a nominal one from the CURRENT font.
  \setlength{\lcv@secgap}{\cvsectiongapratio\dimexpr\f@size pt\relax}%
  \settodepth{\lcv@secdepth}{gjpqy}%
  \setlength{\lcv@secprevdepth}{\prevdepth}%
  %% Clamp low: at the top of a column \prevdepth is -1000pt.
  \ifdim\lcv@secprevdepth<\z@
    \setlength{\lcv@secprevdepth}{\z@}%
  \fi
  %% Clamp high: The emitted skip can never fall below \lcv@secgap.
  \ifdim\lcv@secprevdepth>\lcv@secdepth
    \setlength{\lcv@secprevdepth}{\lcv@secdepth}%
  \fi
  \nointerlineskip
  %% `plus' only, never `minus': the gap is a minimum that may stretch.
  \vskip\dimexpr\lcv@secgap+\lcv@secdepth-\lcv@secprevdepth\relax
    plus\dimexpr0.35\lcv@secgap\relax
  \lcv@taggedpar{H2}{\color{heading}\cvsectionfont #1\par}%
  \if@lcv@rule
    \vspace{-0.7ex}\vspace{-\cvrulegaptrim}%
  {\color{headingrule}\rule{\linewidth}{\cvrulewidth}\par}%
  \fi
  %% One absolute gap for EVERY follower. \nointerlineskip -- drops the glue
  %% from the follower's own \baselineskip; visible gap is exactly this skip.
  \nointerlineskip
  \vskip\cvsectionbelowgap\relax
  %% The next \cventry has no extra above air. The heading trailing sets it.
  \global\@lcv@firstentrytrue
}

%% \cvsubsection heading: a smaller heading than \cvsection, e.g. for grouping
%% entries within a section (such as publications by type).
\newlength{\cvsubsectionskip}

\if@lcv@compressed
  \setlength{\cvsubsectionskip}{0.15em}
\else
  \setlength{\cvsubsectionskip}{\smallskipamount}
\fi

\newcommand{\cvsubsection}[1]{%
  \global\@lcv@aftergroupfalse     % Group flag is irrelevant for a new heading
  \addvspace{\cvsubsectionskip}%
  \lcv@taggedpar{H3}{\color{subheading}\cvsubsectionfont #1\par}%
  \vskip\cvsubsectionskip\relax
  \global\@lcv@firstentrytrue
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% \cventry[key=value, ...]{Title}{Side text}{Date}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Base CV entry suitable for Jobs, Education, Projects, Awards, etc.
%%
%%   oneline      continues the header line with the date instead of stacking
%%                it underneath. Written bare, `oneline' means `oneline=true'.
%%                Defaults to FALSE, `compressed' class option defaults to
%%                TRUE. Writing the key explicitly overrides defaults.
%%   flushdate    carries the date to the RIGHT margin on a dotted leader.
%%                Dots are used for ATS compatibility -- otherwise, the date
%%                could be interpreted as a separate column and detached from
%%                the entry. Written bare, `flushdate' means `flushdate=true'.
%%                Defaults to the entry's OWN `oneline' value: a one-line
%%                entry flushes its date right unless `flushdate=false' is
%%                given, which keeps the date after the last bar instead.
%%                Stacked entries (oneline=false) ignore it.
%%   askip        vertical space ABOVE the entry. Defaults to
%%                \cventrytopsep. Placed with \addvspace -- it is a
%%                minimum rather than an addition. Skipped for a section's
%%                first entry unless stated explicitly.
%%   bskip        vertical space BELOW the entry. Defaults to \cventryskip.
%%   noscale      sets the entry at the document's own size, skipping the
%%                \cventryfontscale optical correction.
%%
%% Example oneline=false (the default) -- the date is on a separate line:
%%     Program Manager | Weyland Yutani Industries
%%     May 2021 - Current
%%
%% Example oneline=true -- the date is flushed right by default:
%%     Program Manager | Weyland Yutani Industries ..... May 2021 - Current
%%
%% Example oneline=true, flushdate=false -- the date stays after the last bar:
%%     Program Manager | Weyland Yutani Industries | May 2021 - Current

%% \cventryfontscale scales a smaller font to cover a difference in optical
%% size, as the same point size of Inter and Source Sans 3 visually differs.
%% Re-measure with \settoheight if family fonts are ever swapped.
%% Commands must reset to \normalsize or \footnotesize before scaling.
\newcommand{\cventryfontscale}{1.111}
\newlength{\lcv@entryfontsize}

%% Noscale key: leave the size the caller's original (unscaled) size
\newif\if@lcv@noscale
\newcommand{\lcv@entryscale}{%
  \if@lcv@noscale\else
    \setlength{\lcv@entryfontsize}{\cventryfontscale\dimexpr\f@size pt\relax}%
    \fontsize{\lcv@entryfontsize}{1.2\lcv@entryfontsize}\selectfont
  \fi}
\newcommand{\cventrytitlefont}{\lcv@titlefont\normalsize\lcv@entryscale}
\newcommand{\cventryorgfont}{\lcv@lightfont\normalsize\lcv@entryscale}
\newcommand{\cventrymetafont}{\lcv@titlefont\footnotesize\lcv@entryscale}

%% Entry separator (|). The mark is in the discretionary's no-break slot, so a
%% wrapped line drops it; `penalty 1' overrides the inherited \hyphenpenalty.
\newcommand{\cventryseparator}{%
  \discretionary penalty 1 {}{}{\kern0.35em\textbar\kern0.35em}%
}

%% The separator, dropped when every field to its left is empty.
\newcommand{\lcv@entrysep}[1]{\ifstrempty{#1}{}{\cventryseparator}}

%% Define true and false detokenized macros to allow true/false comparison
\edef\lcv@true{\detokenize{true}}
\edef\lcv@false{\detokenize{false}}

%% \cventry definition (public)
%% Arguments: #1 keyword arguments, #2 title, #3 side text, #4 date.
%%
%% \lcv@entryarg is detokenized by the key, so \ifx sees catcode-12 tokens.
%% Keys are re-initialised on EVERY call to prevent leakage later on the page.
%% Default \cventry gap below an entry, overridable via the `bskip=' key.
\newlength{\cventryskip}

\if@lcv@compressed
  \setlength{\cventryskip}{1.5pt plus 0.5pt minus 0.5pt}
\else
  \setlength{\cventryskip}{\smallskipamount}
\fi

%% Air ABOVE an entry, added with \addvspace, making it non-additive.
%% Specified as a fraction of \baselineskip to scale with the class font size.
\newcommand{\cventrytopsepratio}{0.25}
\newcommand{\cventrytopsepgluefrac}{0.3333}

\if@lcv@compressed
  \renewcommand{\cventrytopsepratio}{0.1667}
\fi

%% The stretch and shrink nest their \dimexpr
\newcommand{\cventrytopsep}{%
  \dimexpr\cventrytopsepratio\baselineskip\relax
  plus\dimexpr\cventrytopsepgluefrac
    \dimexpr\cventrytopsepratio\baselineskip\relax\relax
  minus\dimexpr\cventrytopsepgluefrac
    \dimexpr\cventrytopsepratio\baselineskip\relax\relax}

%% The first cventry in a Section uses the heading's own trailing glue, so
%% this flag ignores the first minimum cventry skip. Both headings arm it,
%% the para/before hook disarms it, \cventry and \cvsubentry consume it.
\newif\if@lcv@firstentry

%% Set when \cvgroup closes for additional gap before the next \cventry.
\newif\if@lcv@aftergroup

%% \cventry dispatched definition (public)
%% Arguments: #1 keyword arguments, #2 title, #3 side text, #4 date.
%% Keyword args:
%%   - oneline=true|false -- sets the entry on a single line
%%   - flushdate=true|false -- flushes a one-line date right; ignored otherwise
%%                             default: the entry's own oneline value
%%   - askip= -- ABOVE vertical space, overrides the section's first-entry flag
%%   - bskip= -- BELOW vertical space
%%   - noscale -- set at the document size, skipping \cventryfontscale
\newlength{\lcv@entry@askip}
\newlength{\lcv@entry@bskip}
\newif\if@lcv@askipgiven
%% Set by the `flushdate' handler, default \setkeys runs only when unspec.
\newif\if@lcv@flushdategiven
\define@key{lcv@entry}{oneline}[true]{\edef\lcv@entryarg{\detokenize{#1}}}
\define@key{lcv@entry}{flushdate}[true]{%
  \@lcv@flushdategiventrue
  \edef\lcv@flushdatearg{\detokenize{#1}}}
\define@key{lcv@entry}{askip}[\cventrytopsep]{%
  \@lcv@askipgiventrue
  \setlength{\lcv@entry@askip}{#1}}
\define@key{lcv@entry}{bskip}[\cventryskip]{%
  \setlength{\lcv@entry@bskip}{#1}}
\define@key{lcv@entry}{noscale}[]{\@lcv@noscaletrue}

\NewDocumentCommand{\cventry}{ O{} m m m }{%
  %% Oneline defaults to FALSE, true for `compressed'. Setting here overrides
  %% defaults. Compressed is thus processed before \setkeys.
  \if@lcv@compressed
    \edef\lcv@entryarg{\detokenize{true}}%
  \else
    \edef\lcv@entryarg{\detokenize{false}}%
  \fi
  \setlength{\lcv@entry@askip}{\cventrytopsep}%
  \setlength{\lcv@entry@bskip}{\cventryskip}%
  \@lcv@askipgivenfalse
  \@lcv@flushdategivenfalse
  \@lcv@noscalefalse
  %% Obtain the provided arguments (replace defaults)
  \setkeys{lcv@entry}{#1}%
  %% Flushdate defaults to the oneline flag: one line entries flush their date
  %% unless `flushdate=false' given. Stacked entries ignore it.
  \if@lcv@flushdategiven\else
    \ifx\lcv@entryarg\lcv@true
      \let\lcv@flushdatearg\lcv@true
    \else
      \let\lcv@flushdatearg\lcv@false
    \fi
  \fi
  %% Air after a \cvgroup: an explicit askip= keeps the last word
  \if@lcv@aftergroup
    \global\@lcv@aftergroupfalse
    \if@lcv@askipgiven\else\par\addvspace{\cvgroupsep}\fi
  \fi
  %% Air above the entry -- non-additive; suppressed for a section's 1st entry
  \if@lcv@firstentry
    \global\@lcv@firstentryfalse
    \if@lcv@askipgiven\par\addvspace{\lcv@entry@askip}\fi
  \else
    \par\addvspace{\lcv@entry@askip}%
  \fi
  \lcv@entry{#2}{#3}{#4}%
}

%% \lcv@entry definition (private of \cventry)
%% Arguments: #1 title, #2 side text, #3 date. The oneline flag arrives in
%% \lcv@entryarg, already detokenized by the key.
%% Serves as a dispatcher for the correct entry type (oneline/stacked).
%% Only a literal `true' is oneline, so a is silenced and nothing happens.
\newcommand{\lcv@entry}[3]{%
  \ifx\lcv@entryarg\lcv@true
    \lcv@entry@oneline{#1}{#2}{#3}%
  \else
    \lcv@entry@stacked{#1}{#2}{#3}%
  \fi
}

%% Filler that carries the date to the right margin for the `flushdate' key.
%% A dotted leader prevents the phenomenon in geometry-based extractors,
%% which would otherwise interpret the flushed date as a separate column.
\newcommand{\cventrydateleadersep}{0.333em}
\newcommand{\cventrydateleadergap}{0.35em}
\newcommand{\cventrydatefill}{%
  \unskip\nobreak\hskip\cventrydateleadergap\relax
  \leaders\hbox to \cventrydateleadersep{\hss{\color{entryleader}.}\hss}\hfill
  \penalty9999\hskip\cventrydateleadergap\hbox{}%
}

%% One line CV entry. The date takes the organization's font, size AND color.
%% \unskip before each separator group drops a trailing space inside an arg.
\newcommand{\lcv@entry@oneline}[3]{%
  {\color{emphasis}\cventrytitlefont #1%
   \ifstrempty{#2}{}{%
     \unskip{\color{entryorg}\cventryorgfont\lcv@entrysep{#1}#2}}%
   \ifstrempty{#3}{}{%
     \ifx\lcv@flushdatearg\lcv@true
       \cventrydatefill{\color{entryorg}\cventryorgfont#3}%
     \else
       \unskip{\color{entryorg}\cventryorgfont\lcv@entrysep{#1#2}#3}%
     \fi}%
   \unskip\par}%
  \vskip\lcv@entry@bskip\relax
}

%% Stacked line entry -- separate date line, left aligned
\newcommand{\lcv@entry@stacked}[3]{%
  {\color{emphasis}\cventrytitlefont #1%
   \ifstrempty{#2}{}{%
     \unskip{\color{entryorg}\cventryorgfont\lcv@entrysep{#1}#2}}%
   \unskip\par}%
  \ifstrempty{#3}{}{\nopagebreak{\color{meta}\cventrymetafont #3\unskip\par}}%
  \vskip\lcv@entry@bskip\relax
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Sub-entries and related CV group API:
%%    \begin{cvgroup}[rule] ... \end{cvgroup}
%%    \cvsubentry[key=value, ...]{Title}{Side text}{Date}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% A \cventry may have subordinates, e.g. several positions at one employer. To
%% visualize such a relationship, \cvgroup environment is used. Inside, the
%% \cvsubentry elements with their own text or itemize text are placed. Usage:
%%
%%     Employer | City, Country | 09/2021 - 06/2026     (\cventry)
%%                                                      (\begin{cvgroup}[rule])
%%        Position 2 | 09/2023 - 06/2026                (\cvsubentry)
%%        - Bullets for position 2                      (\itemize)
%%        Position 1 | 09/2021 - 08/2023                (\cvsubentry)
%%        - Bullets for position 1                      (\itemize)
%%                                                      (\end{cvgroup})
%% \cvgroup keyword args:
%%   - rule       draw a vertical rule half-way into the indent. Default: false
%%
%% \cvsubentry keyword args:
%%   - oneline      as in \cventry, but defaults to TRUE in every mode,
%%                  `compressed' or not. `oneline=false' stacks the date.
%%   - flushdate    as in \cventry: carries the date to the right margin.
%%                  Defaults to the sub-entry's own `oneline' value.
%%   - askip        vertical space ABOVE. Bare `askip' = \cventrytopsep.
%%                  Default: 0pt for the group's first sub-entry, otherwise the
%%                  minimum air of \cventrytopsep (non-additive)
%%   - bskip        vertical space BELOW. Default 0pt. `bskip' = \cventryskip.
%%
%% The group is set in a box that `framed' then splits across pages. Therefore,
%% it cannot handle footnotes, floats or \cvsection inside it.

%% ------------ CV Group ------------
%% Left indent of everything inside a \cvgroup, wrapped lines included.
\newcommand{\cvgroupindent}{1.2em}

%% Air above the \cventry following a \cvgroup. Dropped under `compressed'.
\newcommand{\cvgroupsepratio}{0.5}
\if@lcv@compressed
  \renewcommand{\cvgroupsepratio}{0}
\fi

\newcommand{\cvgroupsep}{%
  \dimexpr\cvgroupsepratio\baselineskip\relax
  plus\dimexpr\cventrytopsepgluefrac
    \dimexpr\cvgroupsepratio\baselineskip\relax\relax
  minus\dimexpr\cventrytopsepgluefrac
    \dimexpr\cvgroupsepratio\baselineskip\relax\relax}

%% Rule: thickness, place (fraction of the indent) and color `grouprule', which
%% follows \cvaccent (see \lcv@deriveaccent).
\newlength{\cvgrouprulewidth}
\setlength{\cvgrouprulewidth}{1.25pt}
\newcommand{\cvgrouprulepos}{0.5}

%% Set while no \cvsubentry has been placed in the current group yet.
\newif\if@lcv@groupfirst

%% Group keyword arguments: Rule. Only a literal `true' draws the rule
\newif\if@lcv@grouprule
\define@key{lcv@group}{rule}[true]{%
  \ifstrequal{#1}{true}{\@lcv@groupruletrue}{\@lcv@grouprulefalse}}

%% The gaps left and right of the rule. They take exactly \cvgroupindent.
\newlength{\lcv@grouplgap}
\newlength{\lcv@grouprgap}
\newlength{\lcv@groupdepth}
\newlength{\lcv@groupfirstht}

%% Definition: \begin{cvgroup} ... \end{cvgroup}
\NewDocumentEnvironment{cvgroup}{ O{} }{%
  \par
  \@lcv@grouprulefalse
  \setkeys{lcv@group}{#1}%
  \global\@lcv@groupfirsttrue
  \setlength{\OuterFrameSep}{\z@}%
  %% Real height of a sub-entry line so the gaps are the same at any font size.
  \settoheight{\lcv@groupfirstht}{\cvsubentrytitlefont Mkl|}%
  \edef\FrameHeightAdjust{\the\lcv@groupfirstht}%
  \setlength{\lcv@grouplgap}{\dimexpr
    \cvgrouprulepos\dimexpr\cvgroupindent\relax
    -0.5\cvgrouprulewidth\relax}%
  \setlength{\lcv@grouprgap}{\dimexpr
    \cvgroupindent-\lcv@grouplgap-\cvgrouprulewidth\relax}%
  \if@lcv@grouprule
    \def\FrameCommand{%
      \hskip\lcv@grouplgap
      {\color{grouprule}\vrule width\cvgrouprulewidth}%
      \hskip\lcv@grouprgap}%
  \else
    \def\FrameCommand{\hskip\cvgroupindent}%
  \fi
  \MakeFramed{\advance\hsize-\width\FrameRestore}%
}{%
  %% The gap below the group should be \cvgroupsep. Apply \unskip to drop the
  %% excess gap from the last line of the group (e.g., list).
  \par\unskip
  \global\lcv@groupdepth=\prevdepth
  \endMakeFramed
  \ifdim\lcv@groupdepth>-999pt \prevdepth=\lcv@groupdepth \fi
  %% Closing air outside the frame
  \par\addvspace{\cventrytopsep}%
  \global\@lcv@aftergrouptrue
}

%% ------------ Sub-entries ------------
%% Subentry keyword arguments
\newlength{\lcv@subentry@askip}
\newlength{\lcv@subentry@bskip}
\newif\if@lcv@subaskipgiven
\define@key{lcv@subentry}{oneline}[true]{\edef\lcv@entryarg{\detokenize{#1}}}
\define@key{lcv@subentry}{flushdate}[true]{%
  \@lcv@flushdategiventrue
  \edef\lcv@flushdatearg{\detokenize{#1}}}
\define@key{lcv@subentry}{askip}[\cventrytopsep]{%
  \@lcv@subaskipgiventrue
  \setlength{\lcv@subentry@askip}{#1}}
\define@key{lcv@subentry}{bskip}[\cventryskip]{%
  \setlength{\lcv@subentry@bskip}{#1}}

%% Fonts: same faces as \cventry, at \normalsize instead of the scaled size.
\newcommand{\cvsubentrytitlefont}{\lcv@titlefont\normalsize}
\newcommand{\cvsubentryorgfont}{\lcv@lightfont\normalsize}
\newcommand{\cvsubentrymetafont}{\lcv@titlefont\footnotesize}

%% Definition: cvsubentry[key=value, ...]{Title}{Side text}{Date}
\NewDocumentCommand{\cvsubentry}{ O{} m m m }{%
  %% Oneline defaults to TRUE regardless of `compressed'
  \edef\lcv@entryarg{\detokenize{true}}%
  \setlength{\lcv@subentry@askip}{\z@}%
  \setlength{\lcv@subentry@bskip}{\z@}%
  \@lcv@subaskipgivenfalse
  \@lcv@flushdategivenfalse
  \setkeys{lcv@subentry}{#1}%
  %% Flushdate defaults to the oneline flag, as in \cventry
  \if@lcv@flushdategiven\else
    \ifx\lcv@entryarg\lcv@true
      \let\lcv@flushdatearg\lcv@true
    \else
      \let\lcv@flushdatearg\lcv@false
    \fi
  \fi
  %% Consume the section's first-entry flag, so nothing leans on a heading
  \global\@lcv@firstentryfalse
  \par
  %% Air above: an explicit askip= is added as is; otherwise every sub-entry
  %% the group's first gets the small minimum air between sibling positions.
  \if@lcv@subaskipgiven
    \vskip\lcv@subentry@askip\relax
  \else
    \if@lcv@groupfirst\else\addvspace{\cventrytopsep}\fi
  \fi
  \global\@lcv@groupfirstfalse
  %% The \cventry renderers, set in the sub-entry fonts within a group
  \begingroup
    \let\cventrytitlefont\cvsubentrytitlefont
    \let\cventryorgfont\cvsubentryorgfont
    \let\cventrymetafont\cvsubentrymetafont
    \setlength{\lcv@entry@bskip}{\lcv@subentry@bskip}%
    \lcv@entry{#2}{#3}{#4}%
  \endgroup
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Tags and tag lists
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Tags are TikZ-drawn chips. For improved ATS parsability, real space glyph
%% (U+0020) is inserted at their beginning, so the PDF parser does not fuse the
%% chip contents together (\cvtagspace). Furthermore, spaces inside the chip
%% are replaced with a real space glyph to prevent fusing of the chip contents.

%% Define the 0pt space glyph (chip's start) and trailing gutter after it.
\newcommand{\cvtagspace}{\makebox[0pt][l]{\symbol{"0020}}}
\newcommand{\cvtagsep}{\hspace{0.2em}}

%% Substitutes the word gaps INSIDE a chip with a real space glyph (U+0020).
%% \DocumentMetadata{tagging=on} does this inside the whole document, but LaTeX
%% suspends tagging inside a pgfpicture environment.
\ExplSyntaxOn
\seq_new:N \l__lcv_tag_seq
\tl_new:N  \l__lcv_tag_tl

\NewDocumentCommand{\lcv@tagtext}{m}{
  \tl_set:Nn \l__lcv_tag_tl {#1}
  \tl_trim_spaces:N \l__lcv_tag_tl
  \seq_set_split:NnV \l__lcv_tag_seq { ~ } \l__lcv_tag_tl
  \seq_use:Nn \l__lcv_tag_seq { \symbol{"0020} }
}
\ExplSyntaxOff

%% Set the chip text to scale 0.9 size of the class font size.
\newcommand{\cvtagfontscale}{0.9}
\newcommand{\cvtagleading}{1.2}
\newlength{\lcv@tagfontsize}
\newcommand{\cvtagfont}{%
  \normalsize
  \setlength{\lcv@tagfontsize}%
    {\cvtagfontscale\dimexpr\f@size pt\relax}%
  \fontsize{\lcv@tagfontsize}
           {\cvtagleading\lcv@tagfontsize}\selectfont}

%% Vertical gap between the text and the chip border (per side), and the extra
%% room reserved below the chip so wrapped chip rows keep their borders apart.
\newcommand{\cvtagysep}{0.35ex}
\newcommand{\cvtaglinegap}{0.3ex}

%% The chip's text height and depth
\newcommand{\cvtagheight}{1.45ex}
\newcommand{\cvtagdepth}{0.4ex}

%% \cvtag{text} definition
%% Draws a TikZ node around the text, substituting gaps with real spaces using
%% \lcv@tagtext, delimiting tag start with a space, and adding a gutter.
%% Values deliberately set as such so parsers won't mistake them for chars.
%% Lines end in % -- otherwise the newlines add space tokens to the gutter.
%% The invisible rule is a strut of \cvtaglinegap to keep wrapped rows apart.
\newcommand{\cvtag}[1]{%
  \cvtagspace%
  {\cvtagfont%
   \tikz[baseline]\node[anchor=base,draw=accent!30,line width=0.25pt,fill=accent!6,text=emphasis,%
     rounded corners=2.5pt,inner xsep=0.75ex,inner ysep=\cvtagysep,%
     text height=\cvtagheight,text depth=\cvtagdepth]{\lcv@tagtext{#1}};%
   \rule[-\dimexpr\cvtagdepth+\cvtagysep+\cvtaglinegap\relax]{0pt}%
        {\dimexpr\cvtagheight+\cvtagysep
               +\cvtagdepth+\cvtagysep+\cvtaglinegap\relax}%
  }%
  \cvtagsep%
}

%% CV Tag list settings:
%% Space between the tags.
\newcommand{\cvtaglistgap}{0.2em}

%% Tag separator, as a discretionary so a line might be wrapped around it.
%% Carries its own penalty 1, because the class disables hyphenation globally.
\newcommand{\lcv@taglistsep}{%
  \discretionary penalty 1 {%
    \kern\cvtaglistgap\mbox{\cvtagspace\cvtaglistmark}}{}{%
    \kern\cvtaglistgap\mbox{\cvtagspace\cvtaglistmark}\kern\cvtaglistgap}%
}

%% Tags separator symbol. Use en-dash for best ATS compatibility:
%%  - \symbol{"0020}        --> real space might break some ATSs
%%  - \textbullet           --> bullet might break OCRs
%%  - {\color{taglistmark}\textendash}  --> dash looks awful, but works
\newcommand{\cvtaglistmark}{{\color{taglistmark}\textendash}}

%% \cvtaglist{a, b, c}
%% Creates a list of tags (\cvtag) with a delimiter between them.
%% Created because ATSs need a delimiter between tags, and including commas
%% manually created a floating comma state ("C++ , Embedded Systems").
%% The input takes a comma-separated list.
\ExplSyntaxOn
\seq_new:N  \l__lcv_taglist_seq
\tl_new:N   \l__lcv_taglistitem_tl
\bool_new:N \l__lcv_taglistfirst_bool
\NewDocumentCommand{\cvtaglist}{m}{
  \group_begin:
    %% \cvtagsep would otherwise land between a chip and a bullet unbalanced
    \renewcommand{\cvtagsep}{}
    \seq_set_split:Nnn \l__lcv_taglist_seq {,} {#1}
    \bool_set_true:N \l__lcv_taglistfirst_bool
    %% Trim and test BEFORE the sep: trailing comma would cause an empty bullet
    \seq_map_inline:Nn \l__lcv_taglist_seq {
      \tl_set:Nn \l__lcv_taglistitem_tl {##1}
      \tl_trim_spaces:N \l__lcv_taglistitem_tl
      \tl_if_empty:NF \l__lcv_taglistitem_tl {
        \bool_if:NTF \l__lcv_taglistfirst_bool
          { \bool_set_false:N \l__lcv_taglistfirst_bool }
          { \lcv@taglistsep }
        \exp_args:NV \cvtag \l__lcv_taglistitem_tl
      }
    }
  \group_end:
  %% \cvtagsep restored, so the gutter corresponds to a standalone cvtag
  \cvtagsep
}
\ExplSyntaxOff

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% \cvref -- Referees
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% \cvref{name}{email}{mailing address}
%% Renders a reference entry as a hanging-indent block, icon in its own column.
\newlength{\cvrefindent}
\setlength{\cvrefindent}{1.9em}

\newlength{\cvrefskip}

\if@lcv@compressed
  \setlength{\cvrefskip}{0.15em}
\else
  \setlength{\cvrefskip}{\smallskipamount}
\fi

%% The referee's name font
\newcommand{\cvrefnamefont}{\bfseries}

%% One icon + text line with wrapping (internal)
\newcommand{\lcv@refline}[2]{%
  \par\noindent
  \hangindent=\cvrefindent\hangafter=1  % 1st line full-width, others indented
  \makebox[\cvrefindent][l]{\small\normalfont\color{accent}\lcv@refsymbol{#1}}%
  #2\par
}

%% The whole reference block with name, e-mail, and mailing address (public)
\newcommand{\cvref}[3]{%
  \addvspace{\cvrefskip}%
  {\color{emphasis}\cvrefnamefont #1}\par
  \if@lcv@icons
    %% `icons': draw email and mail address icons, extracted as whitespace.
    \lcv@refline{\lcv@fieldicon{email}}{#2}%
    \lcv@refline{\lcv@fieldicon{mailaddress}}{#3}%
  \else
    %% `noicons': an address and an email need no pictogram to be recognised.
    #2\par
    #3\par
  \fi
}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% \lastupdated -- Last-updated date stamp
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Bottom-right date stamp on the last page (optional).
\newcommand{\cvlastupdatedtext}{Last update:}       % The stamp's label
\newcommand{\cvstampwidth}{60mm}

%% The stamp's vertical offset from the bottom margin center (default).
%% Positive values move it down, negative upward.
\newcommand{\cvstampvshift}{-0.1em}

%% Wanted this run/already declared. Two flags, because the last page can
%% ship before \lastupdated runs.
\newif\if@lcv@stampwanted
\newif\if@lcv@stampseen

%% Written to the .aux, executed when the next pass reads it back.
\newcommand{\@lcv@stampdeclared}{\global\@lcv@stampwantedtrue}

%% The side margin in force on the page being shipped; even pages under
%% `twoside' are laid out from \evensidemargin.
\newcommand{\lcv@stampsidemargin}{%
  \if@twoside\ifodd\value{page}\oddsidemargin\else\evensidemargin\fi
  \else\oddsidemargin\fi
}

\newlength{\lcv@stampy}          % Stamp's position

%% Draw the stamp: flush right, vertically centred in the bottom margin.
\newcommand{\lcv@drawstamp}{%
  \setlength{\lcv@stampy}{%
    \dimexpr\paperheight-1in-\topmargin-\headheight-\headsep-\textheight\relax}%
  \setlength{\lcv@stampy}{0.5\lcv@stampy}%            half of it: the middle
  \addtolength{\lcv@stampy}{-\cvstampvshift}%         the caller's nudge
  \addtolength{\lcv@stampy}{\dimexpr 1in-\paperheight\relax}%  hook's origin
  \put(\strip@pt\dimexpr\lcv@stampsidemargin+\textwidth-\cvstampwidth\relax,
       \strip@pt\lcv@stampy){%
    \raisebox{-\dimexpr(\height-\depth)/2\relax}{%
      \makebox[\cvstampwidth][r]{%
        \color{CVDate}\personalinfofont \cvlastupdatedtext\ \today}}}%
}

%% Armed at class load, never depends on when the .aux is read.
\AddToHook{shipout/lastpage}{\if@lcv@stampwanted\lcv@drawstamp\fi}

%% Declares the stamp. No arguments; may be called anywhere in the document.
\newcommand{\lastupdated}{%
  \if@lcv@stampseen\else
    \global\@lcv@stampseentrue
    \global\@lcv@stampwantedtrue
    \if@filesw
      \immediate\write\@auxout{\string\@lcv@stampdeclared}%
    \fi
  \fi
}

\endinput

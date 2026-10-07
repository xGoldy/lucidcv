# latexmk config. Used by Overleaf and local `latexmk` commands.
# Compile the project via LuaLaTeX; Needed for tagging=on document metadata
$pdf_mode = 4;          # 4 = lualatex

# Disable the creation of .ps and .dvi files. Create .pdf only
$postscript_mode = 0;
$dvi_mode = 0;

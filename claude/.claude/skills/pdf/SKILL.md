---
name: pdf
description: Use when the user wants to convert a Markdown file to PDF — "/pdf", "make a PDF of this .md", "export docs/foo.md to PDF", "create a pdf version of <file>.md". Renders the Markdown to a styled A4 PDF and writes it next to the source file by default. Handles tables, blockquotes, code blocks and relative images.
---

# pdf — Markdown → PDF

Convert a Markdown file to a styled PDF using the bundled pandoc → WeasyPrint
pipeline. By default the PDF is written **next to the source file** (same path,
`.pdf` extension).

## How it works

Everything is self-contained in this skill directory:

- `md2pdf.sh` — the converter script (pandoc for MD→HTML, WeasyPrint for HTML→PDF)
- `.venv/` — a dedicated Python venv with WeasyPrint installed (do not delete)
- `style.css` — print stylesheet (A4, branded headings, styled tables/callouts)

## Steps

1. **Identify the input** `.md` file from the user's request. If they didn't name
   one, ask which file. If they gave a bare name, resolve it to a real path first.

2. **Run the converter.** Output defaults to the source path with a `.pdf`
   extension (i.e. next to the file), which is what the user almost always wants:

   ```bash
   bash ~/.claude/skills/pdf/md2pdf.sh <input.md>
   ```

   To write elsewhere, pass an explicit second argument:

   ```bash
   bash ~/.claude/skills/pdf/md2pdf.sh <input.md> <output.pdf>
   ```

3. **Verify** the output exists and looks right, then report the path and page
   count:

   ```bash
   ~/.claude/skills/pdf/.venv/bin/python -c "from pypdf import PdfReader; import sys; r=PdfReader(sys.argv[1]); print('pages:', len(r.pages))" <output.pdf>
   ```

   (`pypdf` may not be installed — if the import fails, just confirm the file
   exists with `ls -la` and report its size; the script already errors out if
   WeasyPrint failed.)

## Notes

- Relative images and links in the Markdown resolve against the source file's
  directory — keep the source in place when converting.
- Requires system `pandoc` (already present) and the bundled `.venv`. If the venv
  is ever missing, recreate it:
  `python3 -m venv ~/.claude/skills/pdf/.venv && ~/.claude/skills/pdf/.venv/bin/pip install weasyprint`
- To restyle output, edit `style.css` — no code change needed.

#!/usr/bin/env bash
# md2pdf.sh <input.md> [output.pdf]
# Converts a Markdown file to a styled PDF. Defaults output to the same path
# with a .pdf extension (i.e. next to the source file).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PY="$HERE/.venv/bin/python"
STYLE="$HERE/style.css"

if [[ $# -lt 1 ]]; then
  echo "usage: md2pdf.sh <input.md> [output.pdf]" >&2
  exit 2
fi

IN="$1"
if [[ ! -f "$IN" ]]; then
  echo "error: input file not found: $IN" >&2
  exit 1
fi

OUT="${2:-${IN%.*}.pdf}"

command -v pandoc >/dev/null || { echo "error: pandoc not installed" >&2; exit 1; }
[[ -x "$VENV_PY" ]] || { echo "error: weasyprint venv missing at $HERE/.venv" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Inline the stylesheet via a header include (pandoc 2.9-compatible).
{ printf '<style>\n'; cat "$STYLE"; printf '\n</style>\n'; } > "$TMP/header.html"

TITLE="$(basename "${IN%.*}")"

# Render Markdown -> standalone HTML. --resource-path lets relative images resolve.
pandoc "$IN" -s --metadata title="$TITLE" \
  --resource-path="$(dirname "$IN")" \
  -H "$TMP/header.html" \
  -o "$TMP/doc.html"

# HTML -> PDF. base_url = source dir so relative images/links resolve.
"$VENV_PY" -m weasyprint "$TMP/doc.html" "$OUT" --base-url "$(dirname "$IN")/"

echo "wrote: $OUT"

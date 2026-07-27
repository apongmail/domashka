#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANDOC="${PANDOC:-/opt/homebrew/bin/pandoc}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
CSS="$ROOT/assets/report.css"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/domashka-reports.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

for number in 05 06; do
  source="$ROOT/domashka-$number/report_domashka-$number.md"
  html="$BUILD_DIR/report_domashka-$number.html"
  pdf="$ROOT/domashka-$number/report_domashka-$number.pdf"

  "$PANDOC" "$source" \
    --from=gfm \
    --to=html5 \
    --standalone \
    --embed-resources \
    --resource-path="$ROOT/domashka-$number" \
    --css="$CSS" \
    --metadata="lang:uk" \
    --metadata="pagetitle:Домашнє завдання $number" \
    --output="$html"

  "$CHROME" \
    --headless=new \
    --disable-gpu \
    --no-pdf-header-footer \
    --print-to-pdf="$pdf" \
    "file://$html" >/dev/null 2>&1

  echo "Built ${pdf#$ROOT/}"
done
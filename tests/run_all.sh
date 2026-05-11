#!/usr/bin/env bash
# Runs every test suite. Must be invoked from the repo root.
set -euo pipefail

if ! command -v lua >/dev/null; then
    echo "lua is required" >&2; exit 1
fi
if ! command -v qpdf >/dev/null; then
    echo "qpdf is required" >&2; exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "python3 is required" >&2; exit 1
fi

# Make sure the fixture PDF is in place (regenerate if missing)
if [ ! -f tests/fixtures/portrait.pdf ]; then
    echo "Generating tests/fixtures/portrait.pdf …"
    python3 - <<'PY'
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
c = canvas.Canvas("tests/fixtures/portrait.pdf", pagesize=A4)
for i in range(1, 4):
    c.setFont("Helvetica", 200); c.drawString(150, 500, f"P{i}")
    c.setFont("Helvetica", 30); c.drawString(150, 300, "PORTRAIT")
    c.showPage()
c.save()
PY
fi
if [ ! -f tests/fixtures/sample.xopp ]; then
    echo "Generating tests/fixtures/sample.xopp …"
    gzip -c tests/fixtures/sample.xopp.xml > tests/fixtures/sample.xopp
fi

echo "== syntax check =="
lua -e "assert(loadfile('PageRotator/main.lua'))"
echo "  ok"

if command -v luacheck >/dev/null; then
    echo "== luacheck =="
    luacheck PageRotator
fi

echo "== test_rotation.lua (unit) =="
lua tests/test_rotation.lua

echo "== test_xopp_edit.lua =="
lua tests/test_xopp_edit.lua

echo "== test_e2e.lua =="
lua tests/test_e2e.lua

echo
echo "All tests passed."

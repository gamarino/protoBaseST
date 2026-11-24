#!/usr/bin/env python3
"""Print deck.html and en/deck.html to slides/*.pdf.

Each deck is the source: one <section> per slide on a 1920x1080 canvas, every
style inline, speaker notes in <aside>. A browser needs a few rules to print it
as one slide per page (zero margins, notes hidden, table rules), so this script
adds them to a temporary copy and prints that copy with a headless Chromium
(Chrome, Chromium or Edge).

Usage: python3 render_pdf.py [path/to/chrome]

Outputs:
  slides/protoBaseST-FAS-registro-2026-12-03.pdf      (Spanish, deck.html)
  slides/protoBaseST-FAS-registry-2026-12-03-en.pdf   (English, en/deck.html)

The temporary copies and the browser profile go to a fresh temporary directory, removed at the end;
set RENDER_TMPDIR to an existing directory to use (and keep) that one instead.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
DECKS = [
    (HERE / "deck.html", HERE / "slides" / "protoBaseST-FAS-registro-2026-12-03.pdf"),
    (HERE / "en" / "deck.html", HERE / "slides" / "protoBaseST-FAS-registry-2026-12-03-en.pdf"),
]

PRINT_CSS = """<style>
@page { size: 1920px 1080px; margin: 0; }
html, body { margin: 0; padding: 0; }
* { box-sizing: border-box; margin: 0; }
section { width: 1920px; height: 1080px; position: relative; overflow: hidden;
          page-break-after: always; break-after: page; }
aside { display: none; }
h1, h2, h3 { font-weight: 600; }
p { font-size: 32px; line-height: 1.4; }
ul, ol { font-size: 32px; line-height: 1.4; padding-left: 1.3em; }
li + li { margin-top: 0.2em; }
table { border-collapse: collapse; width: 100%; }
th, td { padding: 0.35em 0.6em; text-align: left; vertical-align: top;
         border-bottom: 1px solid rgba(127,127,127,0.35); }
th { font-weight: 600; }
[style*="JetBrains"] { font-variant-ligatures: none; }
</style>
"""

CANDIDATES = ["google-chrome", "chromium", "chromium-browser", "msedge",
              r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
              r"C:\Program Files\Google\Chrome\Application\chrome.exe",
              "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]


def find_browser():
    if len(sys.argv) > 1:
        return sys.argv[1]
    for c in CANDIDATES:
        found = shutil.which(c) or (c if Path(c).exists() else None)
        if found:
            return found
    sys.exit("no Chromium found; pass its path as the first argument")


def wait_for_pdf(out, before, timeout=120):
    # Edge on Windows hands the job to a browser process and returns before
    # the PDF is written: wait until a new file exists and stops growing.
    deadline = time.time() + timeout
    last = -1
    while time.time() < deadline:
        st = out.stat() if out.exists() else None
        size = st.st_size if st and st.st_mtime_ns != before else -1
        if size > 0 and size == last:
            return
        last = size
        time.sleep(1)
    sys.exit(f"no PDF written to {out}")


def render(tmp, browser, source, out, n):
    deck = source.read_text(encoding="utf-8")
    page = Path(tmp) / f"print-{n}.html"
    page.write_text(deck.replace("</head>", PRINT_CSS + "</head>", 1), encoding="utf-8")
    out.parent.mkdir(exist_ok=True)
    before = out.stat().st_mtime_ns if out.exists() else None
    subprocess.run([browser, "--headless=new", "--disable-gpu",
                    "--no-pdf-header-footer", f"--user-data-dir={tmp}/profile-{n}",
                    "--virtual-time-budget=20000", f"--print-to-pdf={out}",
                    page.as_uri()], check=True)
    wait_for_pdf(out, before)
    print(out)


def main():
    browser = find_browser()
    keep = os.environ.get("RENDER_TMPDIR")
    for n, (source, out) in enumerate(DECKS):
        if keep:
            render(keep, browser, source, out, n)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                render(tmp, browser, source, out, n)


if __name__ == "__main__":
    main()

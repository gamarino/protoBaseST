#!/usr/bin/env bash
# Guards the repository's own markdown links: every link from a tracked .md file to another
# tracked .md file, or to a heading of the same file, must name a file that exists and, when it
# has a #anchor, a heading of that file with that anchor. Anchors are GitHub's: the heading text
# lower-cased, every character that is not a letter, a digit, a space, a hyphen or an underscore
# dropped, spaces turned into hyphens, and -1, -2 ... added to repeated anchors; an explicit
# <a id="..."> or <a name="..."> also counts. Links inside fenced code blocks and inline code are
# skipped, as are external links (with a scheme) and links outside the repository. docs/superpowers/
# (specs and plans, written before the code) is not checked as a source.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found, the anchor guard cannot run"; exit 1; }
cd "$REPO" || exit 1
git ls-files '*.md' | python3 -I -c '
import os, re, sys
files = [l.strip() for l in sys.stdin if l.strip()]
tracked = set(files)
anchors_cache = {}
def strip_code(text):
    out, fence = [], False
    for line in text.split("\n"):
        if re.match(r"^\s*(```|~~~)", line):
            fence = not fence; out.append(""); continue
        out.append("" if fence else re.sub(r"`[^`]*`", "", line))
    return out
def slug(heading):
    h = re.sub(r"<[^>]+>", "", heading)
    h = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", h)
    h = h.strip().lower()
    h = re.sub(r"[^\w\- ]", "", h)
    return h.replace(" ", "-")
def anchors(path):
    if path in anchors_cache: return anchors_cache[path]
    seen, out = {}, set()
    fence = False
    for line in open(path, encoding="utf-8").read().split("\n"):
        if re.match(r"^\s*(```|~~~)", line): fence = not fence; continue
        if fence: continue
        m = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
        if m:
            s = slug(m.group(1).replace("`", ""))
            n = seen.get(s, 0); seen[s] = n + 1
            out.add(s if n == 0 else "%s-%d" % (s, n))
        for a in re.findall(r"<a\s+(?:id|name)=\"([^\"]+)\"", line): out.add(a)
    anchors_cache[path] = out
    return out
bad, checked = [], 0
for src in files:
    if src.startswith("docs/superpowers/") or src.startswith(".superpowers/"): continue
    for n, line in enumerate(strip_code(open(src, encoding="utf-8").read()), 1):
        for target in re.findall(r"\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", line):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target): continue
            path, _, anchor = target.partition("#")
            dest = os.path.normpath(os.path.join(os.path.dirname(src), path)) if path else src
            if dest.startswith(".."): continue
            if path and not dest.endswith(".md"):
                if not os.path.exists(dest): bad.append("%s:%d: %s: no such file" % (src, n, target))
                continue
            if dest not in tracked:
                bad.append("%s:%d: %s: not a tracked markdown file" % (src, n, target)); continue
            checked += 1
            if anchor and anchor not in anchors(dest):
                bad.append("%s:%d: %s: %s has no heading with that anchor" % (src, n, target, dest))
for b in bad: print(b)
if bad:
    print("FAIL: %d broken markdown links" % len(bad)); sys.exit(1)
print("markdown links: %d links to markdown files and anchors resolve" % checked)
'

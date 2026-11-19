#!/usr/bin/env bash
# The checklist of proto_db's cluster tests (spec 6.2): every test function of the
# tests/unit/test_cluster_*.py files of proto_db v2.0.0rc4 has one row in cluster_checklist.tsv,
# and every row is one of:
#   ported    <protoBaseST .st test file, repo-relative>  <family> the file exists and the family
#                                                                   is one of its check labels, whole:
#                                                                   the string of a `that: '...'` or a
#                                                                   `check value: '...'` (outside the
#                                                                   comments, '' read as '); never a
#                                                                   prefix, never comment text. A .sh
#                                                                   test (tests/cluster, real
#                                                                   processes) names its check labels
#                                                                   in lines `cluster_check '<label>'`
#                                                                   (_cluster.sh), each run once the
#                                                                   assertions of that check passed
#   deferred  <task number, 19..28, or a lettered task of that range, such as 22b, that the cluster
#              plan has as a '### Task <id>:' heading>  <reason>  Phase C ports it (the shell,
#                                                                   transport, storage, processes)
#   n/a       <tiered | DEPTH = 1 | Python-only API>  <reason>     it does not apply to the port
# Columns are tab-separated: proto_db file::function, status, then the two fields above. Blank
# lines and lines starting with '#' are comments. The check fails on a function without a row, a
# row for a function the tag does not have, a duplicate row, a malformed row, a missing file or a
# family that is not a whole check label of its file, and prints the counts, then the deferred
# rows grouped by task. With CHECKLIST_FINAL=1 (the final gate, plan Task 30) every deferred row
# is an error too. The functions are listed from the tag with git show (the protoBase checkout is
# only read). The parsing and the row rules are tests/lib/checklist_rows.sh, shared with
# queries_checklist.sh. Without a checkout at the default path, and none named, it is skipped (exit 77); a
# checkout named explicitly (PROTOBASE_REPO set by the caller: PROTOBASE_REPO_EXPLICIT=1 under
# tests/run_tests.sh, which always exports PROTOBASE_REPO, or PROTOBASE_REPO set when run directly)
# that is missing or lacks the tag, or one present at the default path that lacks the tag, is a
# failure, not a skip.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TAG=v2.0.0rc4
source "$REPO/tests/lib/checklist_rows.sh"
checklist_prepare

files="$(git -C "$PB" ls-tree --name-only "$TAG" tests/unit/ | grep -E '^tests/unit/test_cluster_[A-Za-z0-9_]*\.py$')"
[[ -n "$files" ]] || { echo "FAIL: no tests/unit/test_cluster_*.py at $TAG"; exit 1; }
checklist_list $files

checklist_run "$HERE/cluster_checklist.tsv" "$REPO/docs/superpowers/plans/2026-11-13-cluster-mode.md" 19 28 0 \
    "tiered|DEPTH = 1|Python-only API"

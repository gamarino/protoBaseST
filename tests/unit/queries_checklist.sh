#!/usr/bin/env bash
# The checklist of proto_db's index and query tests (spec 7.1): every test function of the files
# listed below, at the tag v2.0.0rc4, has one row in queries_checklist.tsv, and every row is one of:
#   ported    <protoBaseST .st test file, repo-relative>  <check label>   the file exists and the label
#                                                                is one of its check labels, whole
#                                                                (see tests/lib/checklist_rows.sh)
#   deferred  <task 1..10, or 4a / 4b>  <reason>   the task of the indexed-queries plan that ports it
#   n/a       <excluded: vector | deferred: cache | deferred: tokens | deferred: spec 3.2 | Python-only API>  <reason>
#                                                  it does not apply to the port
# Columns are tab-separated: proto_db file::function, status, then the two fields above. Blank
# lines and lines starting with '#' are comments. The rules (missing row, unknown row, duplicate,
# malformed, missing file, label not a whole check label, reasons of at least six words) and the
# output are those of cluster_checklist.sh: both run tests/lib/checklist_rows.sh. A deferred task
# must be one the plan has a '### Task <id>:' heading for. With CHECKLIST_FINAL=1 (the final gate,
# plan Task 10) every deferred row is an error too. The checkout is only read; without one at the
# default path, and none named, the check is skipped (exit 77); a named one that is missing or lacks
# the tag is a failure (as in cluster_checklist.sh).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TAG=v2.0.0rc4
source "$REPO/tests/lib/checklist_rows.sh"
checklist_prepare

checklist_list \
    tests/unit/test_equality_index.py tests/unit/test_range_index.py tests/unit/test_index_base.py \
    tests/unit/test_index_key_neutrality.py tests/unit/test_index_contract.py \
    tests/unit/test_keyspec.py tests/unit/test_terms.py tests/unit/test_expressions.py \
    tests/unit/test_planner.py tests/unit/test_query_plans.py tests/unit/test_linq.py \
    tests/unit/test_pager.py tests/unit/test_vector_index.py tests/unit/test_query_cache.py \
    tests/property/test_index_equals_scan.py tests/property/test_index_rank.py \
    tests/property/test_query_cache_soundness.py \
    tests/concurrency/test_index_weights_concurrency.py tests/concurrency/test_indexed_roots.py \
    tests/concurrency/test_pager_stability.py

checklist_run "$HERE/queries_checklist.tsv" "$REPO/docs/superpowers/plans/2026-11-18-indexed-queries.md" 1 10 1 \
    "excluded: vector|deferred: cache|deferred: tokens|deferred: spec 3.2|Python-only API"

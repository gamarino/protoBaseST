#!/usr/bin/env bash
# The checklist of proto_db's index and query tests (spec 7.1): every test function of the files
# listed below, at the tag v2.0.0rc4, has one row in queries_checklist.tsv, and every row is one of:
#   ported    <protoBaseST .st test file, repo-relative>  <check label>   the file exists and the label
#                                                                is one of its check labels, whole
#                                                                (see tests/lib/checklist_rows.sh)
#   deferred  <task 1..10, or 4a / 4b>  <reason>   the task of the indexed-queries plan that ports it
#   deferred  <V0..V10, V-pin, VP>  <reason>       the task of the vectors phase that ports it (Addendum
#                                                  V, section 5.4; the task names are the addendum's,
#                                                  read from the '### Task <n> (<name>):' headings of
#                                                  docs/superpowers/plans/2026-11-20-vectors.md)
#   n/a       <deferred: cache | deferred: tokens | deferred: spec 3.2 | Python-only API |
#              deviation: DV1 | deviation: DV4>  <reason>   it does not apply to the port (DV1: hnsw
#                                                  search refused; DV4: no derived-structure cache;
#                                                  Addendum V, section 4)
# Columns are tab-separated: proto_db file::function, status, then the two fields above. Blank
# lines and lines starting with '#' are comments. The rules (missing row, unknown row, duplicate,
# malformed, missing file, label not a whole check label, reasons of at least six words) and the
# output are those of cluster_checklist.sh: both run tests/lib/checklist_rows.sh. A deferred task
# must be one the plan has a '### Task <id>:' heading for. With CHECKLIST_FINAL=1 (the final gate,
# plan Task 10, and the vectors phase's V9) every deferred row is an error too.
# The vectors phase (Addendum V, section 5.4) adds the files with vector tests the list lacked; of
# three of them only the vector tests are in scope, so they are listed one function at a time
# (file::function). tests/unit/hnsw_checks.py, which the addendum also names, has no test function:
# its four checks run in child processes started by four test_vector_index.py tests, whose rows
# (n/a, DV1 and Python-only API) stand for them. The checkout is only read; without one at the
# default path, and none named, the check is skipped (exit 77); a named one that is missing or lacks
# the tag is a failure (as in cluster_checklist.sh). A .sh test names its check labels in lines
# `queries_check '<label>'`.
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
    tests/unit/test_plans.py::test_vector_search_wraps_the_index_plan \
    tests/unit/test_plans.py::test_filter_accepts_prefix_lists_and_rejects_near \
    tests/unit/test_format_neutral.py::test_vector_removal_is_exact_too \
    tests/unit/test_format_neutral.py::test_validate_accepts_a_vector_index_with_format_3_tokens \
    tests/unit/test_structure_depth.py::test_a_vector_index_store_key_adds_its_own_tuple \
    tests/property/test_index_equals_scan.py tests/property/test_index_rank.py \
    tests/property/test_query_cache_soundness.py \
    tests/concurrency/test_index_weights_concurrency.py tests/concurrency/test_indexed_roots.py \
    tests/concurrency/test_pager_stability.py

VECTOR_TASKS="$(sed -n -E 's/^### Task [0-9]+ \((V[-A-Za-z0-9]*)\).*/\1/p' \
    "$REPO/docs/superpowers/plans/2026-11-20-vectors.md" 2>/dev/null | tr '\n' ' ')"
[[ -n "$VECTOR_TASKS" ]] || { echo "FAIL: no '### Task <n> (V...)' heading in docs/superpowers/plans/2026-11-20-vectors.md"; exit 1; }
checklist_run "$HERE/queries_checklist.tsv" "$REPO/docs/superpowers/plans/2026-11-18-indexed-queries.md" 1 10 1 \
    "deferred: cache|deferred: tokens|deferred: spec 3.2|Python-only API|deviation: DV1|deviation: DV4" \
    queries_check "$VECTOR_TASKS"

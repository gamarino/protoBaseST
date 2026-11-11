# protoBaseST

A perennial object database for protoST, in the tradition GemStone opened.

protoBaseST is a Smalltalk implementation, on protoST, of ProtoBase (the Python package `proto_db`).
It reads and writes the same on-disk format (format 4, frozen at ProtoBase `v2.0.0rc1`), so one
database directory can be shared by Python and Smalltalk programs.

Status: proposal prototype for discussion at the FAST Smalltalk workshop (2026-12-03). Not a product.

Design: [docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md](docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md)

## Running the tests

The tests need a protoST binary 0.9.0 or newer (run from a protoST checkout on the branch that
provides `lib/decimal.st` and `lib/calendar.st`). Point `PROTOST` at it:

```sh
export PROTOST=../protoST/build_release/protost      # default: protost from PATH
tests/conformance/fetch_vectors.sh                    # vendors the format-4 vectors; run once, checks digests
PYTHON=python3.14 tests/interop/setup_venv.sh         # Python side of the interop tests (needs ../ProtoBase)
tests/run_tests.sh                                    # everything under tests/ and examples/
tests/run_tests.sh tests/unit tests/week0             # or chosen paths
```

The runner prints `PASS`, `FAIL` or `SKIP` per test and ends with `passed N, failed N, skipped N`.
A `.st` test starts with an `"EXPECT: <last line>"` or `"EXPECT-ERROR: <text>"` directive; a
`.sh` test passes with exit 0 and is skipped with exit 77. `PROTOBASE_REPO` (default `../ProtoBase`)
names the ProtoBase checkout used by the two setup scripts.

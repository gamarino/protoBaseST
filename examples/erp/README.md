# The ERP demo: Python and protoST on one database directory

protoBaseST is a Smalltalk (protoST) port of the Python object database
`proto_db`. Both read and write the same on-disk format, so the two languages can work on one directory. This demo is a small ERP, three
customers and 24 invoices, that passes through both of them. It is a proposal prototype, shown
to collect criticism, not a finished product.

## Run it

```bash
tests/interop/setup_venv.sh                 # once: the pinned `proto_db` and msgpack, in a venv
PROTOST=/path/to/protost examples/erp/run_demo.sh
```

The script creates a fresh temporary directory, runs the four steps on it, and compares what
both languages print with `expected_report.txt`. It prints `demo ok` on success. It is also
a test: `tests/run_tests.sh` runs it (and skips it, exit 77, when the venv is missing).

## The steps

| Step | Language | What it shows |
|---|---|---|
| `1_create.py` | Python | One commit creates three customers, each a *mutable cell* (`customer:acme`), 24 invoices that name their customer's cell, and an empty `tags` dictionary. The record types are in `erp_model.py`. |
| `2_payments.st` | protoST | `erp_model.st` declares the same types under the same names. A payment is a **new version** of the invoice, made with `with:value:`; nothing is changed in place. The customer ACME is renamed through its `PBMutableObject`, the one name that always means "the latest version". Two commits. |
| `3_tag.st` + `3_tag_peer.py` | both | protoST opens a transaction and tags invoice 1003; before it commits, a Python process tags invoice 1010 and commits. Neither side read `tags`, so both writes are **blind**: the second commit replays its operations onto the dictionary the first one left. Both tags survive and nobody retries. |
| `4_report.st` + `4_report.py` | both | The same **as-of report** for three moments. Each prints identical text. |

## The as-of report

Nothing is ever deleted, so every commit stays readable. The three moments are the
`committedAt` of the commits that steps 1 and 2 made (versions 1, 2 and 3), read from the
database's history, never from a clock. A small helper finds the newest version committed at or
before a moment, and the report reads only that snapshot:

```smalltalk
asOf := [:aMoment |
    | entry |
    entry := db history detect: [:each | each committedAt <= aMoment]
        ifNone: [PBUserError signal: 'the database did not exist yet'].
    db snapshotAt: entry].
```

(A script has no class to hold helpers, so they are blocks bound to temporaries.)

```python
def as_of(db, moment):
    entry = next((e for e in db.history() if e.committed_at <= moment), None)
    if entry is None:
        raise ValueError("the database did not exist yet")
    return db.snapshot_at(entry)
```

If two commits ever carried the same timestamp, the moment of the older one would resolve to
the newer version, which is the right as-of answer but would blur the demo. Both reports
therefore refuse to run unless the three moments are strictly increasing (the steps run as
separate processes, so they are), and they check that each moment found the version it names.

At moment 1 no invoice is paid; at moment 2 six are; at moment 3 ACME has its new name, while
the invoices still show the payments. The last line lists the tags as they are now.

## Running a step alone

`run_demo.sh` sets everything up. To run `3_tag.st` by itself, `STPATH` must contain
`<repo>/src` (the peer script is found from it, whatever the working directory), and `PY` should
name a Python that can import `proto_db` (the interop venv, `tests/interop/env.sh`; `python3`
when `PY` is unset). The other steps need only `STPATH` or `PYTHONPATH` and the directory
argument.

## API mapping

| Concept | `proto_db` (Python) | protoBaseST (protoST) |
|---|---|---|
| open | `ObjectSpace(FileStorage(dir)).open_database(name)` | `(PBObjectSpace storage: (PBFileStorage path: dir)) openDatabase: name` |
| transaction | `db.new_transaction()`, `db.run(fn)` | `db newTransaction`, `db newTransactionDo: [:tr | ...]`, `db run: [:tr | ...]` |
| new version of a record | `record.with_(paidOn=day)` | `record with: 'paidOn' value: day` |
| mutable cell | `MutableObject(name).set(tx, v)` | `(PBMutableObject name: n) set: tr value: v` |
| history, as of | `db.history()`, `db.snapshot_at(entry)` | `db history`, `db snapshotAt: entry` |
| blind write | `tx.new_dictionary().set_at(k, v)` | `tr newDictionary setAt: k value: v` |

## Notes

- `erp_model.py` and `erp_model.st` are the two halves of one declaration: each type has a
  language-neutral name (`demo.erp.Invoice`), and `isPaid` / `is_paid` is behaviour, never a
  stored attribute.
- The run is deterministic: no sleeps, no wall-clock readings. Step 3 orders its two commits
  by running Python's one-shot script while protoST's transaction is open.
- `check_guards.sh` (also run as a test) writes two spaces with scripted commit times and checks
  that both reports refuse them with their messages: two moments with the same `committedAt`,
  and a moment that resolves to a later version.

"""The transaction workload of tx_workload.st in ProtoBase (proto_db), on FileStorage.

Same profiles, same transactions, same output lines, same checksums; see tx_workload.st's header
for what each profile does. Every profile runs in a new directory under $TX_DIR, with the default
durability ("fsync", the only one protoBaseST has), and is verified after the space is closed and
reopened: a wrong count or checksum raises and the exit status is non-zero.

Output lines, tab-separated:
  op <profile> <transactions> <seconds> <retries> <checksum>
The last line is 'tx_workload ok'. Run with the interop venv (tests/interop/env.sh sets PY and
PYTHONPATH); run_tx.sh runs both implementations and prints the table.
"""
import os
import sys
import threading
import time

from proto_db import FileStorage, ObjectSpace

SCALE = int(os.environ.get("TX_SCALE", "1"))
BASE = os.environ["TX_DIR"]
TINY, SMALL, BATCH, CONC = 100 * SCALE, 100 * SCALE, 10 * SCALE, 120 * SCALE
RECORDS, BATCH_KEYS, RETRIES = 100, 100, 1000


def report(name, txns, seconds, retries, checksum, want):
    if checksum != want:
        raise SystemExit(f"{name}: checksum {checksum}, expected {want}")
    print(f"op\t{name}\t{txns}\t{seconds:.6f}\t{retries}\t{checksum}", flush=True)


def open_space(name):
    return ObjectSpace(FileStorage(os.path.join(BASE, name)))


def setup(name, roots):
    """A new space with database 'bench' whose roots are set by one untimed transaction."""
    space = open_space(name)
    db = space.new_database("bench")
    with db.new_transaction() as tr:
        for root, build in roots.items():
            tr.set_root_object(root, build(tr))
    return space, db


def dict_sum(d):
    """'<count>:<sum of key * value>' of a Dictionary with Integer keys and values."""
    n = s = 0
    for k, v in d.items():
        n += 1
        s += k * v
    return f"{n}:{s}"


def readback(name, fn):
    """fn(tr) on a new space over the profile's directory, after the writer's space closed."""
    space = open_space(name)
    try:
        return fn(space.open_database("bench").new_transaction())
    finally:
        space.close()


def timed_run(db, n, body):
    """Runs n transactions through db.run, body(tr, i) for i in 1..n; answers (seconds, retries)."""
    attempts = 0

    def tx(i):
        def fn(tr):
            nonlocal attempts
            attempts += 1
            body(tr, i)
        return fn
    t0 = time.perf_counter()
    for i in range(1, n + 1):
        db.run(tx(i))
    return time.perf_counter() - t0, attempts - n


def set_key(tr, root, key, value):
    tr.set_root_object(root, tr.get_root_object(root).set_at(key, value))


def tiny():
    space, db = setup("tiny", {"kv": lambda tr: tr.new_dictionary()})
    try:
        secs, retries = timed_run(db, TINY, lambda tr, i: set_key(tr, "kv", i, i % 1000))
    finally:
        space.close()
    want = f"{TINY}:{sum(i * (i % 1000) for i in range(1, TINY + 1))}"
    report("tiny", TINY, secs, retries, readback("tiny", lambda tr: dict_sum(tr.get_root_object("kv"))), want)
    if retries:
        raise SystemExit("tiny: a single writer retried")


def small_record():
    def records(tr):
        d = tr.new_dictionary()
        for r in range(RECORDS):
            d = d.set_at(r, tr.new_object(name=f"account {r}", balance=0, hits=0, stamp=0))
        return d

    def update(tr, i):
        recs = tr.get_root_object("records")
        rec = recs.get_at(i % RECORDS)
        rec = rec.with_(balance=rec.balance + i, hits=rec.hits + 1, stamp=i)
        tr.set_root_object("records", recs.set_at(i % RECORDS, rec))

    def check(tr):
        n = bal = hits = stamps = 0
        for _, rec in tr.get_root_object("records").items():
            n, bal, hits, stamps = n + 1, bal + rec.balance, hits + rec.hits, stamps + rec.stamp
        return f"{n}:{bal}:{hits}:{stamps}"
    space, db = setup("small", {"records": records})
    try:
        secs, retries = timed_run(db, SMALL, update)
    finally:
        space.close()
    # The last stamp of record r is the largest i <= SMALL with i mod RECORDS = r (0 if none).
    stamps = sum(max((i for i in range(1, SMALL + 1) if i % RECORDS == r), default=0) for r in range(RECORDS))
    want = f"{RECORDS}:{SMALL * (SMALL + 1) // 2}:{SMALL}:{stamps}"
    report("small-record", SMALL, secs, retries, readback("small", check), want)
    if retries:
        raise SystemExit("small-record: a single writer retried")


def batch():
    def insert(tr, i):
        d = tr.get_root_object("kv")
        for k in range((i - 1) * BATCH_KEYS + 1, i * BATCH_KEYS + 1):
            d = d.set_at(k, k % 97)
        tr.set_root_object("kv", d)
    space, db = setup("batch", {"kv": lambda tr: tr.new_dictionary()})
    try:
        secs, retries = timed_run(db, BATCH, insert)
    finally:
        space.close()
    n = BATCH * BATCH_KEYS
    want = f"{n}:{sum(k * (k % 97) for k in range(1, n + 1))}"
    report("batch-100", BATCH, secs, retries, readback("batch", lambda tr: dict_sum(tr.get_root_object("kv"))), want)
    if retries:
        raise SystemExit("batch-100: a single writer retried")


def concurrent(mode, writers):
    """writers threads share one Database and commit CONC tiny transactions in all (CONC / writers
    each). disjoint: writer w reads and writes its own root 'kv-w'. merge: every writer blindly
    writes a one-key Dictionary to the shared root 'shared' (merged at commit, never read).
    hot: every writer increments key 0 of the shared root 'hot' (read-modify-write, conflicts)."""
    each = CONC // writers
    name = f"{mode}-{writers}"
    roots = {"shared": lambda tr: tr.new_dictionary(),
             "hot": lambda tr: tr.new_dictionary().set_at(0, 0)}
    for w in range(writers):
        roots[f"kv-{w}"] = lambda tr: tr.new_dictionary()
    space, db = setup(name, roots)
    attempts = [0] * writers
    errors = []

    def writer(w):
        def body(tr, i):
            attempts[w] += 1
            key = w * each + i
            if mode == "disjoint":
                set_key(tr, f"kv-{w}", key, key % 1000)
            elif mode == "merge":
                tr.set_root_object("shared", tr.new_dictionary().set_at(key, key % 1000))
            else:
                set_key(tr, "hot", 0, tr.get_root_object("hot").get_at(0) + 1)
        try:
            for i in range(1, each + 1):
                db.run(lambda tr, i=i: body(tr, i), retries=RETRIES)
        except BaseException as e:      # reported by the main thread; the run fails
            errors.append(f"writer {w}: {e!r}")
    threads = [threading.Thread(target=writer, args=(w,)) for w in range(writers)]
    try:
        t0 = time.perf_counter()
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        secs = time.perf_counter() - t0
    finally:
        space.close()
    if errors:
        raise SystemExit(f"concurrent-{name}: " + "; ".join(errors))
    total = each * writers

    def check(tr):
        if mode == "disjoint":
            n = s = 0
            for w in range(writers):
                c, v = dict_sum(tr.get_root_object(f"kv-{w}")).split(":")
                n, s = n + int(c), s + int(v)
            return f"{n}:{s}"
        if mode == "merge":
            return dict_sum(tr.get_root_object("shared"))
        return f"1:{tr.get_root_object('hot').get_at(0)}"
    want = f"1:{total}" if mode == "hot" else f"{total}:{sum(k * (k % 1000) for k in range(1, total + 1))}"
    retries = sum(attempts) - total
    report(f"conc-{name}", total, secs, retries, readback(name, check), want)
    if mode != "hot":
        if retries:
            raise SystemExit(f"conc-{name}: disjoint writers retried")


def main():
    tiny()
    small_record()
    batch()
    for mode in ("disjoint", "merge", "hot"):
        for writers in (1, 2, 4):
            concurrent(mode, writers)
    print("tx_workload ok")


if __name__ == "__main__":
    sys.exit(main())

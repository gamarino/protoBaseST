"""The PBAvl workload of avl_workload.st in ProtoBase (proto_db.collections.avl).

Same operations, same output lines (op <name> <operations> <us per operation> <checksum>),
same checksums, verified here: a wrong result raises and the exit status is non-zero.
Run with the interop venv (tests/interop/env.sh sets PY and PYTHONPATH).
"""
import sys
import time

from proto_db.collections import avl


def report(name, ops, micros, checksum, want):
    if checksum != want:
        raise SystemExit(f"{name}: checksum {checksum}, expected {want}")
    print(f"op\t{name}\t{ops}\t{micros / ops}\t{checksum}")


def timed(fn):
    t0 = time.perf_counter()
    fn()
    return (time.perf_counter() - t0) * 1e6


def main():
    n, reps = 1000, 2000
    state = {"pos": None, "key": None, "sum": 0}

    def build_pos():
        for i in range(1, n + 1):
            state["pos"] = avl.pos_insert(state["pos"], avl.pos_count(state["pos"]), i * 10)
    report("posAppend", n, timed(build_pos), avl.pos_count(state["pos"]), n)

    def build_key():
        for i in range(1, n + 1):
            state["key"] = avl.key_put(state["key"], i, i * 10)[0]
    report("keyPut-new", n, timed(build_key), state["key"].count, n)

    expected = sum((i % n + 1) * 10 for i in range(1, reps + 1))

    def pos_at():
        s = 0
        for i in range(1, reps + 1):
            s += avl.pos_get(state["pos"], i % n)
        state["sum"] = s
    report("posAt", reps, timed(pos_at), state["sum"], expected)

    def key_at():
        s = 0
        for i in range(1, reps + 1):
            s += avl.key_get(state["key"], i % n + 1)
        state["sum"] = s
    report("keyAt", reps, timed(key_at), state["sum"], expected)

    def key_replace():
        s = 0
        for i in range(1, 501):
            root, replaced, old = avl.key_put(state["key"], i, i)
            if not replaced:
                raise SystemExit(f"keyPut-replace: key {i} was not replaced")
            s += old
        state["sum"] = s
    report("keyPut-replace", 500, timed(key_replace), state["sum"], sum(i * 10 for i in range(1, 501)))

    # check_invariants answers None: the in-order fold after it proves the walked tree.
    def check_pos():
        s = 0
        for _ in range(3):
            avl.check_invariants(state["pos"])
            for v in avl.pos_iter(state["pos"]):
                s += 1 + v
        state["sum"] = s
    report("check-pos", 3, timed(check_pos), state["sum"], 3 * (n + sum(i * 10 for i in range(1, n + 1))))

    def check_key():
        s = 0
        for _ in range(3):
            avl.check_invariants(state["key"])
            for k, v in avl.key_iter(state["key"]):
                s += 1 + k + v
        state["sum"] = s
    report("check-key", 3, timed(check_key), state["sum"], 3 * (n + sum(i + i * 10 for i in range(1, n + 1))))
    print("avl_workload ok")


if __name__ == "__main__":
    sys.exit(main())

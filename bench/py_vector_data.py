"""Write the data set of the vector benchmarks (Addendum V, 5.5) to a MessagePack file that both
bench/py_vector_workload.py and bench/vector_workload.st read: protoST cannot reproduce Python's
random.gauss cheaply, and both sides must score the same numbers.

Usage: python py_vector_data.py <n> <dim> <out file>

The data are proto_db's benchmark data set (benchmarks/workloads/vector.py:18-26 at v2.0.0rc4):
random.Random(51), `clusters` Gaussian centres (gauss(0, 1) per component), and each point a centre
drawn with randrange plus gauss(0, 0.35) per component; here clusters = 16 and QUERIES = 10 query
points follow the n vectors. The file is a msgpack map: 'n', 'dim', 'clusters', 'seed', 'vectors' (n
arrays of dim float64), 'query' (the first query point, one array of dim float64: VB0's) and
'queries' (the QUERIES points, VB1's and VB2's). It refuses to overwrite <out file>.
"""
import random
import sys
from pathlib import Path

import msgpack

SEED = 51
CLUSTERS = 16
QUERIES = 10


def dataset(n: int, dim: int, clusters: int = CLUSTERS, queries: int = 1, seed: int = SEED):
    """benchmarks/workloads/vector.py _dataset, verbatim."""
    rng = random.Random(seed)
    centres = [[rng.gauss(0, 1) for _ in range(dim)] for _ in range(clusters)]

    def point():
        c = centres[rng.randrange(clusters)]
        return tuple(x + rng.gauss(0, 0.35) for x in c)

    return [point() for _ in range(n)], [point() for _ in range(queries)]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    n, dim, out = int(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])
    if out.exists():
        sys.exit(f"py_vector_data: {out} exists")
    vectors, queries = dataset(n, dim, queries=QUERIES)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(msgpack.packb({"n": n, "dim": dim, "clusters": CLUSTERS, "seed": SEED,
                                   "vectors": [list(v) for v in vectors], "query": list(queries[0]),
                                   "queries": [list(q) for q in queries]},
                                  use_bin_type=True))


if __name__ == "__main__":
    main()

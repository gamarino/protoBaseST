"""Write the vector math vectors (Addendum V, task V1, section 5.2) with proto_db at v2.0.0rc4 and
the CPython that runs it.

Usage: python py_vector_math_cases.py <out directory>

<out> must not exist. The script writes <out>/cases.msgpack and <out>/manifest.sha256 (sha256sum's
format). It refuses to run unless the imported proto_db is the commit tests/interop/setup_venv.sh
pins, and it blocks numpy and hnswlib before importing proto_db (sys.modules[...] = None, the
mechanism of proto_db's own tests/unit/test_vector_index.py:523), so that proto_db's _kmeans takes
its pure-Python path whatever the venv can import; it checks that numpy_module() answers None. Run it
through the interop venv (tests/conformance/fetch_vector_math_vectors.sh does); the vendored copy is
tests/conformance/vectors-vector-math/, read by tests/conformance/vector_math.st.

Every expected result is computed by CPython or by proto_db's own functions
(proto_db/indexing/vector_backends.py: canonical_vector, exact_score, score_floor, rank_entries,
_sum_nonnegative, _kmeans, _training_order, _normalized, IvfFlatBackend.list_for), never by a
re-implementation. The inputs are seeded (SEED) and adversarial: near-cancelling sums, subnormals,
magnitudes near 1e+-300, Integers near 2^53, 2^64 and the Float range, Decimals with subnormal
half-way values and extreme exponents, the signalling NaN, odd 27-bit Integers whose squares are
exact half-way cases, ties.

cases.msgpack is a msgpack map:

  meta            a map: 'python' (sys.version), 'libc' (platform.libc_ver(), the libm whose pow
                  the '** 2' squares and the k-means use), 'numpy' ('blocked'), 'hnswlib'
                  ('blocked'), 'proto_db' (the commit), 'seed'
  float_of        [x, r]: r is float(x)
  canonical       [dim, key, r]: r is canonical_vector(key, dim)
  fsum            [terms, r]: r is math.fsum(terms) (terms are Floats)
  sum_nonnegative [terms, r]: r is _sum_nonnegative(terms)
  score           [metric, q, v, r]: r is exact_score(metric, q, v)
  score_floor     [metric, threshold, r]: r is score_floor(metric, threshold)
  rank            [entries, q, metric, k, threshold, r]: r is rank_entries(...) as [element, count]
                  pairs; an entry is [member key, element (a str), count, vector]
  squares         [x, pow, mul, overflow]: pow is libm pow(x, 2.0) (ctypes), equal to CPython's
                  x ** 2 whenever that does not raise; overflow is True when x ** 2 raised
                  OverflowError (CPython's float_pow on an infinite pow result); mul is x * x
  training_order  [vectors, order, bytes]: order is the 0-based permutation that sorts the vectors
                  by _training_order (a stable sort), bytes the _training_order of each vector
  normalized      [v, r]: r is _normalized(v)
  getrandbits     [seed, k, values]: values are the first draws of random.Random(seed).getrandbits(k)
  sample          [seed, n, k, r]: r is random.Random(seed).sample(range(n), k)
  kmeans          [vectors, nlist, iters, seed, r]: r is _kmeans(vectors, nlist, iters, seed), numpy
                  blocked (the pure-Python path); at least 8 cases (pow_witnesses) have centroids that
                  change when the square multiplies, so a port that squares with * fails them (the
                  script refuses to write otherwise)
  list_for        [metric, centroids, vector, r]: r is IvfFlatBackend().list_for of an index with
                  those centroids and metric (numpy blocked: every centroid is scored exactly)

Value encoding (msgpack has no 8-byte float bit-for-bit guarantee across decoders, no big Integers
and no Decimal): a number or key is a tagged array: ['f', <8 bytes, IEEE 754 binary64 big-endian>],
['i', <decimal text>], ['d', <str(Decimal)>], ['b', bool], ['s', str], ['n'] (None), ['t', [items]]
(a tuple), ['l', [items]] (a list). A result is ['f', bytes], ['n'] (None), ['v', [8-byte strings]] (a
tuple of floats), or ['e', <exception class name>, <message>]. Seeds, k, n and drawn values are
decimal texts (some exceed 64 bits).
"""
import ctypes
import ctypes.util
import hashlib
import math
import platform
import random
import struct
import sys
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

sys.modules["numpy"] = None
sys.modules["hnswlib"] = None

import msgpack  # noqa: E402

import proto_db  # noqa: E402
from proto_db.indexing import vector_backends as vb  # noqa: E402

TAG = "v2.0.0rc4"
SEED = 20261120
LIBM = ctypes.CDLL(ctypes.util.find_library("m"))
LIBM.pow.restype = ctypes.c_double
LIBM.pow.argtypes = [ctypes.c_double, ctypes.c_double]


def check_pinned() -> str:
    """Refuse to run unless the imported proto_db is the commit setup_venv.sh pins (TAG_COMMIT)."""
    setup = Path(__file__).resolve().parent / "setup_venv.sh"
    pinned = next((line.split('"')[1] for line in setup.read_text().splitlines()
                   if line.startswith('TAG_COMMIT="')), None)
    held_file = Path(proto_db.__file__).resolve().parent.parent / ".commit"
    held = held_file.read_text().strip() if held_file.exists() else None
    if not pinned or not held or not held.startswith(pinned):
        sys.exit(f"py_vector_math_cases: proto_db at {proto_db.__file__} is commit {held}, "
                 f"not the pinned {pinned} of setup_venv.sh ({TAG}); run it through the interop venv")
    if vb.numpy_module() is not None:
        sys.exit("py_vector_math_cases: numpy is importable although blocked; nothing written")
    return held


def fb(x: float) -> bytes:
    return struct.pack(">d", x)


def enc(x):
    """A number, key or element as a tagged array (module docstring)."""
    if isinstance(x, bool):
        return ["b", x]
    if isinstance(x, int):
        return ["i", str(x)]
    if isinstance(x, float):
        return ["f", fb(x)]
    if isinstance(x, Decimal):
        return ["d", str(x)]
    if isinstance(x, str):
        return ["s", x]
    if x is None:
        return ["n"]
    if isinstance(x, tuple):
        return ["t", [enc(i) for i in x]]
    if isinstance(x, list):
        return ["l", [enc(i) for i in x]]
    raise TypeError(f"cannot encode {x!r}")


def result(thunk):
    """The tagged result of thunk(), or the tagged exception it raised."""
    try:
        r = thunk()
    except (OverflowError, ValueError, ArithmeticError) as e:
        return ["e", type(e).__name__, str(e)]
    if r is None:
        return ["n"]
    if isinstance(r, float):
        return ["f", fb(r)]
    if isinstance(r, tuple):
        return ["v", [fb(x) for x in r]]
    raise TypeError(f"unexpected result {r!r}")


def floats(xs):
    return [fb(x) for x in xs]


# -- inputs -------------------------------------------------------------------------------------

def float_of_inputs(rng):
    xs = []
    for base in (2 ** 53, 2 ** 54, 2 ** 63, 2 ** 64, 2 ** 65, 2 ** 100):
        for d in range(-5, 6):
            xs += [base + d, -(base + d)]
    xs += [2 ** 1024 - 2 ** 970, 2 ** 1024 - 2 ** 970 - 1, 2 ** 1024 - 2 ** 971, 2 ** 1024, 10 ** 400,
           -(2 ** 1024 - 2 ** 971), -(2 ** 1024 - 2 ** 970), 0, -1, 1, 2 ** 55, 2 ** 55 + 1, -(2 ** 55) - 1]
    for _ in range(300):
        bits = rng.randrange(1, 1100)
        xs.append(rng.getrandbits(bits) * rng.choice((1, -1)))
    for _ in range(100):  # Integers that are half-way between two Floats, and one above or below
        m = rng.getrandbits(53) | (1 << 52)
        e = rng.randrange(1, 900)
        half = (2 * m + 1) << (e - 1)
        xs += [half, half + 1, half - 1, -half]
    # Decimals.
    ds = ["0", "-0", "0E-999999", "-0E+999999", "0E-1000000000", "-0E+999999999999", "NaN", "-NaN", "NaN123",
          "Infinity", "-Infinity", "1E-310", "2.5E-324", "2.4703282292062327E-324", "2.4703282292062328E-324",
          "1E-320", "1E+400", "-1E+400", "1E+308", "1.7976931348623157E+308", "1.7976931348623158E+308",
          "1.7976931348623159E+308", "4.9406564584124654E-324", "1E-999999", "-1E-999999", "1E+999999",
          "123", "-123", "1.20", "0.1", "-0.1", "1E-5", "123456789012345678901234567890",
          "9007199254740993", "9007199254740993.000000000000000000001", "-9007199254740993"]
    xs += [Decimal(t) for t in ds]
    # Exact half-way Decimals: between two subnormals ((2m + 1) * 2^-1075), between two normals,
    # and the largest finite Float's half-way neighbour (2^1024 - 2^970), each also nudged by a tiny
    # amount up and down (so the tie is broken).
    five = 5 ** 1075
    for m in list(range(0, 6)) + [rng.getrandbits(52) for _ in range(40)]:
        exact = (2 * m + 1) * five
        xs.append(Decimal(f"{exact}E-1075"))
        xs.append(Decimal(f"{exact * 10 + 1}E-1076"))
        xs.append(Decimal(f"{exact * 10 - 1}E-1076"))
        xs.append(Decimal(f"-{exact}E-1075"))
    for _ in range(30):
        m = rng.getrandbits(53) | (1 << 52)
        e = rng.randrange(-1070, -60)  # half-way at 2^(e-1) * (2m + 1), e - 1 >= -1074 - 53
        n = 1 - e
        exact = (2 * m + 1) * 5 ** n  # (2m + 1) * 2^(e-1) = (2m + 1) * 5^(1-e) * 10^(e-1)
        xs.append(Decimal(f"{exact}E{e - 1}"))
        xs.append(Decimal(f"{exact * 10 + 1}E{e - 2}"))
    xs.append(Decimal(2 ** 1024 - 2 ** 970))
    xs.append(Decimal(f"{(2 ** 1024 - 2 ** 970) * 10 - 1}E-1"))
    xs.append(Decimal(f"{(2 ** 1024 - 2 ** 970) * 10 + 1}E-1"))
    xs.append(Decimal(-(2 ** 1024 - 2 ** 970)))
    for _ in range(300):
        digits = rng.randrange(1, 40)
        coef = rng.randrange(10 ** (digits - 1), 10 ** digits)
        exp = rng.choice((rng.randrange(-360, -280), rng.randrange(280, 330), rng.randrange(-30, 30),
                          rng.randrange(-1100, -300)))
        xs.append(Decimal(f"{'-' if rng.random() < 0.3 else ''}{coef}E{exp}"))
    return xs


def canonical_inputs(rng):
    cases = [
        (2, (1.0, 0.0)), (2, [0.0, 1.0]), (2, None), (2, (1.0,)), (2, (1.0, float("nan"))),
        (2, (True, 0.0)), (2, (0.0, False)), (2, "ab"), (2, (1e200, 1e200)), (2, (float("inf"), 0.0)),
        (2, (float("-inf"), 0.0)), (2, (1, 2)), (2, (Decimal("1.5"), 2)), (2, (Decimal("NaN"), 0.0)),
        (2, (Decimal("Infinity"), 0.0)), (2, (Decimal("1E+400"), 0.0)), (2, (2 ** 1024, 0.0)),
        (2, (2 ** 1024 - 2 ** 971, 0.0)), (2, (10 ** 200, 10 ** 200)), (1, (1.3407807929942596e154,)),
        (1, (1.3407807929942597e154,)), (2, (Decimal("1E-400"), -0.0)), (3, (1, 2.5, Decimal("-3"))),
        (2, ("a", 1.0)), (2, (None, 1.0)), (2, ((1.0,), 1.0)), (0, ()), (0, []), (1, ()), (2, (1.0, 2.0, 3.0)),
        (2, (Decimal("sNaN"), 0.0)), (2, [Decimal("-sNaN12"), 1]), (2, (2 ** 64 + 1, -(2 ** 70))),
        (2, (5e-324, -5e-324)), (2, (1e-200, 1e-200)), (2, (Decimal("-0"), Decimal("0E-50"))),
    ]
    for _ in range(40):
        dim = rng.randrange(1, 9)
        kind = rng.random()
        items = []
        for _ in range(dim):
            r = rng.random()
            if r < 0.4:
                items.append(rng.uniform(-1e3, 1e3))
            elif r < 0.6:
                items.append(rng.randrange(-10 ** 6, 10 ** 6))
            elif r < 0.8:
                items.append(Decimal(f"{rng.randrange(-10 ** 9, 10 ** 9)}E{rng.randrange(-20, 5)}"))
            else:
                items.append(rng.choice((1e155, -1e155, 1e-160, 0.0, -0.0, 7)))
        cases.append((dim if kind < 0.9 else dim + 1, tuple(items) if kind < 0.5 else list(items)))
    return cases


def fsum_inputs(rng):
    out = [
        [], [0.0], [-0.0], [-0.0, -0.0], [0.0, -0.0],
        [1e100, 1.0, -1e100, 1e-100, 1e50, -1.0, -1e50],
        [2.0 ** 53, -0.5, -2.0 ** -54], [2.0 ** 53, 1.0, 2.0 ** -100], [2.0 ** 53 + 10.0, 1.0, 2.0 ** -100],
        [2.0 ** 53 - 4.0, 0.5, 2.0 ** -54], [1. / n for n in range(1, 1001)],
        [(-1.) ** n / n for n in range(1, 1001)], [1e16, 1., 1e-16],
        [1e16 - 2., 1. - 2. ** -53, -(1e16 - 2.), -(1. - 2. ** -53)],
        [2. ** n - 2. ** (n + 50) + 2. ** (n + 52) for n in range(-1074, 972, 2)] + [-2. ** 1022],
        [1e-16, 1.0, 1e16], [1e308, 1e308], [1e308, 1e308, -1e308], [1.7976931348623157e308, 9.979201547673598e291],
        [float("inf")], [float("-inf")], [float("inf"), float("inf")], [float("inf"), float("-inf")],
        [float("nan")], [1.0, float("nan"), float("inf")], [float("-inf"), 1e308, 1e308],
        [float("inf"), float("-inf"), float("nan")], [5e-324, 5e-324], [5e-324, -5e-324],
        [2.2250738585072014e-308, -2.225073858507201e-308], [1e300, 1e-300, -1e300],
        [1e308, -1e308, 1e308, 1e308],
    ]
    for _ in range(150):
        n = rng.randrange(1, 60)
        scale = rng.choice((1.0, 1e-300, 1e300, 1e150, 1e-160, 5e-324 * 2 ** 20))
        xs = [rng.uniform(-1, 1) * scale * 2.0 ** rng.randrange(-40, 40) for _ in range(n)]
        if rng.random() < 0.5:  # near-cancelling: every term and its negative, plus small residues
            xs = xs + [-x for x in xs] + [rng.uniform(-1, 1) * 2.0 ** rng.randrange(-1074, -1000) for _ in range(3)]
        if rng.random() < 0.3:
            xs += [rng.choice((1.0, -1.0)) * 2.0 ** rng.randrange(-60, 60) for _ in range(5)]
        rng.shuffle(xs)
        out.append(xs)
    for _ in range(80):  # half-way ties across partials
        a = float(rng.getrandbits(53) | (1 << 52)) * 2.0 ** rng.randrange(-30, 30)
        u = math.ulp(a)
        out.append([a, u / 2, rng.choice((1.0, -1.0)) * u * 2.0 ** -rng.randrange(20, 60)])
        out.append([a, -u / 2, u * 2.0 ** -rng.randrange(20, 60)])
        out.append([a, u / 2])
    return out


def nonnegative_inputs(rng):
    out = [[], [0.0], [1e308, 1e308], [1.7976931348623157e308, 1.0], [float("inf"), 1.0], [5e-324] * 7]
    for _ in range(60):
        out.append([abs(rng.uniform(-1, 1)) * 2.0 ** rng.randrange(-1074, 1020) for _ in range(rng.randrange(1, 30))])
    return out


def vector(rng, dim, style):
    if style == "uniform":
        return tuple(rng.uniform(-1.0, 1.0) for _ in range(dim))
    if style == "grid":
        return tuple(float(rng.randrange(-2, 3)) for _ in range(dim))
    if style == "big":
        return tuple(rng.uniform(-1.0, 1.0) * 1e150 for _ in range(dim))
    if style == "tiny":
        return tuple(rng.uniform(-1.0, 1.0) * 1e-160 for _ in range(dim))
    if style == "huge":
        return tuple(rng.uniform(-1.0, 1.0) * 1e300 for _ in range(dim))
    if style == "odd27":
        return tuple(float(rng.randrange(2 ** 26, 2 ** 27) | 1) * rng.choice((1, -1)) for _ in range(dim))
    raise ValueError(style)


STYLES = ("uniform", "grid", "big", "tiny", "huge", "odd27")


def score_inputs(rng):
    out = [("cosine", (0.0, 0.0), (1.0, 2.0)), ("cosine", (1.0, 0.0), (2.0, 0.0)), ("l2", (0.0, 0.0), (3.0, 4.0)),
           ("ip", (1.0, 2.0), (3.0, 4.0)), ("cosine", (1.0, 2.0), (0.0, -0.0)), ("ip", (1e300, 1e300), (1e300, 1e300)),
           ("ip", (1e200,), (1e200,)), ("cosine", (1e300, 1e300), (1e300, 1e300)), ("l2", (1e300,), (-1e300,)),
           ("l2", (1e200, 1e200), (-1e200, -1e200)), ("cosine", (5e-324,), (5e-324,)), ("ip", (-0.0,), (0.0,)),
           ("l2", (-0.0,), (0.0,)), ("cosine", (1e-200, 1e-200), (1e-200, -1e-200)),
           ("ip", (1e308, 1e308), (1.0, 1.0)), ("cosine", (1.3e154, 1.3e154), (1.0, 1.0)),
           ("cosine", (1.0, 1.0), (1e308, 1e308)), ("l2", (1e308, -1e308), (-1e308, 1e308))]
    for _ in range(400):
        dim = rng.randrange(1, 20)
        style = rng.choice(STYLES)
        out.append((rng.choice(vb.METRICS), vector(rng, dim, style), vector(rng, dim, style)))
    return out


def rank_inputs(rng):
    out = []
    for _ in range(60):
        dim = rng.randrange(1, 5)
        style = rng.choice(("uniform", "grid", "grid", "odd27"))
        n = rng.randrange(0, 25)
        keys = rng.sample(range(-50, 50), n)
        entries = []
        for i, key in enumerate(keys):
            kind = rng.random()
            mk = key if kind < 0.5 else (f"m{key}" if kind < 0.75 else (key % 5, f"x{key}"))
            entries.append((mk, f"e{i}", rng.randrange(1, 4), vector(rng, dim, style)))
        metric = rng.choice(vb.METRICS)
        k = rng.choice((None, 1, 3, 10, 100))
        threshold = None if rng.random() < 0.5 else {"cosine": rng.choice((-0.5, 0.0, 0.3, 0.9, 1.0)),
                                                      "l2": rng.choice((0.0, 0.5, 1.5, 3.0)),
                                                      "ip": rng.choice((-1.0, 0.0, 0.5, 2.0))}[metric]
        if k is None and threshold is None:
            k = 5
        out.append((entries, vector(rng, dim, style), metric, k, threshold))
    return out


def square_inputs(rng):
    xs = [0.0, -0.0, 1.0, -1.0, 130492547.0, -130492547.0, 1.3407807929942596e154, 1.3407807929942597e154,
          -1.3407807929942597e154, 1e154, 1.5e-154, 1e-162, 1e-170, 5e-324, -5e-324, 2.2250738585072014e-308,
          1.4916681462400413e-154, 1.0000000000000002, 1.7976931348623157e308]
    for _ in range(600):
        xs.append(float(rng.randrange(2 ** 26, 2 ** 27) | 1) * rng.choice((1, -1)))
    for _ in range(300):
        xs.append(rng.uniform(-1e3, 1e3))
    for _ in range(100):
        xs.append(rng.uniform(1e-170, 1.5e-154) * rng.choice((1, -1)))
    for _ in range(40):
        xs.append(rng.uniform(1.0e154, 1.4e154) * rng.choice((1, -1)))
    return xs


def kmeans_inputs(rng):
    out = []
    for _ in range(40):
        dim = rng.randrange(1, 6)
        n = rng.randrange(1, 60)
        style = rng.choice(("uniform", "grid", "odd27", "uniform", "clustered"))
        if style == "clustered":
            centres = [tuple(rng.gauss(0, 1) for _ in range(dim)) for _ in range(rng.randrange(1, 5))]
            vectors = [tuple(c + rng.gauss(0, 0.35) for c in rng.choice(centres)) for _ in range(n)]
        else:
            vectors = [vector(rng, dim, style) for _ in range(n)]
        if rng.random() < 0.3 and vectors:  # duplicates
            vectors += [vectors[0]] * rng.randrange(1, 4)
        nlist = rng.randrange(1, min(len(vectors), 9) + 1)
        out.append((vectors, nlist, rng.randrange(1, 11), rng.choice((0, 1, 7, 2 ** 32, rng.getrandbits(40)))))
    # a cluster that empties, and a large-magnitude set whose squares overflow
    out.append(([(0.0,), (0.0,), (10.0,), (10.0,), (10.0,)], 3, 3, 0))
    out.append(([(1e300, 1e300), (-1e300, -1e300), (1e300, -1e300), (0.0, 0.0)], 2, 3, 1))
    out += pow_witnesses(rng)
    return out


def kmeans_multiplying(vectors, nlist, iters, seed):
    """_kmeans with (a - b) * (a - b) in place of (a - b) ** 2: the wrong port the witnesses catch."""
    rng = random.Random(seed)
    centroids = [list(vectors[i]) for i in sorted(rng.sample(range(len(vectors)), nlist))]
    for _ in range(iters):
        sums = [[0.0] * len(vectors[0]) for _ in range(nlist)]
        counts = [0] * nlist
        for v in vectors:
            j = min(range(nlist), key=lambda c: (vb._sum_nonnegative((a - b) * (a - b) for a, b in zip(v, centroids[c])), c))
            counts[j] += 1
            sums[j] = [s + x for s, x in zip(sums[j], v)]
        centroids = [[s / counts[j] for s in sums[j]] if counts[j] else centroids[j] for j in range(nlist)]
    return centroids


def pow_witnesses(rng, wanted=8):
    """k-means inputs whose centroids differ when the square multiplies (2.5 step 3): the origin and
    two points (a, b), (c, d) of 27-bit coordinates with a^2 + b^2 = c^2 + d^2 exactly (Brahmagupta's
    identity), so that the two distances tie or not depending on how each square rounds; seed 0
    samples the two points as the initial centroids."""
    out = []
    lo, hi = int(2 ** 26.5) + 1, 2 ** 27
    while len(out) < wanted:
        m, p, q = (rng.randrange(9000, 11600) for _ in range(3))
        n = rng.randrange(1, 1900)
        a, b, c, d = m * p - n * q, m * q + n * p, m * p + n * q, abs(m * q - n * p)
        if not all(lo <= z < hi for z in (a, b, c, d)):
            continue
        vectors = [(0.0, 0.0), (float(a), float(b)), (float(c), float(d))]
        iters = 1 + len(out) % 3
        if vb._kmeans(vectors, 2, iters, 0) != kmeans_multiplying(vectors, 2, iters, 0):
            out.append((vectors, 2, iters, 0))
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    if out.exists():
        sys.exit(f"py_vector_math_cases: {out} exists")
    commit = check_pinned()
    rng = random.Random(SEED)
    data = {"meta": {"python": sys.version, "libc": " ".join(platform.libc_ver()), "numpy": "blocked",
                     "hnswlib": "blocked", "proto_db": commit, "seed": SEED}}

    data["float_of"] = [[enc(x), result(lambda x=x: float(x))] for x in float_of_inputs(rng)]
    data["canonical"] = [[dim, enc(key), result(lambda d=dim, k=key: vb.canonical_vector(k, d))]
                         for dim, key in canonical_inputs(rng)]
    data["fsum"] = [[floats(xs), result(lambda xs=xs: math.fsum(xs))] for xs in fsum_inputs(rng)]
    data["sum_nonnegative"] = [[floats(xs), result(lambda xs=xs: vb._sum_nonnegative(xs))]
                               for xs in nonnegative_inputs(rng)]
    data["score"] = [[m, floats(q), floats(v), result(lambda m=m, q=q, v=v: vb.exact_score(m, q, v))]
                     for m, q, v in score_inputs(rng)]
    data["score_floor"] = [[m, enc(t), result(lambda m=m, t=t: vb.score_floor(m, t))]
                           for m in vb.METRICS for t in (None, 0.0, -0.0, 1.5, -2.25, 1e300)]
    ranks = []
    for entries, q, metric, k, threshold in rank_inputs(rng):
        r = vb.rank_entries(entries, q, metric, k, threshold)
        ranks.append([[[enc(mk), e, c, floats(v)] for mk, e, c, v in entries], floats(q), metric,
                      None if k is None else k, enc(threshold), [[e, c] for e, c in r]])
    data["rank"] = ranks
    squares = []
    for x in square_inputs(rng):
        p = LIBM.pow(x, 2.0)
        try:
            py = x ** 2
            overflow = False
            if fb(py) != fb(p):
                sys.exit(f"py_vector_math_cases: x ** 2 and libm pow differ at {x!r}; nothing written")
        except OverflowError:
            overflow = True
            if not math.isinf(p):
                sys.exit(f"py_vector_math_cases: x ** 2 overflowed at {x!r} but pow answered {p!r}")
        squares.append([fb(x), fb(p), fb(x * x), overflow])
    data["squares"] = squares
    orders = []
    for _ in range(30):
        dim = rng.randrange(1, 4)
        vs = [vector(rng, dim, rng.choice(("grid", "uniform"))) for _ in range(rng.randrange(1, 20))]
        vs += [tuple(-0.0 if x == 0.0 else x for x in vs[0]), tuple(0.0 * abs(x) for x in vs[0])]
        order = sorted(range(len(vs)), key=lambda i, vs=vs: vb._training_order(vs[i]))
        orders.append([[floats(v) for v in vs], order, [vb._training_order(v) for v in vs]])
    data["training_order"] = orders
    data["normalized"] = [[floats(v), result(lambda v=v: vb._normalized(v))]
                          for v in [(0.0, 0.0), (-0.0,), (3.0, 4.0), (1e-200, 1e-200), (1e154, 1e154)]
                          + [vector(rng, rng.randrange(1, 9), rng.choice(STYLES[:4])) for _ in range(60)]]
    seeds = [0, 1, 7, 2 ** 32 - 1, 2 ** 32, 2 ** 40, 2 ** 64 + 3, 12345, 2 ** 100 + 2 ** 33 + 5]
    bits = []
    for seed in seeds:
        for k in (0, 1, 31, 32, 33, 64, 100):
            g = random.Random(seed)
            bits.append([str(seed), k, [str(g.getrandbits(k)) for _ in range(5)]])
    g = random.Random(5)
    bits.append(["5", 32, [str(g.getrandbits(32)) for _ in range(700)]])  # crosses a twist
    data["getrandbits"] = bits
    samples = []
    for seed in seeds:
        for n, k in ((1, 1), (5, 0), (5, 5), (21, 3), (22, 3), (85, 6), (86, 6), (100, 10), (1000, 10),
                     (2 ** 32 + 7, 4), (2 ** 33, 3), (60, 60), (341, 22), (342, 22),
                     (277, 22), (278, 22)):  # k = 22: setsize = 21 + 4 ** 4 = 277
            samples.append([str(seed), str(n), k, [str(j) for j in random.Random(seed).sample(range(n), k)]])
    data["sample"] = samples
    km = []
    pow_sensitive = 0
    for vectors, nlist, iters, seed in kmeans_inputs(rng):
        cents = vb._kmeans(vectors, nlist, iters, seed)
        pow_sensitive += cents != kmeans_multiplying(vectors, nlist, iters, seed)
        km.append([[floats(v) for v in vectors], nlist, iters, str(seed), [floats(c) for c in cents]])
    if pow_sensitive < 8:
        sys.exit(f"py_vector_math_cases: only {pow_sensitive} k-means cases tell ** 2 from *; nothing written")
    data["kmeans"] = km
    lf = []
    backend = vb.IvfFlatBackend()
    for _ in range(120):
        dim = rng.randrange(1, 5)
        style = rng.choice(("uniform", "grid", "odd27"))
        cents = tuple(vector(rng, dim, style) for _ in range(rng.randrange(1, 9)))
        if rng.random() < 0.3:
            cents = cents + (cents[0],)
        metric = rng.choice(vb.METRICS)
        index = SimpleNamespace(centroids=cents, metric=metric)
        v = vector(rng, dim, style)
        lf.append([metric, [floats(c) for c in cents], floats(v), backend.list_for(index, v)])
    data["list_for"] = lf

    out.mkdir(parents=True)
    blob = msgpack.packb(data, use_bin_type=True)
    (out / "cases.msgpack").write_bytes(blob)
    (out / "manifest.sha256").write_text(f"{hashlib.sha256(blob).hexdigest()}  cases.msgpack\n")
    counts = {k: len(v) for k, v in data.items() if k != "meta"}
    print(f"numpy: blocked; hnswlib: blocked; CPython {platform.python_version()}; "
          f"libc {' '.join(platform.libc_ver())}; proto_db {commit}")
    print(f"wrote {sum(counts.values())} cases to {out}: {counts}; "
          f"{pow_sensitive} k-means cases change if the square multiplies")


if __name__ == "__main__":
    main()

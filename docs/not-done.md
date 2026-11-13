# What is not done

The text for the "what is not done" slide, and its detail. protoBaseST is a proposal prototype.
It is shown to start a discussion and to collect criticism, so the list of what it does not do is
as important as the list of what it does. Everything here is either a stated non-goal of the
design (spec section 2) or a cut made while building, with its reason.

## The slide

- Not a product, not production ready, and not fast.
- What is shown: one directory, opened by Python and by protoST, gives the same answers in the
  scenarios tested (below). Nothing outside those scenarios is claimed.
- No cluster: no framed logs, no wire protocol, no leases. Mixed Python/protoST clusters wait for
  a protocol freeze.
- No cloud or tiered storage, no durability mode other than `fsync`, no Windows.
- No writes to indexed collections, no merges onto them, no index queries, no vector-index
  writes or training.
- No writes to `RepeatedKeysDictionary`.
- No IANA time zones: no wall-clock conversion; a fixed pinned list of zone keys.
- No per-database class registry and no symbol kind (`@sym`): both are additive format-5
  features.
- No group commit, no query planner or LINQ, no pagers, no `snapshot_ref` byte references, no
  residency.
- No rebuilding of format-3 indexes, no `validate()` or `rebuilt()` of misfiled format-3
  collections.
- No frozen instances: immutability is a convention, checked by a test, not enforced at run time.
- No business rules in the core: no constraints, schema checks or `ondelete` rules. Application
  classes keep them (the Odoo lesson).

## What was tested, and what was not

Tested, with the `proto_db` at `v2.0.0rc2` reference:

- the conformance vectors of the tag, for every layer protoBaseST implements (the cluster and
  framed-log vectors are visible skips; three differences are on purpose, see
  [deviations.md](deviations.md));
- both directions of the round trip: spaces written by `proto_db` are dumped identically by
  protoBaseST, and spaces written by protoBaseST pass `proto_db`'s verifier with an identical dump,
  including values at the integer boundaries, the boxing threshold by code points, and nesting at
  1022 and 1023 containers;
- tree shapes: 1000 seeded list operations, a larger dictionary replay, and multi-entry hash
  buckets are compared with `proto_db` node by node, byte for byte;
- concurrent commits from both languages in 27 scenarios, each run with both roles, plus the same
  table driven by two protoST actors, with `proto_db`'s recorded outcomes;
- crash states a writer can leave on disk, read by both languages, and the root lock excluded in
  both directions;
- the ERP demo, a clean-clone run included.

Not tested, or not proven:

- **Anything outside those scenarios.** No fuzzing of the codec against `proto_db` beyond the
  vectors, the seeded sequences and a few dozen hand-picked edge values.
- **Other `proto_db` releases.** The reference is `v2.0.0rc2`. A newer release may differ.
- **Speed.** The AVL workload is many times slower than `proto_db`'s. The dated figures, and how
  they were measured, are in [deviations.md](deviations.md#performance); they are indicative only.
- **Memory and long runs.** A segment rolls over at 256 MiB as `proto_db`'s does; nothing was run
  near that size.
- **Heavy contention.** The lock backoff blocks the caller's worker, see
  [deviations.md](deviations.md).
- **The whole thing is one implementer's work, reviewed task by task.** It has not had outside
  review. That is what the workshop is for.

## The cuts

| Item | State | Why | Cost |
|---|---|---|---|
| `CountedSet` | **Done** (ruling R22), first a stretch goal | Time allowed, and cutting it would have left `PBCountedSet` mutators refusing. | None. |
| Framed log reader (`PBFramedLog`) | Written, removed (ruling R14), **re-ported** with the linear search in cluster Task A1 (`cluster/log.st`) | The spec lists framed logs as a non-goal and nothing in protoBaseST reads them; an uncalled reader is debt. Its worst case was quadratic. | If cluster or tiered storage enters scope, the reader must be re-ported with `proto_db`'s linear prefix-checksum search. |
| `asOf:` | Not added | `proto_db` has none. | A three-line helper in each program. |
| Cluster held retries | Not ported | No cluster mode. | |
| Index maintenance | Not done | Out of scope (design 7.4). Refused explicitly rather than done partly. | A database with indexes can be read, not changed in its indexed collections. |

## What would come next, if the workshop wants it

In the order the cost of the omission is felt:

1. Index maintenance and merges onto indexed collections. Without them protoST cannot change an
   indexed collection, which limits the shared-directory story to databases without indexes.
2. The `@sym` kind, once format 5 defines it, with the explicit symbol wrapper in protoST.
3. A time-zone database in protoST, so zoned datetimes have a wall clock.
4. Speed of the record and node paths, which is protoST VM work more than library work.
5. The cluster, after the protocol is frozen.

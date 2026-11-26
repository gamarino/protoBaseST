# Proposal: the precondition concurrency model for protoBaseST

**Status: a proposal for discussion, no code.** Written 2026-11-26 for the FAST Smalltalk group,
ahead of the workshop of 2026-12-03. Nothing in protoBaseST changes with this document. It
presents a change that `proto_db` (the Python library protoBaseST ports) has made on the branch
to be released as 2.0.0rc5, explains what porting it would mean here, and asks the group the
questions that the port should not answer alone.

The normative text is `proto_db`'s specification,
`docs/superpowers/specs/2026-11-24-precondition-concurrency-model-design.md` in the protoBase
repository (rules P-A to P-G and R1 to R70, with the amendments of its sections 14 and 15), and
its reference page `docs/source/concurrency-model.rst`; the decision is D73 of `proto_db`'s
`docs/decisions.md`. Rule R62 of that specification is the reason this document exists: the port
to protoBaseST is deferred, and the model is first presented to the protoBaseST community for
feedback.

## Contents

1. [In one paragraph](#1-in-one-paragraph)
2. [The problem in protoBaseST today](#2-the-problem-in-protobasest-today)
3. [The model](#3-the-model)
4. [What `proto_db` shipped and what was verified](#4-what-proto_db-shipped-and-what-was-verified)
5. [What a protoBaseST port would touch](#5-what-a-protobasest-port-would-touch)
6. [The format-7 consequence](#6-the-format-7-consequence)
7. [The cross-runtime contract: the conformance scenarios](#7-the-cross-runtime-contract-the-conformance-scenarios)
8. [Open questions for the group](#8-open-questions-for-the-group)
9. [References](#9-references)

## 1. In one paragraph

Today a protoBaseST transaction conflicts **per named root**: reading a root remembers a token of
the whole value, and the commit refuses the transaction if that token changed. The new model
makes every operation record, as data, what it saw of its base (a **precondition**) and what it
wants to change (an **intention**), over a fine **unit**: a dictionary key, a set element, a list
position, a mutable cell, a root, a whole collection. At commit every precondition must still
hold against the current state; if they all do, the intentions are reapplied on that state, and
if any fails nothing is published. Committed transactions are serializable in commit order, and
nothing but engine code and format comparisons runs while the space root is held.

For a Smalltalk audience the closest picture is the one GemStone opened: optimistic transactions
over a persistent object graph, with conflicts detected at commit. As we understand it, GemStone
detects conflicts per object and offers reduced-conflict classes (`RcCounter`, `RcIdentityBag`,
`RcKeyValueDictionary`, `RcQueue`) for hot shared collections. GemStone also offers explicit
object locks for the cases where optimism does not fit; the model here keeps locks out of its core
(P-D), and they can be built on top as lock cells (the specification's section 13). The model proposed here reaches a
similar effect by a different route: there is no special class to choose; the unit follows from
the **operation** the program sent (`setAt:value:` on a key, `add:` of an element), and an operation
the engine cannot prove safe falls back to the whole collection. We would value the group's
correction of this comparison, which we hold loosely.

## 2. The problem in protoBaseST today

protoBaseST ports `proto_db` at v2.0.0rc4, and so it has the three mechanisms that `proto_db`
replaced. They are already documented here as deviations or costs.

**Collections conflict as a whole.** `PBTransaction >> readSet` is "root name -> token"
(`src/protobase/transactions.st`, the class comment). A transaction that reads a `PBDictionary`
root in order to change one key holds the whole dictionary in its read set, so two transactions
that change different keys conflict, and a hot collection serializes every writer.

**A merge of blind writes, conditional on a runtime state.** To let writers of different keys
coexist, a collection that is written *without being read* is merged by replaying its log:
`_merged:onto:` in `transactions.st`, with `opLog`, `isMergeable` and `rebaseOnto:` in
`collections.st`. It applies only when the collection's log is complete, a property of how the
value was built (a `newDictionary` built in this process merges; a version read and changed does
not), and which the caller cannot see. `docs/deviations.md` lines 103-121 describe the indexed
case: the index definitions are logged so that "a blind write onto an indexed current merges as
in `proto_db`" (row 13 of `tests/interop/concurrency.sh`). The same `setRootObject:value:` merges
or replaces depending on that state.

**Blind writes lose updates.** A root written without a prior read, when it is not mergeable, is
stored as written; a blind `setMutable:value:` checks only that the cell still exists
(`transactions.st`: "without an earlier write of n it is blind: n must exist at commit"). In both
cases the last writer wins.

**Application code runs inside the commit.** Because a merge replays intents through the current
version's mutators, the current version's **extractors** run during the commit's build, in the
publisher under the root lock (standalone) or in the cluster round's build:

- `docs/deviations.md:116` records the cost: "a merge onto an indexed current runs the index work
  and the extractors in the commit's build, at protoBaseST's index speed";
- `docs/deviations.md:189` records the consequence for group commit: an extractor's exception is
  a build error of that commit alone, reaching the caller as a copy;
- `docs/deviations.md:990` ("Worth knowing") records that an extractor's exception fails only its
  own commit, in a cluster round too, where `proto_db` rc4 fails the whole round: in the cluster
  case a deviation by the maintainer's decision of 2026-11-19;
- `src/protobase/publisher.st` says it plainly: "An extractor must be pure and quick: a slow one
  delays the round, under the root lock."

Three mechanisms (the per-root read set, the log merge, and, in `proto_db`, an intents mode that
protoBaseST never ported) coexist without one definition of conflict. `proto_db` replaced all of
them with one model; protoBaseST would follow.

## 3. The model

This section summarises; the specification is the reference, and its rule numbers are cited.

### 3.1 Definitions

- **Base**: the database version in force when the transaction opened. It never changes.
- **Current**: the version the commit is built on (the last published one or, inside a
  group-commit round, the one the previous commit of the round produced).
- **Unit**: the portion of state a precondition protects: a dictionary key, a set element, a
  counted element, a list position, a mutable cell, a root, a whole collection, an index group,
  a key range. **Absent** is a value of every unit; creating is going from absent to a value.
- **Precondition**: "this unit holds, at commit, the value it held in the base".
- **Intention**: "this unit becomes this value", or a composable adjustment (a counter).

### 3.2 The principles that decide every doubtful case

- **P-A, coarser when in doubt.** An operation whose fine unit is not proven safe takes a coarser
  one, in the end the whole collection. An extra conflict is acceptable; a result that no serial
  execution would produce is not.
- **P-B, a closed list.** Only the operations listed in the tables below are fine-grained. Any
  other write, and any other read, takes the whole collection.
- **P-C, only engine code under the root.** Preconditions and intentions are canonical values,
  compared with the format's comparisons (`exactToken:`, the order key), identical in Python and
  Smalltalk. No extractor, key block, computed attribute or user callback runs while the space
  root is held. This is what lets two implementations decide alike.
- **P-D, optimistic core.** Reading neither blocks nor reserves. The only point of exclusion is
  the publication of the space root.
- **P-E, reading is declaring.** What a transaction read is taken as necessary for its logic and
  must be unchanged at publication. A program should not read what its logic does not need.
- **P-F, all or nothing.** Every precondition is validated before any intention is applied.
- **P-G, no change to the persisted format** beyond the version mark (section 6) and an index's
  uniqueness attribute.

The comparison rules: values compare by **exact token** (`1` becoming `1.0` is a change; an atom
by its storage pointer, never loaded; R6); **ABA by value**, no version numbers (R7); the expected
value is always the base's (R8); **one record per unit**: the first operation that observes a
unit records its precondition, and an operation on a unit the transaction already wrote reads its
own value and adds none (R9).

### 3.3 Which unit a root has

- An **object root** (a record, a number, a string, a tuple) has the **whole value** as its unit
  (R2). Two transactions that change different instance variables of one record conflict; there
  is no per-attribute merge.
- A **collection root** (`PBDictionary`, `PBHashDictionary`, `PBSet`, `PBCountedSet`,
  `PBRepeatedKeysDictionary`, `PBList`) has units that depend on the operation.
- A **mutable cell** (`PBMutableObject`) is its own unit, in a namespace of its own; different
  cells never conflict (R3).
- **One level only** (R5): fine grain applies to the collection that is the direct value of a
  root. A collection inside a record, a cell or another collection is part of the unit that
  contains it.

In Smalltalk terms, `aTransaction getRootObject: 'customers'` on a collection root would answer a
**linked** copy: the transaction's own instance, which records its reads and whose derived
versions carry their intentions. Only a version assigned back with
`setRootObject: 'customers' value:` in the same transaction publishes them (R40-R47). A collection
built separately (`newDictionary`), taken from another root, another transaction or a snapshot, is
not linked: assigning it replaces the root, compared against the base value.

### 3.4 Writes

| Operation | Precondition | Intention |
| --- | --- | --- |
| `setRootObject:value:`, value not linked | root holds its base value (absent included) | root holds the value |
| `removeRootObject:` | root holds its base value | root absent |
| `newMutable:value:` | cell absent | cell holds the value |
| `setMutable:value:`, `removeMutable:` | cell holds its base value | cell holds the value / absent |
| Dictionary, HashDictionary `setAt:value:` / `removeAt:` | key holds its base value, absent included | key holds the value / absent |
| Set `add:` | none: every serial order leaves it present | element present |
| Set `remove:` | element still present (or still absent, when absent in the base) | element absent |
| Set union / difference | one `add:` / `remove:` per element | |
| Set intersection | whole collection | |
| CountedSet and RepeatedKeysDictionary counts | none: counts compose per element (`c -> max(c - removes, 0) + adds`, D26) | one adjustment per element or key |
| List `appendLast:`, `extend:` | none | appended, in commit order |
| List `setAt:value:` of a base position | position exists and holds its base value | position holds the value |
| List insertions, removals, `appendFirst:`, a position the transaction appended, a negative position | whole collection | |
| `addIndex:`, `removeIndex:` | whole collection, with a catch-up (below) | |
| any other mutator | whole collection | |

A blind write is compared too: a blind `setMutable:value:` over a concurrent change conflicts, and
so does removing a cell another transaction removed. That is the end of "the last writer wins".

Two amendments found during the implementation are worth naming, because they are the kind of
case a reviewer would ask about (spec section 15):

- **A position the transaction appended is read through the length** (A-1). Folding it, as R9
  first suggested, is not serializable: base `#(1 2 3)`; A appends 7 and sets position 3 (0-based)
  to 8; B appends 9 and commits first; the fold publishes `#(1 2 3 9 8)`, which neither serial
  order gives. The randomized checker found it.
- **Indexed counters do not compose on the element they remove** (A-3). On an indexed collection a
  concurrent commit may have replaced a stored member by an equal one of another exact form (`10`
  by `10.0`) whose index key was never computed, and P-C forbids computing it under the lock. So
  such a removal records its element or key, and two of them on the same element conflict.

### 3.5 Reads

| Read | Precondition recorded |
| --- | --- |
| `getRootObject:` of an absent root | still absent |
| `getRootObject:` of an object root | holds its base value |
| `getRootObject:` of a collection root | still present and of the same class; content not recorded |
| `rootNames`, `mutableNames` | the set of names unchanged (today they record nothing) |
| `getMutable:` | cell holds its base value, absent included |
| Dictionary, HashDictionary `getAt:`, `has:` | that key unchanged |
| Set `has:` | presence or absence unchanged |
| CountedSet `has:`, `countOf:` | that count unchanged |
| RepeatedKeysDictionary `getAt:`, `has:` | the set of records of that key unchanged |
| List `getAt:` of a base position | that position unchanged |
| `indexNames` | the set of index definitions unchanged |
| `getIndex:` | whole collection, and the index definitions |
| a query answered by an equality-index lookup | the group of that key unchanged |
| a query answered by a range-index scan, a window of dictionary keys | no key inside the range changed (a range, R67-R68) |
| `size`, `count`, iteration (`do:`), `keys`, an unindexed query, a vector search, a pager | whole collection |

What is reachable from a value read through a recorded read needs no further record: values are
immutable (R20). The exception is a `PBMutableObject`, whose resolution is a `getMutable:`. A
`snapshotAt:` is the deliberate escape: what it reads is outside the guarantee, the analogue of a
relational READ COMMITTED (R21).

### 3.6 Indexes: no extractor under the root

This is the part that changes protoBaseST's deviations most. In a **preparation phase**, before
the commit takes the space root, the key of every element a transaction adds, removes or replaces
is computed with the extractors of the base collection's indexes (R24). The keys travel with the
intentions as data, and under the root the indexes are updated from those keys alone. Consequences:

- every transaction with intentions on an indexed collection declares that the set of index
  definitions is unchanged (R25);
- an extractor must be pure: one that reads through a transaction fails with `PBUserError` (R27);
- `PBEqualityIndex` may be declared **unique** (R29), a persisted attribute; a concurrent
  duplicate is a conflict on that key's group, whose retry fails with a validation error;
- an IVF-Flat vector index cannot be maintained from precomputed keys (its lists depend on the
  whole collection), so every write to a collection holding one takes the whole collection (R30);
- `addIndex:` takes the whole collection, so on a busy collection it would never commit; a
  **catch-up** in the pre-pass applies the changed elements to the index under construction
  (extractors run there, outside the lock), at most three rounds (R69).

### 3.7 The commit protocol

1. **Close.** A transaction without intentions ends without publishing; a read-only transaction
   never fails with a conflict (R23).
2. **Preparation, without the space root.** One record per unit; the index keys; the catch-up;
   every atom reachable from the written values is saved (the storage is append-only, so
   unpublished records are harmless).
3. **Pre-pass, without the space root.** Read the last published root R0; validate every
   precondition against it (a failure is a conflict without ever taking the lock); reapply the
   intentions on R0 and keep the result as the **candidate** (R64).
4. **Publication, with the space root held** (the root lock; in a cluster, the write permission).
   Read the current root R1. If R1 is R0 by pointer, build on the candidate: no validation, no
   reapplication. Otherwise validate the **delta**: a structural diff of the persistent trees from
   R0 to R1, skipping every pair of subtrees with the same pointer, fails if a changed unit is
   covered by a recorded precondition or range (R65); then reapply on R1. The cost under the lock
   is O(changes since R0 x log n), independent of the size of the read set.
5. **Publish** by the epoch compare-and-swap, with the outcome rules of today (an unknown outcome
   is reported as such, never guessed).

Group commit is kept: inside a round each commit is built on the previous one's result, and the
candidate serves any entry whose current root is still its R0 by pointer (A-6). A transaction
records at most 1024 fine preconditions per collection root; the next one escalates them to the
whole collection (R66).

### 3.8 What the model leaves to the program

Hot units (N writers of one key: one commits per attempt), traversals that then write, no fairness
among retries, one ordering point per space, coarser behaviour on indexed collections. None of
them can produce a result no serial order produces; each costs conflicts or throughput. A block
given to `run:` may run several times, so its external effects belong after it returns.

## 4. What `proto_db` shipped and what was verified

The model is implemented on the `proto_db` branch to be released as 2.0.0rc5 (its CHANGELOG
section [Unreleased], decision D73). At the time of writing it is not released.

**What was verified is correctness:**

- a **serializability checker** (`tests/concurrency/test_serializability.py`): threads of randomly
  generated transactions over the closed set of operations; the committed ones are re-run serially
  in commit order on an in-memory model, and every read and the final state must match. It found
  amendment A-1 above;
- **full-versus-delta equivalence runs**: the delta validation of step 4 checked against a full
  re-validation, 11,492 delta checks with 0 mismatches (ten runs of the checker, during the
  implementation);
- **86 conformance scenarios** (`tests/conformance/concurrency_scenarios.json`, section 7), run in
  standalone mode, with group commit and in a cluster;
- the whole `proto_db` suite, 8394 passing tests.

**What was not measured: performance.** No benchmark was run under the new model.
`docs/source/performance.rst` in `proto_db` says so explicitly: none of its figures measures the
precondition model, and whether the model makes any of them better or worse is open. We give no
throughput or latency claim here, and a port would not inherit one.

## 5. What a protoBaseST port would touch

The port would follow the specification's section 11 (R56-R61), deferred by R62. The files:

| File | Today | After the port |
| --- | --- | --- |
| `src/protobase/transactions.st` | `PBTxState` with `reads`, `writes`, `replaced`, `mreads`, `mwrites`, `mexpected`; `_merged:onto:`; `_buildOn:` compares read tokens per root | a precondition record per unit and the intentions per assigned version; `_buildOn:` validates the delta and reapplies; `replace:` disappears; `rootNames` and `mutableNames` record |
| `src/protobase/collections.st` | `opLog`, `isMergeable`, `rebaseOnto:`, `consumed` | linked versions carrying reads (per transaction) and intentions (per version); reapplication on the current collection with precomputed keys; `isMergeable` and the complete-log notion retired |
| `src/protobase/indexes.st` | index maintenance through the mutators, extractors called in the merge | maintenance from precomputed keys; `unique` on `PBEqualityIndex`; the group and range preconditions; the catch-up of `addIndex:` |
| `src/protobase/keygroups.st` | member keys and group operations | the units of an equality group and the bounds of a range precondition, compared by order key |
| `src/protobase/vectors.st` | exact, IVF and hnsw maintenance | exact and hnsw from the precomputed vector; IVF takes the whole collection |
| `src/protobase/avl.st` | keyed and positional trees with counts | positional access on keyed trees (`keyAtPosition:`, `positionOf:`, from the node counts) and the structural diff of two trees that skips shared subtrees |
| `src/protobase/round.st` | the round runner actor saves each entry's atoms and hands the queue to `PBPublisher >> publishGroup:` | the preparation and the pre-pass run **in the caller**, before `enqueue:`; the runner keeps only step 4 |
| `src/protobase/cluster/` | the round's build (`PBBuild`, on the runner) | validation and reapplication on the building node under its write permission (R38), protocol 16 |

The point about `round.st` deserves a sentence of its own. In protoBaseST every commit is a
`PBCommitEntry` queued on the space's `PBRoundRunner`, an actor, and the build runs there. In
`proto_db` each thread prepares and runs its pre-pass before it joins the group. The natural port
puts the preparation (index keys, extractors, the saving of atoms) and the pre-pass in the caller's
actor, so the runner, which serializes the space, runs only engine code and never an extractor.
That moves today's saving of each entry's atoms out of the runner as well. Question 8.1 asks
whether that is the right place.

**Deviations that would be retired** (R58): the blind-write merge (`docs/deviations.md:103-121`),
the extractor's cost inside the commit (`:116`), the extractor's exception as a build error
(`:189`), and the "Worth knowing" note with the cluster deviation of 2026-11-19 (`:990`): with no
extractor under the root, none of them has a subject.

**Deviations that would stay** (R58): `PBRepeatedKeysDictionary` stays read-only, and the
execution of hnsw plans stays unsupported.

## 6. The format-7 consequence

`proto_db` marks a space operated under the model: **every root record it publishes is version 7**
(feature `preconditions`), whatever the data reachable from it (R63). No record byte changes
(segments keep the lowest sufficient version), but a reader of version 6 or lower refuses a
version-7 root, because a writer without the model would apply "the last writer wins" and break
the guarantee for every other writer. The upgrade is one-way: the first rc5 commit to a space of
version 2 to 6 opens it without migration and marks it.

protoBaseST reads formats 2 to 4, writes 4, and refuses 5 (the runtime registry, D62) with
`PBNotSupportedError` (`docs/deviations.md`, "Format 5 is refused"). Therefore:

- **the shared directory ends at rc4.** Once a `proto_db` rc5 process commits to a space, protoBaseST
  can no longer open it. The polyglot demonstration (one directory, two languages) holds only with
  `proto_db` up to rc4 until the port;
- **reading a version-7 space needs formats 5 to 7**, because the format's rule is that a reader of
  version *n* reads every version up to *n*: the runtime registry (format 5, `parents` and
  `registry`), the semantic catalog's eleven built-in types (format 6, aliases 24 to 34) and the
  root mark (format 7);
- **writing one needs the model**, by R59: a protoBaseST version without it must not be able to
  write a marked space;
- **a cluster needs protocol 16** (protoBaseST speaks 14; `proto_db` went to 15 with the catalog and
  to 16 with the model), since every node must validate the same way.

## 7. The cross-runtime contract: the conformance scenarios

`proto_db` added `tests/conformance/concurrency_scenarios.json` (R60): **data only**, 86 scenarios,
no Python in them. Each one has a base state, the operations of transaction A and of transaction B
(both opened on the base), the commit order, and the expected result: the final state, or the
unit on which the second commit raises a conflict. States are compared as exact JSON text, so `10`
and `10.0` are two forms. Each scenario names the row of the specification's tables it covers. A
sample:

```json
{ "name": "set_root_other_root_composes", "row": "5.roots.set_root_object",
  "base": { "roots": { "o": { "value": 1 }, "p": { "value": 1 } } },
  "a": [ ["set_root", "o", { "value": 2 }] ],
  "b": [ ["set_root", "p", { "value": 3 }] ],
  "order": ["b", "a"],
  "expect": { "state": { "roots": { "o": { "value": 2 }, "p": { "value": 3 } }, "mutables": {} } } }
```

A port would run the same file through protoBaseST in standalone mode, with group commit and in a
cluster, as `proto_db` does, and both implementations must agree. That file, not prose, is the
contract between the two runtimes, in the same way the format's conformance vectors are today. The
crossed interoperability cases of R61 (one transaction in Python, the other in Smalltalk, on one
space, per unit class) would extend `tests/interop/concurrency.sh` after the port.

## 8. Open questions for the group

These are questions we do not want to settle without the group. Each has a default we would take
if nobody objects; the default is stated so that it can be argued with.

**8.1 Where should the pre-pass run relative to the round-runner actor?** The default is the
caller's actor, before `enqueue:` (section 5), so that extractors and saves never run on the actor
that serializes the space. The cost is that a commit's preparation competes with the caller's own
work, and that a pre-pass may be stale by the time the runner reaches the entry (then the runner
diffs, as designed). An alternative is a pool of preparation actors in front of the runner. Is
there experience in the group, from GemStone or elsewhere, on where commit preparation should
live when the commit point is a single serializing process?

**8.2 How should extractor purity be expressed in Smalltalk?** In `proto_db` an extractor that
reads through a transaction fails at run time; purity beyond that is a documented contract. In
protoBaseST an extractor is a block registered by name (`PBKeySpec registerExtractor:block:version:`),
and a block can reach any global. Should protoBaseST rely on the run-time check only, or ask
protoST for something stronger, for example an extractor compiled in a restricted mode, or
declared as a method of a value class (8.3)? What would the group accept as "pure" in a
Smalltalk where every object can be sent any message?

**8.3 Should stored records become protoST value classes?** protoST's explicit-state
specification (a draft for review whose scope the maintainer approved on 2026-11-19; value
classes are planned for protoST 0.18.0) gives classes whose instances' fields can never be
rebound: a write signals `ModificationForbidden` (the spec's section 5.6). That immutability is
shallow: a field may still refer to a mutable object, and a value immutable all the way down is
the recommended form, not a checked one. protoBaseST's records are immutable by convention only
(decision 3). The model relies on values being immutable (R20: what is reachable from a read
value needs no further record). Value classes would enforce the first level of that, and
protoBaseST could check the rest when a record is stored; they would also give extractors a
natural pure home. Is that worth making protoBaseST depend on 0.18.0,
and does it read as a gain or as a constraint to a Smalltalk programmer used to mutable domain
objects?

**8.4 In what order should formats 5 to 7 be read?** Reading a version-7 space needs formats 5
and 6 (section 6). Options: (a) port the runtime registry (format 5, already planned as its own
work in `docs/not-done.md`) and the catalog types (format 6) first, then the model and the mark;
(b) port the model first and accept version-7 roots while refusing format-5 and format-6 records
precisely, per record, so plain-data spaces open early; (c) do both in one release. (b) gives the
polyglot demonstration back soonest but adds a partial reader the format's rule does not describe.
Which would the group trust more?

**8.5 Is the closed list the right shape for Smalltalk collections?** The fine-grained operations
are a closed list (P-B) under `proto_db`'s names, mapped to protoBaseST's selectors. A Smalltalk
programmer will expect `at:ifAbsentPut:`, `removeKey:ifAbsent:`, `addAll:`, `detect:`, and
subclasses of the collections. The model says that anything unlisted takes the whole collection and
that a subclass overriding an operation the model relies on is treated as an object root. Is that
acceptable, or should the selectors a Smalltalk programmer reaches for first be given their own
rows (in `proto_db` too, through the shared scenarios)?

**8.6 Should a conflict's unit be a first-class object for the program?** `proto_db`'s
`ProtoConflictError` carries the unit (kind, root, key, index). In Smalltalk the natural design is
an exception whose `unit` answers an object the handler can inspect and perhaps `retry` with
knowledge of. Is anything beyond reporting the unit useful in practice, for example a hook that
lets the program re-derive only the affected part, or does that invite code under the retry that
defeats P-E?

**8.7 Is "the last writer wins" missed anywhere?** The model removes it entirely, including for
blind writes of cells. Programs that used a cell as a "latest value" register will now conflict.
Are there Smalltalk persistence idioms in the group's experience (caches, session state, counters)
that relied on the last writer winning and would need a documented replacement, such as a cell per
writer?

## 9. References

In the protoBase repository (`proto_db`), on the branch to be released as 2.0.0rc5:

- `docs/superpowers/specs/2026-11-24-precondition-concurrency-model-design.md`: the specification;
  sections 11 (protoBaseST), 14 (amendments, R62-R70) and 15 (amendments A-1 to A-6);
- `docs/source/concurrency-model.rst`: the reference page;
- `docs/decisions.md`, D73 (amending D9, D26, D33, D34, D35 and D67);
- `docs/source/format-spec.rst`, "Format stability" and the version-7 root mark;
- `docs/source/performance.rst`: no figure measures the model;
- `tests/conformance/concurrency_scenarios.json`: the 86 scenarios;
- `tests/concurrency/test_serializability.py`: the serializability checker;
- `CHANGELOG.md`, section [Unreleased].

In this repository:

- `docs/deviations.md` lines 103-121, 116, 189 and 990, and "Format 5 is refused";
- `docs/queries.md`, "Extractors and their purity contract";
- `src/protobase/transactions.st`, `collections.st`, `indexes.st`, `keygroups.st`, `vectors.st`,
  `avl.st`, `round.st`, `publisher.st` and `cluster/`;
- `docs/not-done.md`, the runtime registry (format 5) as a plan of its own.

In protoST: `docs/superpowers/specs/2026-11-23-explicit-state-design.md`, value classes (section 5).

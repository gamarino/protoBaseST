# Changelog

## 0.1.0 (unreleased)

- Repository skeleton: error hierarchy mirroring ProtoBase, test runner, vendored
  conformance vectors (ProtoBase `v2.0.0rc1`), Python interop venv and week-0 checks.
- Values and the canonical codec: `PBFrozenList`, `PBTuple`, `PBFrozenDict`, `PBMissing`,
  `PBMutableObject` (the handle), `PBAtomPointer`, `PBUnresolvedRef` and `PBLegacyZoneDateTime`;
  `PBCodec` with `canonical:`, `toWire:atomRef:`, `fromWire:resolver:`, `encode:` and `decode:`.
  The bytes are those of ProtoBase `v2.0.0rc1`; every refusal of the format spec is explicit
  (`PBValidationError` when writing, `PBCorruptionError` when reading, `PBNotSupportedError`
  for what needs a time-zone database or `lib/uuid.st`).
- Time-zone keys are checked against `PBZoneKeys`, a committed list of the IANA tzdata 2026e
  keys (`tools/gen_zone_keys.py`), never against the host's zoneinfo. Instant-form datetimes are
  read and presented in UTC. Format-3 zone-datetime map keys whose conflicts need offsets are
  refused (`PBNotSupportedError`). Lone surrogates and values nested deeper than 511 msgpack
  containers are refused with `PBValidationError`. Duplicate map keys are found in linear time.
- The format-3 key refusal applies only to two keys that could conflict (equal at every other
  position under the order-key rule, so `true`, `1`, `1.0` and `Decimal 1.00` are one item there,
  and datetimes within the 24 h or 48 h offset window). Every string the codec writes
  (zone names, mutable names, reference type names) is checked for lone surrogates. Empty
  containers are charged one msgpack level less, and `canonical:enclosingDepth:` and
  `toWire:atomRef:enclosingDepth:` take the depth of an enclosing record.
- Conformance runners for the value layers: `PBNotation` (`describe:`, `build:`, `describeRaw:`,
  `floatHex:`, `floatFromHex:`) and the vector checks of `tests/conformance`.
- Framing and the type registry: `PBSegmentHeader`, `PBRecordHeader`, `PBRootRecord` and
  `PBAtomEnvelope` (`framing.st`); `PBTypeRegistry`, `PBAtom` and `PBOpaqueAtom`
  (`registry.st`). The built-in alias table now lives in `PBTypeRegistry builtinNames`;
  `PBNotation builtinAliasNames` is removed. `PBCodec` reads a `@ref` with the writer's tag: a
  format-2 built-in name becomes its alias, an application alias the declared name. The
  `framing` vectors and the invalid `record`, `segment` and `root` vectors pass, and so do
  `ref-format2`, `ref-name-of-builtin` and `ref-alias`.
- The read path (plan Task 12): AVL nodes and value boxes (`avl.st`); the collections with
  ProtoBase's read API (`collections.st`); `PBObject` with the reserved behaviour names of DBObject
  (`records.st`); `PBOpaqueAtom` reads its fields and refuses everything else naming its type;
  the indexes, decoded and kept (`indexes.st`); `PBSpaceRoot` and `PBDatabaseRoot` (`roots.st`);
  `PBObjectSpace`, `PBDatabase`, `PBSnapshot` and `PBHistoryEntry`, read side (`space.st`);
  `PBReferenceError`; `PBNotation describeObject:`, `describeDatabase:` and `dumpSpace:to:`.
  Every built-in type now has its class. The `database`, `legacy_database` and
  `polyglot_database` contents and the invalid `atom` vectors pass; the cluster vectors are
  visible skips (clusters are outside the prototype).
- The transaction, read side (plan Task 13, `transactions.st`): `PBDatabase >> newTransaction`
  snapshots the root record, the `SpaceRoot` and the `DatabaseRoot` once; `PBTransaction` has
  `getRootObject:`, `rootNames`, `getMutable:`, `mutableNames`, `abort`, `isActive`, `database`
  and the test-visible `readSet` and `mutableReadSet`. The first read of a name records its token
  (an atom's pointer, a plain value's exact token, `#absent`) in one immutable `PBTxState` held
  in an `Atom` and replaced with `swap:`. After `abort` every other message is `PBUserError`.
  `PBMutableObject >> get:` reads a cell through a transaction.
- Atom identity as ProtoBase D21 (ruling R13): an atom that is not stored draws its oid (a
  version-4 UUID, `UUID new`) in memory on first need, published by compare-and-swap so two first
  readers agree; a stored atom's oid is its record's. `PBAtom >> =` and `hash` go by oid, so an
  unsaved atom is a map key and a lookup probe like any other (a lookup by it misses where no
  stored key has its oid). `PBKeys isUnsavedProbe:` and the `PBNotSupportedError` for an atom
  without an oid are removed.
- A record that needs itself to be decoded (a map key referring back to it) is
  `PBCorruptionError` naming its pointer, where ProtoBase recurses until Python's
  `RecursionError`: damaged data, or a writer that breaks the save-dependents-first invariant.
  The loads in progress are passed explicitly to the resolver (`_PBLoadResolver`) instead of
  through a resumable exception, which any `on: Exception do:` around a read used to catch,
  answering the handler's value instead of the data.
- Map keys `Float infinity` and its negation (and Decimal infinities) are keys again: their
  order-key payloads are private marker objects, not Symbols (a short Symbol is a String in
  protoST, STATUS D35, so their hash was refused). ProtoBase-written maps, Dictionaries and
  HashDictionaries keyed by infinities are read (`tests/unit/read_cross_kind_keys.st`).
- A transaction's read sets are persistent maps: a first read costs O(log n) instead of
  rebuilding the map.
- The ERP example's record types, `examples/erp/erp_model.st` and `erp_model.py` (`Invoice`,
  `Customer`; `demo.erp.AuditNote` is Python-only). Design spec 10.2 runs: a space ProtoBase
  writes is dumped by protoBaseST exactly as by ProtoBase's verifier
  (`tests/interop/py_to_st.sh`).
- ProtoBase reads back the deepest attribute protoBaseST writes (509 nested lists) only with a
  raised Python recursion limit: at the default limit its reader raises `RecursionError` from
  about 333 nested lists. `tests/interop/st_deep_to_py.sh` states the workaround in a `NOTE:`
  line naming ask B12 (which the runner now shows under PASS) and fails once ProtoBase reads the
  record at the default limit. `_st_dump.st` also reads versions 2 and 1 of the ERP database.
- New versions (plan Task 15): `PBList new` and `setAt:value:`, `insertAt:value:`, `removeAt:`,
  `appendFirst:`, `appendLast:`, `extend:`, `sliceFrom:to:`, `head:`, `tail:` with ProtoBase's
  positions (Review Focus 5); `PBDictionary new`, `setAt:value:`, `removeAt:`; `PBSet new`,
  `add:`, `remove:`; `PBObject withAll:`, `with:value:` and `withAll:` on a record. Each answers a
  new atom and leaves the receiver unchanged; values are canonical at once; a collection with an
  index refuses every change (`PBNotSupportedError` naming the indexes). `PBAvl posFromArray:`,
  `posConcat:with:` and `posSlice:from:to:` build ProtoBase's trees for `extend:` and the slices.
- The save, dependents first (`PBAtom >> _saveInto:` over a storage answering `pushAtom:`): every
  record refers only to records written before it; the record carries the oid drawn in memory;
  the atom records its place (`pointer`, `isSaved`), so it is written once. `PBAtom >>
  _decodedTwin` is ProtoBase's `_decoded_twin`. Building an atom no longer needs its class to
  be registered; saving it does.
- The class comments of `PBList`, `PBDictionary`, `PBSet` and `PBCountedSet` start with "Every
  message answers a new version; the receiver never changes."
- The save refuses an unregistered class before writing any of its dependents, and two saves of
  one atom that race end the same way whatever the interleaving (one storage: the first pointer
  published; two storages: `PBValidationError`). `extend:` of nothing answers the receiver even
  when the list is indexed, as ProtoBase's; `extend:` of a String is refused up front. A
  non-Integer slice bound (a Boolean included) is refused, a documented deviation from Python's
  slice rules.
- Operation logs and merges (plan Task 16, ProtoBase `ConcurrentOptimized`, D33): every
  `PBDictionary`, `PBHashDictionary` and `PBSet` version carries `opLog` (a `PBFrozenList` of
  `PBTuple`s `('set' k v)`, `('remove' k)`, `('add' e)`, kept internally as a persistent chain,
  so a mutator logs in O(1)), `logComplete`/`isMergeable` and a `consumed` cell that
  `markConsumed` sets. `rebaseOnto:` replays the net effect (the last intent per key, by order
  key, in order of last occurrence) through the public mutators; a current of another class
  is `PBValidationError`, one with an index `PBNotSupportedError`. A `PBDictionary` logs a
  large value in its stored form, so a replay reuses the `PBValueBox` (ProtoBase D51).
- `PBHashDictionary >> setAt:value:` and `removeAt:` (buckets of `(key, value)` tuples under
  the hash key); `PBSet >> union:`, `intersection:` and `difference:`, ProtoBase's folds of
  `add:` and `remove:`.
- `PBCountedSet` and `PBRepeatedKeysDictionary` are `ConcurrentOptimized`, as in ProtoBase: a
  new empty one is mergeable and rebases to `current` unchanged (Task 16 review I1).
- `_bucketHash:` on `PBHashDictionary` and `PBHashBuckets` (ProtoBase `_bucket_hash`): lookups
  and writes file entries under it; multi-entry buckets match ProtoBase byte for byte
  (`tests/interop/bucket_collisions_identical.sh`).
- The invalid `log` vectors (framed log files, read by ProtoBase only in its cluster and
  tiered storage) are justified skips of `tests/conformance/cluster.st` (ruling R14); the
  runner prints the `SKIP:` lines of a passing test under its `PASS` line.
- Record field access in a few dispatches (plan Task 16b, ruling R15): every atom class has a
  record shape (`_PBRecordShape`: its `persistedFields` with a shared `PBMapKeyIndex`, its slot
  order, its integer fields), built from its declarations when it is registered or first
  needed and published once. Each record carries a slots Array, built once when the record is
  built or loaded and published once by compare-and-swap. A class that declares `slotFields`
  reads them through accessors with literal slot numbers (`PBPosNode`, `PBKeyNode`,
  `PBCountedKeyNode`, `PBValueBox`; an application subclass of a keyed node class inherits
  the layout, may reorder its `persistedFields` and may add fields, read with `_slotAt:`; the
  AVL writes carry such a field, present or absent, into every copy of a node); a subclass
  whose layout cannot hold, or whose `persistedFields` name a field twice, is refused when it
  is registered. Positional trees are not subclassable, as ProtoBase's `PosNode`: their writes
  build `PBPosNode` only, and a `PBPosNode` subclass is refused when it is registered, built
  or given to a positional operation. `tests/unit/record_slots.st` holds every
  literal to `slotFields` for every registered class. Integer fields are checked once per
  record (an optional one may be absent); the AVL writes, which compute them, are not checked
  again. A loaded record in persisted order shares its class's keys and index (the decoder
  builds no index for it). The walks check each child with one send, `check:` installs one
  handler per tree, and the index and root checks of `PBAvl` use no blocks. The bytes, `=`,
  `hash` and the save are unchanged. `bench/run_avl.sh` measures the AVL workload against
  ProtoBase, interleaved, for any binary and source tree.
- The file storage's write side (plan Task 17, `store.st`): `PBFileStorage >> save:`,
  `pushAtom:` (into `PBSegmentWriter`, the segment the storage owns: a fresh UUID4 name,
  `#create #exclusive`, header and directory synced), `flushSegment`, `currentSegment`,
  `tryLockRoot` and `unlockRoot` (the OS lock on `space.lock`, ProtoBase's `root_lock`),
  `replaceRoot:` (lock held, segment synced, SpaceRoot pointer checked, epoch + 1, cluster
  refusal, `space.root.tmp` synced, renamed, directory synced), `isCluster`, `isFailed` and
  `newSegmentId`. A file-system failure leaves the storage failed for writes, as ProtoBase's.
  The unit tests that saved into the `SegmentSink` double now save into `PBFileStorage`, and
  `tests/unit/_sink.st` is gone. `tests/interop/st_write_to_py.sh` runs ProtoBase's verifier on
  spaces protoST wrote, commits from each side on top of the other, and checks the root lock
  both ways; `compare_dumps.py --exact` compares dumps without the AuditNote normalisation.
- File storage write side, review fix round 1: one storage state (an Atom changed by
  compare-and-swap: idle, writing, close requested, closed), so `close` during a write is
  completed by that write and never releases the root lock under a publish, and `unlockRoot`
  during a write is refused; segment rollover as ProtoBase (`path:segmentMaxBytes:`, 256 MiB by
  default), with every segment written since its last sync synced before a root is published;
  the epoch of a publish is documented as the start epoch plus one. New tests:
  `store_close_race.st`, `store_crash_states.st`, `store_segment_rollover.st`, the seams of
  `tests/unit/_seams.st`, `tests/interop/crash_states_to_py.sh`, and the reverse lock
  exclusion (protoST holds, ProtoBase times out) in `st_write_to_py.sh`.
- ProtoBase `v2.0.0rc2` (plan Task 17b, ruling R18; ask B12 resolved): a value nests at most
  `MAX_VALUE_DEPTH` = 1022 msgpack containers (`PBCodec maxValueDepth`), counted from the value
  as the format spec counts it (an empty container counts like any other; map keys are on the
  paths), and a record therefore at most 1024. Depth 1022 round-trips; 1023 is
  `PBValidationError` when written, naming the field, attribute or collection element, key or
  value, and `PBCorruptionError` when read. This replaces the 511-container cut (509 inside a
  record, ruling R12), which a conforming reader may no longer apply;
  `canonical:enclosingDepth:` and `toWire:atomRef:enclosingDepth:` are removed, and
  `canonical:for:`, `toWire:atomRef:for:`, `valueDepth:` and
  `check:wrapping:holder:wrapper:` are added. `PBSet` refuses an element past 1020 and
  `PBHashDictionary` a key or value past 1018, when the mutator is called. The codec's walks,
  and the order keys, hash keys, tuple comparison and map-key checks, use explicit stacks: a
  recursion through `do:` or `collect:` stops at about 1,000 levels in protoST. Needs protoST's
  MessagePack at 1024 levels (protoIO `e952077`, protoST `b412b38`).
- The conformance vectors are those of `v2.0.0rc2` (digest `6e913bcb…dfbf4`): the
  `values_depth` section (`tests/conformance/values_depth.st`), seven `value-depth-over-*`
  invalid vectors, and the regenerated database vector. The interop venv holds ProtoBase
  `v2.0.0rc2` with msgpack 1.2.4; `env.sh` fails when the venv holds another commit. The
  recursion-limit workaround of `st_deep_to_py.sh` and its `NOTE:` line are gone; the deep
  cross tests run at 1022 both ways and check the refusals of 1023 both ways.
- Transactions write side and the publisher (plan Task 18): `PBObjectSpace >> newDatabase:`
  (version 0, empty objects and mutables, a 16-byte random origin, `committedAt` now in UTC);
  `PBTransaction >> setRootObject:value:`, `setRootObject:value:replace:` (a `__` name is
  `PBValidationError`), `removeRootObject:`, `newMutable:value:`, `setMutable:value:` and
  `removeMutable:` with the D35 rules, the factories `newList`, `newDictionary`,
  `newHashDictionary`, `newSet`, `newCountedSet` and `newObject:`, `commit` (a commit with no
  writes publishes nothing; a failed commit aborts) and the write side of `abort`;
  `PBDatabase >> newTransactionDo:`; `PBMutableObject >> set:value:`. A written value passes
  `PBCodec canonical:for:` with the holder `Root 'name'` or `Mutable 'name'`. The writes and the
  sets of a transaction are persistent maps (`_PBWriteMap`, O(log n) per write), like its read
  sets. `PBPublisher` (`publisher.st`), one actor per space, runs design spec 7.3: the root lock
  retried from 1 ms doubling to 50 ms until `lockTimeout` (`PBTimeoutError`), validation against
  the root read under the lock (`PBConflictError`), the merge of blind writes (`rebaseOnto:`)
  or last writer wins, save and sync, publish with that root's epoch plus one, consumed marks
  (D33), and the outcome of a failed publish decided by reading
  `space.root` again (`PBOutcomeUnknownError` when it cannot be read). `PBObjectSpace >> close`
  closes the storage through the publisher, between commits. `PBSpaceRoot databases:`,
  `PBDatabaseRoot objects:mutables:version:committedAt:origin:previous:` and `committedAfter:`.
  New tests: `tx_commit_basic`, `tx_conflict_read`, `tx_blind_merge`, `tx_replace`,
  `tx_mutables`, `tx_after_end`, `tx_refusals`, `tx_outcome`, `tx_new_database`, and
  `tests/interop/st_commit_to_py.sh` (ProtoBase verifies and reads the publisher's records,
  whose fields are in ProtoBase's order, and blind merges compose across the two languages).
- Task 18 review fix round 1:
  - **The publisher never waits** (ruling R19, review C1). An attempt that finds the root lock
    held answers `false` at once, and the committing caller owns the backoff
    (`PBObjectSpace >> _untilPublished:`, used by `commit` and `newDatabase:`). Before, a
    publisher waiting in its backoff inside a helping worker made other commits fail with
    protoST's `deadlock:` Error and lose their writes. New test: `tx_lock_contention.st`.
  - **Written atoms are saved before the root lock**, once, as ProtoBase's `_commit` does.
  - **`newTransactionDo:` commits on a non-local return** (`^`), as Python's `return` inside
    `with` does.
  - **Origin.** A new database's origin is the bytes of a version-4 UUID (`UUID new`), as
    ProtoBase's `uuid4().bytes`.
  - **Python's repr in messages.** Error texts quote names as Python's `repr` does
    (`PBCodec repr:`): the `Root`, `Mutable`, `Field` and `Attribute` holders, and the
    database messages.
  - **Unused state removed.** The space's last-known root had no reader in the spec or in
    ProtoBase outside a cluster.
  - **Comments.** The `replaceRoot:` comment and the README state the epoch rule the
    publisher follows.
  - **Interop.** New test `tests/interop/st_py_interleaved.sh`: a Python commit between a
    protoST transaction's start and its commit, and the reverse, give a conflict for the read
    root and a merge for the blind write.
- Task 18 review fix round 2 (ruling R20, review N1):
  - **`newTransactionDo:` aborts on any exception that ends the block**, as ProtoBase's
    `__exit__`. Before, only an `Error` aborted, so a `Warning` or `Notification` ended by an
    enclosing handler (`return:`, falling off) committed the block's partial writes. The block
    now asks the enclosing handlers with `Exception>>outer` (protoST 58f1834): a resumption
    goes on from the signal and the block may still commit; an exception they end unwinds the
    block and aborts. An `Error`, or an exception that is not resumable, aborts at once and is
    passed. A `^` commits, also after a resumed exception. New test: `tx_do_exceptions.st`.
- Task 18 review fix round 3 (ruling R20b, re-review N3):
  - **A resumed `Error` no longer discards the block's writes.** Round 2 aborted at once on any
    `Error`, so a resumable one (`ZeroDivide`) that an enclosing handler resumed left the block
    running on an aborted transaction. Its writes were lost, or its next transaction message
    signalled `PBUserError`. Now the transaction is aborted exactly when an exception unwinds
    the block: a resumable `Error` goes through `outer` like any resumable exception. Only an
    exception that is not resumable aborts at once and is passed. `tx_do_exceptions.st` checks
    a resumed `ZeroDivide` (committed with its write), one the handler returns from (aborted)
    and a plain `Error` (aborted).

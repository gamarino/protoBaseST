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

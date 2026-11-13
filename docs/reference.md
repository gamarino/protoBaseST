# Reference

Every public class and message of protoBaseST, grouped as the design spec groups them (section
5.1). The names are `proto_db`'s (`proto_db` at `v2.0.0rc2`) with the prefix `PB` and Smalltalk
camelCase; the first table says which is which. This file lists what exists in `src/protobase/`;
a message that is not here is not public. Names that start with an underscore (`_saveInto:`,
`_currentRoot`) are the implementation's, used by the tests, and may change.

Two rules hold for everything below, and the README states them in boxes:

- **Every collection message answers a new version**; the receiver never changes. `add:`,
  `remove:` and `removeAt:` do not mean what Pharo's do.
- **`PBList` positions are zero-based.**

Conventions: a *name* (root, mutable cell, attribute) is a `String`; a `Symbol` is accepted for a
name, since on disk a name is always a string. A timeout or backoff is a SmallInteger of
milliseconds. `Integer` arguments that must be positions or counts and are not are
`PBValidationError`. "Answers a new version" means a new atom with its own oid.

Contents:
[Mapping](#mapping-from-protobase) |
[Space and databases](#space-and-databases) |
[Transactions](#transactions) |
[Mutable objects](#mutable-objects) |
[Records](#records) |
[Collections](#collections) |
[Values](#values) |
[Errors](#errors) |
[Lower layers](#lower-layers) |
[The module and its files](#the-module-and-its-files)

## Mapping from `proto_db`

| `proto_db` | protoBaseST |
|---|---|
| `ObjectSpace`, `FileStorage`, `Database` | `PBObjectSpace`, `PBFileStorage`, `PBDatabase` |
| `Transaction`, `Snapshot`, `HistoryEntry` | `PBTransaction`, `PBSnapshot`, `PBHistoryEntry` |
| `DBObject`, `MutableObject` | `PBObject`, `PBMutableObject` |
| `List`, `Dictionary`, `HashDictionary` | `PBList`, `PBDictionary`, `PBHashDictionary` |
| `Set`, `CountedSet`, `RepeatedKeysDictionary` | `PBSet`, `PBCountedSet`, `PBRepeatedKeysDictionary` |
| `EqualityIndex`, `RangeIndex`, `VectorIndex` | `PBEqualityIndex`, `PBRangeIndex`, `PBVectorIndex` (decoded, read only) |
| `FrozenList`, `FrozenDict`, `MISSING`, a Python tuple | `PBFrozenList`, `PBFrozenDict`, `PBMissing`, `PBTuple` |
| `OpaqueAtom` | `PBOpaqueAtom` |
| `Proto...Error` | `PB...Error` |

Python keyword arguments become keyword parts (`with_(paid_on=d)` is `with: 'paidOn' value: d`).
There is no `asOf:`: `proto_db` has none either (tutorial, section 12).

## Space and databases

### PBObjectSpace

A directory holding databases, and the process-wide registry of record classes. One publisher
actor per space serialises commits (`publisher.st`); it takes the OS lock on `space.lock`, the
format's inter-process protocol, and no other lock exists in the protoST layer.

| Message | Meaning |
|---|---|
| `PBObjectSpace class >> storage: aStorage` | Space over a storage, with the default lock timeout (30000 ms). `PBValidationError` if not a storage. |
| `PBObjectSpace class >> storage: aStorage lockTimeout: ms` | The same, with a positive SmallInteger of milliseconds. A commit waits at most that long for the root lock, then `PBTimeoutError`. |
| `PBObjectSpace class >> registerAtomClass: aClass` | Registers an application record class under its `typeName` and `typeAliases` (`PBTypeRegistry register:`). Process-wide, as `proto_db`'s `register_atom_class`. `PBValidationError` for a name already taken, outside the grammar, or a `proto_db.` name outside the built-in table. |
| `PBObjectSpace class >> defaultLockTimeout` | 30000. |
| `firstLockDelay`, `longestLockDelay` (class) | 1 and 50 ms: the caller's backoff while the root lock is held. |
| `listDatabases` | The names of the databases, sorted, as an Array. |
| `newDatabase: aName` | Creates database `aName` (version 0, empty) and answers it. `PBValidationError` if it exists. |
| `openDatabase: aName` | Answers the existing database. `PBValidationError` if absent. |
| `close` | Ends the space; a later message to it or its databases is `PBClosedError`. |
| `isClosed`, `storage`, `lockTimeout` | State. |

### PBDatabase

| Message | Meaning |
|---|---|
| `name`, `space` | |
| `newTransaction` | A `PBTransaction` on the current version. |
| `newTransactionDo: aBlock` | Runs the block with a new transaction and answers its value. Commits when the block ends, also by a non-local return (`^`); aborts when an exception unwinds the block, and lets the exception go on. A resumable exception that an enclosing handler resumes does not end the block. Never retries. |
| `run: aBlock`, `run: aBlock retries: n`, `run: aBlock retries: n backoff: pair` | As `newTransactionDo:`, but on `PBConflictError` aborts and retries with a fresh transaction, at most `n` times (default 10), waiting `d * (0.5 + random / 2)` ms with `d = min(high, low * 2^attempt)` and `pair` = `#(low high)` (default `#(1 200)`). After the last retry the conflict is signalled. `PBOutcomeUnknownError` is never retried. The block may run more than once. |
| `PBDatabase class >> backoffFor: attempt low: l high: h random: aRandom` | The wait in milliseconds; the random source is a parameter so tests need no clock. |
| `history` | The committed versions, newest first, as `PBHistoryEntry` objects. |
| `snapshotAt: aReference` | A `PBSnapshot` of the version a `PBHistoryEntry` or `PBSnapshot` names. `PBReferenceError` if the version does not belong to this database (name or origin). |

### PBHistoryEntry, PBSnapshot

A `PBHistoryEntry` is a committed version without its roots; open it with `snapshotAt:`
(`proto_db` has no `get_root_object` on it either). A `PBSnapshot` is a version opened for
reading, immutable.

| Message | On |
|---|---|
| `version` | both: the version number (0 for the empty database) |
| `committedAt` | both: a `DateTime` in UTC; never earlier than the previous version's |
| `rootNames`, `mutableNames` | both: sorted Arrays |
| `getMutable: aName` | both: the value of the cell in that version, `nil` when absent |
| `getRootObject: aName` | `PBSnapshot` only: the root, `nil` when absent |
| `databaseName` | both |
| `database` | `PBSnapshot` |

### PBFileStorage

The directory: segment files `<uuid>.seg`, `space.root`, `space.lock`. It writes as the format
spec's "minimal external writer" does, so `proto_db` processes share the directory. Applications
use it only to open a space; the other messages are the publisher's and the tests'.

| Message | Meaning |
|---|---|
| `PBFileStorage class >> path: aPath` | Opens the directory, creating it if needed. Refuses (`PBNotSupportedError`) a directory with `cluster/`, or whose SpaceRoot carries a `cluster_term`. Durability is always `fsync`. |
| `PBFileStorage class >> path: aPath segmentMaxBytes: n` | A segment rolls over before it exceeds `n` bytes (default 256 MiB). |
| `PBFileStorage class >> path: aPath atomCacheEntries: n`, `path:atomCacheEntries:atomCacheBytes:`, `path:segmentMaxBytes:atomCacheEntries:`, `path:segmentMaxBytes:atomCacheEntries:atomCacheBytes:` | The atom cache holds at most `n` records (default 20,000, `defaultAtomCacheEntries`) and at most the given bytes of record payload, measured on disk (default 64 MiB, `defaultAtomCacheBytes`, `proto_db`'s storage cache default); `0` for either disables it. It keeps records already decoded or written, as decoded state, so a load does not read and decode them again; that state takes several times its payload size in memory. Records are immutable once written, so it is never stale, even with other processes writing. A load still answers new, unloaded stubs for the references and runs the class's checks, as a decode does; nothing a transaction loaded stays reachable from it. It is emptied on `close` and on a write failure; each storage instance has its own. |
| `directory`, `segmentMaxBytes`, `atomCacheEntries`, `atomCacheBytes`, `atomCacheSize`, `atomCacheWeight`, `isClosed`, `isFailed`, `isCluster` | State. A write failure of the file system is `PBUnexpectedError` and ends writing through that storage (`isFailed`); reads keep working. |
| `readRoot` | The `PBRootRecord` of `space.root`, `nil` for a new space. |
| `recordAt:`, `loadAt:expecting:`, `refTo:offset:tag:`, `recordsOfSegment:`, `openSegmentCount` | Reading by pointer. |
| `save: anAtom` | Writes the atom and its dependents (dependents first) and answers its `PBAtomPointer`. |
| `pushAtom: anEnvelope`, `flushSegment`, `currentSegment`, `newSegmentId` | One record into the storage's own segment; sync; the segment; a fresh id. |
| `tryLockRoot`, `unlockRoot`, `holdsRootLock` | The OS lock on `space.lock`. `tryLockRoot` answers at once. |
| `replaceRoot: aRootRecord` | Publishes: lock held (`PBUserError`), segments synced, SpaceRoot pointer checked (the SpaceRoot this storage just wrote is read back and compared byte for byte with what was written; any other pointer is decoded in full), epoch is current + 1 (`PBConflictError`), then `space.root.tmp` is synced, renamed, and the directory synced. |
| `close` | Never waits and never releases the root lock under a publish. |
| `PBFileStorage class >> rootFileName`, `segmentSuffix`, `rootTempFileName`, `lockFileName`, `clusterDirectoryName`, `defaultSegmentMaxBytes`, `spaceRootTag` | Format constants. |

`PBSegmentReader` (`segment:file:`, `segment`, `segmentHex`, `header`, `size`, `recordAt:`,
`records`, `close`, `isClosed`) and `PBSegmentWriter` (`create:file:`, `segment`, `segmentHex`,
`append:`, `end`, `holdsNoRecord`, `sync`, `close`, `isClosed`) are the storage's files. A writer
only writes segments it created (`#create #exclusive`), and appended bytes are never truncated.

## Transactions

### PBTransaction

Created by `PBDatabase >> newTransaction`, `newTransactionDo:` and `run:`. It reads the version
current when it started, records what it reads, and commits through the space's publisher.
States: active, committing, committed, aborted. After `commit` or `abort`, every message but
`isActive`, `database` and `printOn:` is `PBUserError`.

| Message | Meaning |
|---|---|
| `database`, `isActive` | |
| `getRootObject: aName` | The root, `nil` when absent. The transaction's own write comes first. The first read of a name is recorded (absence too). |
| `rootNames` | Sorted names as this transaction sees them. Records nothing. |
| `setRootObject: aName value: v` | Writes the root. `v` passes `PBCodec canonical:for:` at once. A name starting with `__` is `PBValidationError`. |
| `setRootObject: aName value: v replace: aBoolean` | With `true`, the root is replaced, not merged, at commit (last writer wins). |
| `removeRootObject: aName` | Removes the root (counts as a replace). |
| `getMutable: aName`, `mutableNames` | Reads a cell and its names. |
| `newMutable: aName value: v` | Creates a cell; it must be absent in the transaction's view. Answers the `PBMutableObject`. |
| `setMutable: aName value: v`, `removeMutable: aName` | Blind writes to a cell; the cell must still exist at commit. |
| `newList`, `newDictionary`, `newHashDictionary`, `newSet`, `newCountedSet` | New empty collections. |
| `newObject: anArray` | A `PBObject` from `{ 'name' -> 'Ada'. 'born' -> 1815 }`. |
| `commit` | Publishes. See below. |
| `abort` | Ends the transaction without publishing. |
| `readSet`, `mutableReadSet` | A `PBFrozenDict` of name to token. For tests and diagnosis. |

**Commit.** The publisher reads `space.root` under the root lock and validates every read token
and every blindly set cell against it (`PBConflictError`). It builds the new version from the
*current* roots. A root written but neither read nor replaced is merged when the value is a
collection with a complete operation log (`rebaseOnto:`); otherwise the last writer wins.
Mutable cells are never merged. Atoms are saved before the lock is taken, once. A commit with no
writes publishes nothing. A failed commit leaves the transaction aborted. If the lock is held,
the caller retries from 1 ms, doubling to 50 ms, until the space's `lockTimeout`
(`PBTimeoutError`); the publisher itself never waits, because an actor must not block its worker.
When a publish fails, `space.root` is read again: its own root means success; the root it built
on means nothing was published (the original error); another root is `PBConflictError`; a root
that cannot be read is `PBOutcomeUnknownError`.

## Mutable objects

### PBMutableObject

An immutable handle naming a cell of the database's mutable table. Its value changes only by
commit; the history keeps every earlier value.

| Message | Meaning |
|---|---|
| `PBMutableObject class >> name: aName` | The handle. |
| `name` | |
| `get: aTransaction` | The cell's value in that transaction (`getMutable:`). |
| `set: aTransaction value: v` | Sets the cell (`setMutable:value:`). |

## Records

### PBObject

`proto_db`'s `DBObject`. Subclass it for an application type.

| Message | Meaning |
|---|---|
| `typeName` (class) | **You define it.** The language-neutral type name: two or more dotted ASCII identifiers (`acme.sales.Order`). |
| `typeAliases` (class) | **You define it, optionally.** Names the type was stored under before. |
| `reservedAttributeNames` (class) | **You define it, optionally.** Behaviour names no implementation may persist. A record holding one is `PBCorruptionError` when loaded. `with_` and `has_defined_attr` are always reserved. |
| `PBObject class >> withAll: anArray` | A record from `{ 'a' -> 1. ... }`; attribute order is kept. |
| `with: aName value: v` | A new version with that attribute set. A change keeps an attribute's place. |
| `withAll: anArray` | A new version with several changes. |
| `at: aName` | The attribute; `nil` when absent. |
| `hasDefinedAttr: aName` | |
| `attributeNames` | |

Attribute names follow the format's rule: no leading `_`, not `oid`, `atom_pointer` or
`context`, not a reserved name; otherwise `PBValidationError`. An accessor method must only
answer the stored value (`self at: 'total'`); a computing method must be listed as reserved.

### PBAtom, PBTypeRegistry, PBOpaqueAtom

`PBAtom` is the base of everything persisted. `PBTypeRegistry` maps type tags to classes.
Applications meet them through `registerAtomClass:` and through a record read from a file.

| Message | Meaning |
|---|---|
| `PBAtom >> oid`, `tag`, `pointer`, `isSaved`, `isLoaded`, `knownOid`, `state`, `stateAt:` | Identity and the stored fields. An atom's oid is its record's; an atom not stored draws a version-4 UUID in memory on first need (`proto_db` D21). Atoms are `=` when one object or sharing an oid. |
| `PBAtom class >> typeName`, `typeAliases`, `requiredFields`, `persistedFields`, `integerFields`, `slotFields`, `unloadedAt:storage:` | The class-side declaration. |
| `PBTypeRegistry class >> register:` | As `registerAtomClass:`. |
| `classForTag:`, `tagFor:`, `isRegistered:`, `nameOfTag:`, `canonicalTag:`, `writerTag:`, `isTag:sameTypeAs:`, `recordShapeForTag:`, `unloadedAtomFor:at:storage:`, `checkOpaqueName:`, `aliasOf:`, `isValidName:`, `builtinNames`, `builtinCount` | Lookup. An unregistered application name gives `PBOpaqueAtom`; an unknown `proto_db.` name is `PBCorruptionError`. |

A `PBOpaqueAtom` is a record of a type with no class here (decision D59). It answers `typeName`,
`tag`, `at:` and `attributeNames`; every other message, and its use where a built-in type is
expected, is `PBNotSupportedError` naming the type. It is never re-written: a reference to it is
kept byte for byte.

## Collections

All inherit from `PBIndexedCollection` (`proto_db`'s `IndexedCollection`). Every write answers a
new version. Values, keys and elements pass through `PBCodec canonical:` at once; a key or
element that is not orderable (a NaN, a list, a map) is `PBValidationError`. A collection that
has an index refuses every change with `PBNotSupportedError` naming its indexes (design spec 7.4).

**Common** (`PBIndexedCollection`):

| Message | Meaning |
|---|---|
| `PBList new`, `PBDictionary new`, ... | An empty collection. |
| `count`, `size`, `isEmpty`, `notEmpty` | The persisted count (`size` is a synonym). |
| `do: aBlock`, `elements` | The elements in the collection's own order; `elements` as an Array. |
| `indexNames`, `getIndex: aName`, `indexes` | The indexes, sorted; `nil` when absent. |
| `opLog` | A `PBFrozenList` of `PBTuple`s: the intents that built this version (`proto_db`'s names: `('set' k v)`, `('remove' k)`, `('add' e)`, `('transform' e removes adds)`). |
| `logComplete`, `isMergeable` | True for a version built by `new` and derived only by logged mutators; false for a loaded version and everything derived from it. A `PBList` has no log and is never mergeable. |
| `rebaseOnto: current` | Replays the net effect of the log onto `current` (the last intent per key, by order key, in order of last occurrence). `current` of another class is `PBValidationError`; one with an index `PBNotSupportedError`. |
| `markConsumed`, `consumed` | Set by the publisher after a commit: later versions are no longer mergeable, so a reused value replaces instead of replaying twice (D33). |

**PBList.** Zero-based positions; a negative position counts from the end; a position out of
range or not an Integer is `PBValidationError`.

| Message | Meaning |
|---|---|
| `getAt: i` | The element. |
| `setAt: i value: v`, `insertAt: i value: v`, `removeAt: i` | `insertAt:` with `i` = count appends. |
| `appendFirst: v`, `appendLast: v`, `extend: aCollection`, `head: n`, `tail: n` | `extend:` of nothing answers the receiver. |
| `sliceFrom: a to: b` | Python slice rules; `nil` is an open end. |

**PBDictionary** (a tree ordered by order key) and **PBHashDictionary** (a tree by hash key;
buckets of key-value tuples):

| Message | Meaning |
|---|---|
| `getAt: k`, `getAt: k default: d`, `has: k` | Keys are compared by order key: `1`, `1.0` and `Decimal 1.00` are one key; `true` is another. |
| `setAt: k value: v`, `removeAt: k` | `removeAt:` of an absent key answers a new version with the same content. |
| `keys`, `values`, `items`, `keysAndValuesDo:`, `do:` | `items` are Associations. `PBDictionary` iterates in key order, `PBHashDictionary` in hash order. |

**PBSet**: `add:`, `remove:`, `has:`, `union:`, `intersection:`, `difference:` (the operand is a
set or anything answering `do:` except a String). They fold `add:` and `remove:`, so the log
records each element's intent.

**PBCountedSet**: `add:` (one occurrence more), `remove:` (one fewer; the last takes the element
out; an absent element answers a new version with the same content), `countOf:`, `has:`, `count`
(distinct elements), `totalCount` (all occurrences), `items` (element to count),
`keysAndValuesDo:`. Its merge composes: concurrent increments are all kept.

**PBRepeatedKeysDictionary**: `getAt:`, `has:`, `keys`, `values`, `items`, `keysAndValuesDo:`,
`totalCount`. Read only; its writes are a non-goal.

**Indexes** are decoded and kept, not queried: `PBEqualityIndex`, `PBRangeIndex`
(`PBKeyGroupIndex`), `PBVectorIndex` (`dim`, `metric`, `backend`, `params`, `centroids`,
`trainedSize`, `storeEntries`). On all: `name`, `keySpec`, `hasMemberTokens` (false for an index
written by format 3), `totalCount`. `PBIndexSet` (`names`, `get:`, `size`, `isEmpty`) holds a
collection's indexes.

## Values

The canonical values of the format, and what each is in protoST. Equality between stored values
and dictionary keys follows the format's order keys, never protoST's `=`.

| Format kind | protoST class | Notes |
|---|---|---|
| nil, bool, int, float, str, bytes | `nil`, `true`/`false`, `Integer`, `Float`, `String`, `ByteArray` | an integer outside -2^63..2^64-1 is `{"@int": hex}`; floats keep their 64 bits; a string holding a lone surrogate is refused |
| decimal | `Decimal` (protoST `lib/decimal.st`) | to-scientific-string; sign, exponent, trailing zeros kept |
| date, time, datetime, timedelta | `CalendarDate`, `TimeOfDay`, `DateTime`, `TimeSpan` (protoST `lib/calendar.st`) | fixed offsets and `UTC`; no IANA wall-clock conversion |
| uuid | `UUID` (protoST `lib/uuid.st`) | 16 bytes in RFC 4122 order |
| list | `PBFrozenList` | an `Array` or `OrderedCollection` is copied into one when written |
| tuple | `PBTuple` | orderable when its items are; may be a key |
| map | `PBFrozenDict` | insertion order kept; a protoST `Dictionary` is refused |
| missing | `PBMissing default` | only in index keys |
| mutable | `PBMutableObject` | |
| ref | the atom, loaded on access | `PBUnresolvedRef` when decoded without a resolver |
| opaque atom | `PBOpaqueAtom` | |

Everything else (`Symbol` longer than six bytes, `Fraction`, `Character`, `Set`, `Bag`,
`Dictionary`, `Interval`, a block, any other object) is refused with `PBValidationError` naming
the class. A host subclass of a mapped class is stored as its base value.

- `PBFrozenList`, `PBTuple`: `withAll:` (an `Array`, `OrderedCollection`, `PBFrozenList` or
  `PBTuple`), `size`, `isEmpty`, `notEmpty`, `at:` (1-based, as Smalltalk's), `do:`,
  `keysAndValuesDo:`, `associations`, `asArray`, `=`, `hash`.
- `PBFrozenDict`: `withAssociations:`, `size`, `at:`, `at:ifAbsent:`, `includesKey:`, `do:`,
  `keysAndValuesDo:`, `keys`, `associations`, `=` (ignores order, as Python's dict equality).
- `PBMissing default`; `PBAtomPointer` (`segment:offset:`, `segmentBytes`, `segmentHex`, `offset`,
  `pythonText`); `PBUnresolvedRef` (`pointer:tag:`, `pointer`, `tag`).
- `PBLegacyZoneDateTime`: a format-3 `["zone", key]` datetime, read lazily. `isLegacyZone` answers
  true (`DateTime >> isLegacyZone` answers false). It signals `PBNotSupportedError` whenever an
  answer needs the zone's offset. It is never written.
- `PBZoneKeys` (`release`, `includes:`, `size`): the pinned list of IANA zone keys (tzdata 2026e).

## Errors

`PBDBError` (an `Error`) is the root. These mirror `proto_db/errors.py`, so `on: PBLockingError do:`
means the same in both languages. `PBTimeoutError` is not protoST's `TimeoutError`.

| Class | Meaning |
|---|---|
| `PBValidationError` | An argument or value is refused when written or used |
| `PBReferenceError` (under `PBValidationError`) | A snapshot or version does not belong to this database |
| `PBClosedError` (under `PBValidationError`) | The space or storage is closed |
| `PBUserError` | Misuse: a transaction used after its end, a lock not held |
| `PBCorruptionError` | Stored data is damaged or malformed |
| `PBClusterProtocolError` (under `PBCorruptionError`) | Bytes received on a cluster connection are not a valid protocol-13 message |
| `PBNotSupportedError` | Valid, but outside what the prototype handles |
| `PBUnexpectedError` | The file system failed |
| `PBOutcomeUnknownError` (under `PBUnexpectedError`) | The commit may or may not have been applied; never retried |
| `PBLockingError` | |
| `PBConflictError` (under `PBLockingError`) | A read root, cell or the root itself changed meanwhile |
| `PBTimeoutError` (under `PBLockingError`) | The root lock was not obtained within `lockTimeout` |

## Lower layers

For tests, tools and readers of the format. An application does not need them.

- **`PBCodec`**: `canonical: v`, `canonical: v for: holder` (the holder names the refusal:
  `Root 'x'`), `valueDepth:`, `check:wrapping:holder:wrapper:`, `maxValueDepth` (1022 msgpack
  containers), `toWire:atomRef:`, `toWire:atomRef:for:`, `fromWire:resolver:`, `encode:`,
  `decode:` (`PBCorruptionError` for malformed bytes), `repr:` (Python's `repr` of a string, used
  in messages), `tokenRef`, `pointerRef`, `tooDeepData:`.
- **`PBKeys`**: `orderKey:`, `compare:with:`, `isOrderable:`, `hashKey:`, `exactToken:`,
  `checkMapKeys:`, `checkMapKeys:reading:`, `checkDecidableKeys:`, `modulus`, `residue:`,
  `bitLength:`, `signedBytes:`, `feed:`, `offsetWindow`. `PBOrderKey`, `PBIdentityKey`,
  `PBMapKeyIndex` are its value types.
- **Framing** (`framing.st`): `PBSegmentHeader`, `PBRecordHeader`, `PBRootRecord`,
  `PBAtomEnvelope`: `decode:` and `encode` for the byte frames. Integers are little-endian;
  every checksum is CRC-32. Readers accept format versions 2, 3 and 4; writers write 4.
- **Framed logs** (`cluster/log.st`): `PBFramedLog`, the append-only log file of `proto_db`'s
  `logfile.py`. Class side: `header:` (kinds `'ROOT'`, `'RANG'`, `'SEGS'`), `frame:`,
  `scan:kind:path:`, `read:kind:` (never writes; a missing file is an empty log),
  `openAppend:kind:` (creates the file with its header, truncates a torn tail and reports it on stderr, syncs; a file
  with more than one hard link is `PBLockingError`, checked on the open file before anything is read or repaired, as
  `proto_db`'s open_log). Any other failure to read a file is `PBUnexpectedError`, where `proto_db` lets `OSError` propagate. An
  open log answers `payloads`, `append:sync:`, `sync`, `close`, `isClosed`, `path`. A scan is a
  `PBLogScan` (`payloads`, `validEnd`, `isTorn`). A torn tail is dropped; a damaged frame
  followed by a valid one is `PBCorruptionError` ("mid-log"); another format version is
  `PBNotSupportedError`. The search for a later valid frame is linear in the file size.
- **Membership** (`cluster/members.st`): `PBPeer` (`nodeId:host:port:`; `nodeId`, `host`,
  `port`) and `PBMembership` (`peers:voters:`, voters `nil` for the default: the first three ids
  in code point order, every member of a smaller cluster; an explicit set has distinct members,
  odd and at least three when the cluster has three or more). It answers `ids` (code point
  order), `rankOf:`, `voters`, `isVoter:`, `majority` (`V // 2 + 1`), `fingerprint` (CRC-32 of
  the UTF-8 of the voter ids joined with `,`) and `peerNamed:`. An empty or non-String id,
  duplicate ids and more than 4096 members are `PBValidationError`. Class side:
  `ballotAfter:rank:` (`((floor - r) // 4096 + 1) * 4096 + r`), `rankBits` (12), `maxMembers`,
  `refoundStep` (2^44).
- **Root order** (`cluster/rootlog.st`): `PBLabeledRoot` (`label:record:`, the record `nil` for
  the empty space; `label`, `record`, `epoch`, `key`: label, epoch, segment bytes, offset) and
  `PBRootOrder` (`compare:with:`, `max:with:`, and `compareKey:with:`, which takes only keys answered
  by `PBLabeledRoot key` and applies no corruption rule), the only comparison of roots.
  An unknown root is `nil` and orders below every known one; two different roots with equal
  label and epoch are `PBCorruptionError`.
- **Acceptor log** (`cluster/rootlog.st`): `PBAcceptorLog`, `proto_db`'s RootsLog (kind
  `'ROOT'`). Class side: `path:` (takes the lock on the path plus `lockSuffix` (`'.lock'`) first,
  a held lock being `PBUserError` naming the lock file; then opens or creates the log and its
  directory with `PBFramedLog openAppend:kind:` and syncs the file, its directory and the
  parent directory), `encode:label:root:` (the 41-byte entry of kind `#accepted`, `#committed`,
  `#promise` or `#rejoined`; the root a `PBRootRecord` or `nil`), `decode:path:` (pure: payloads
  to a `PBLoggedRoots`; kinds 1 to 6), `logKind`, `framedLogClass` (a test seam). An open log
  answers `append:label:root:` (`#accepted`, synced, or `#committed`, not synced), `promise:`
  (synced; a term not above the durable promise writes nothing), `markRejoined` (synced),
  `load`, `close` (idempotent), `isClosed`, `isFailed`, `path`. A failed write or sync is
  `PBUnexpectedError` and poisons the log: every later write is `PBUnexpectedError` until it is
  reopened; a closed log refuses writes with `PBClosedError`. `PBLoggedRoots` answers
  `accepted` and `committed` (`PBLabeledRoot` or `nil`), `promise` (0 when none), `top`,
  `isRejoined`, `dataEntryCount` (kinds 5 and 6) and `entries` (`PBLogEntry`: `kind`, `label`,
  `root`, `seq`, `pred`, `records`, `ranges`, `flags`; `nil` where the kind has no such field).
  Malformed entries and two different roots of one kind with equal label and epoch are
  `PBCorruptionError`.
- **Wire messages** (`cluster/protocol.st`): `PBClusterMessage`, the 22 message types of
  `proto_db`'s cluster protocol 13 (`protocol.py`). Class side: `protocolVersion` (13), `schema`
  (a fresh `Dictionary` from each type to its `name -> kind` Associations in the order of the
  format spec's table; kinds `#int #number #str #bool #root #records #uuid #optBytes #optStr
  #ranges #strs #after`), `type:from:fields:` (a message to send: exactly the fields of the type,
  as `name -> wire value`; anything else is `PBValidationError`), `decode:` (the body of one
  frame), `rootFrom:` / `rootValue:` (a wire root and a `PBLabeledRoot` or `nil`: `[0, nil, nil,
  label]` is the empty space, the 3-item form reads with label 0 and is never written),
  `rangesFrom:` / `rangesValue:` (`nil` or `{ segment bytes. start. end }` triples, start <=
  end) and `afterFrom:` (`nil` or `{ seq. holder }`). A message answers `type`, `from`, `at:`
  (a fresh copy of a field's wire value) and `encode` (the msgpack map `v type from` then the
  fields in table order). `decode:` signals `PBClusterProtocolError` (a `PBCorruptionError`) for
  bytes that are not one msgpack map, a map key that is not a str or bin, a missing `v`, `type`
  or `from`, another version, an unknown type, a missing or ill-typed field, or a timestamp ext
  msgpack-python would refuse (extra fields included); extra fields are ignored and never
  re-encoded. `type:from:fields:` also refuses integers of 2^64 or more and the 3-item root
  form. The rules where `proto_db`'s code and format spec differ are in
  [deviations.md](deviations.md#cluster-wire-messages). The frame around a message is not here.
- **AVL** (`avl.st`): `PBNode`, `PBPosNode`, `PBKeyNode`, `PBCountedKeyNode`, `PBValueBox`, and
  `PBAvl` (class-side `posAt:index:`, `posInsert:...`, `keyAt:key:`, `keyPut:...`, `check:` and
  others). Positional trees are not subclassable; a keyed node class may be extended with fields.
  A large value is stored in a `PBValueBox`.
- **Roots**: `PBSpaceRoot` (`databases`, `clusterTerm`, `clusterEpoch`, `clusterPrevious`;
  `databases:` and, for a cluster commit, `databases:term:epoch:previous:`),
  `PBDatabaseRoot` (`objects`, `mutables`, `version`, `committedAt`, `previous`, `origin`).
  A DatabaseRoot without `mutables` is `PBCorruptionError`; a SpaceRoot written by a cluster node
  is `PBNotSupportedError`.
- **`PBNotation`**: `describe:`, `describeObject:`, `describeDatabase:`, `describeRoots:`,
  `describeMutables:`, `describeIndexes:`, `describeOrigin:`, `dumpSpace:to:` (the JSON of
  `proto_db`'s verifier `--out`), `jsonText:`, `build:`, `describeRaw:`, `floatHex:`,
  `floatFromHex:`.
- **`PBPublisher`**: the actor that commits (`space:`, `commit:`, `createDatabase:`,
  `closeStorage`).

## The module and its files

`Import from: 'protobase'.` loads, in order, `errors`, `keys`, `values`, `registry`, `codec`,
`notation`, `framing`, `store`, `cluster/log`, `cluster/members`, `cluster/rootlog`, `cluster/protocol`, `avl`, `collections`, `records`, `indexes`, `roots`, `publisher`,
`space` and `transactions` (`src/protobase.st`, `src/protobase/*.st`, `src/protobase/cluster/*.st`); the codec itself imports
`zonekeys`. The protoST libraries it uses are `decimal`, `calendar` and `uuid`.

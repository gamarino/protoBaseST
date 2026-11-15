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
| `PBClusterProtocolError` (under `PBCorruptionError`) | Bytes received on a cluster connection are not a valid protocol-13 frame or message, or fail frame authentication |
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
- **Membership** (`cluster/members.st`): `PBPeer` (`nodeId:host:port:`, the id a non-empty String without NUL; `nodeId`,
  `host`, `port`) and `PBMembership` (`peers:voters:`, voters `nil` for the default: the first three ids
  in code point order, every member of a smaller cluster; an explicit set has distinct members,
  odd and at least three when the cluster has three or more). It answers `ids` (code point
  order), `rankOf:`, `voters`, `isVoter:`, `majority` (`V // 2 + 1`), `fingerprint` (CRC-32 of
  the UTF-8 of the voter ids joined with `,`) and `peerNamed:`. An empty or non-String id,
  duplicate ids and more than 4096 members are `PBValidationError`. Class side:
  `ballotAfter:rank:` (`((floor - r) // 4096 + 1) * 4096 + r`), `rankBits` (12), `maxMembers`,
  `refoundStep` (2^44).
- **Configuration** (`cluster/config.st`): `PBClusterConfig nodeId:peers:options:`, the validated settings of one member
  (the node id must be a member). Options, in milliseconds as Integers, with `proto_db`'s defaults: `#leaseDuration` 2000,
  `#driftMargin` (default and minimum `ceiling(2D/3)`, below `D`), `#requestTimeout` 250 (below the belief `D - margin`),
  `#sendReserve` (default `min(requestTimeout, belief // 4)`, at most `belief // 4`), `#acquireTimeout` 30000, `#backoff`
  `#(1 50)`, `#startupGrace` (default `D + margin`), `#persistInterval` 50, `#persistLag` 1000, `#ownerIdleRelease` nil,
  `#voters` nil, `#authKey` nil or a `ByteArray` of at least 32 bytes, `#seed`, and the test seams `#transport` and `#clock`.
  An unknown option or a refused value is `PBValidationError` naming it; `#fetchTimeout` is
  `PBNotSupportedError` (Phase D). An option key is a Symbol or String; a duration is at most `SmallInteger maxVal // 4000` ms; an explicit `nil` for
  `#driftMargin`, `#sendReserve`, `#startupGrace` or `#ownerIdleRelease` (positive when given) means the default. The accessors answer microseconds: `leaseDuration`, `driftMargin`, `belief`,
  `requestTimeout`, `sendReserve`, `acquireTimeout`, `backoffLow`, `backoffHigh`, `startupGrace`, `idleEnd`,
  `persistInterval`, `persistLag`, `ownerIdleRelease`; the constants `wakeSpread`, `minStraggle`, `straggleFactor`,
  `turnSilence`, `gatherAttempts`, `retryHold`, `retryWait`, `permitRetries`, `depth` (0); and `membership`, `nodeId`,
  `rank`, `authKey`, `seed`, `transport`, `clock`. `PBClusterConfig timerTable` answers the timers that apply at depth 0 as
  rows `{ name. default. what it drives }`.
- **Lease values** (`cluster/lease.st`): `proto_db`'s `lease.py` as immutable values; time is
  the argument `now:` in microseconds and nothing reads a clock. `PBGrantState initial:now:`
  builds the state of a peer that refuses every request until `now + startupGrace`. A state
  answers:
  - `restore:` (a `PBLoggedRoots`: the logged promise and the accepted root's label count as
    granted) and `restore:seen:` (a term, of which only the second argument is lease activity:
    a rejoin's form);
  - `promise:` (a rejoin's ballot: `{ newState. endedTerm }`, ending a grant of a lower term);
  - `decideRequest:inc:term:now:config:` and `renew:inc:term:now:config:`, each answering a
    `PBGrantDecision`: `verdict` `#grant` or `#reject`, `reason` the wire string `'granted'`,
    `'bad_ballot'`, `'starting'`, `'stale_term'`, `'busy'` or `'term_taken'`, `highest`,
    `remaining`, `promiseToLog` (the term of a grant, `nil` on a refusal), `endedTerm` (a grant
    ended without its holder's release, 0 when none) and `newState`. The holder must be a
    member (`PBValidationError` otherwise);
  - `release:inc:term:now:` (`{ newState. endedTerm }`; closes the term here);
  - `highestSeen`, `termsSeen` (lease activity only, as terms_seen of `proto_db`),
    `highestGranted`, `grantedTop`, `activeGrant` (a `PBActiveGrant`: `holder`, `inc`, `term`,
    `expiry`; or `nil`) and `isStarting:`.

  `PBAttempt term:rid:sentAt:voters:` answers `withGrant:root:committed:certain:`,
  `withReject:reason:highest:remaining:` (a peer counts once), `state` (`#pending`, `#won` at
  `voters // 2 + 1` grants, `#lost` past reach), `needed`, `replies`, `busyRemaining`,
  `highestSeen`, `committedRoots`, `validUntil:` (a configuration: the send plus the belief,
  never the win) and `bestRoot:suspect:` (`{ root. certain }`: the highest root in root order
  of the granters' and the requester's own). `PBLease term:validUntil:root:certain:` answers
  `remainingAt:`, `isValidAt:`, `term`, `root`, `isCertain`. `PBPermission
  term:seq:rid:owner:root:certain:sentAt:valid:` is a `PBLease` valid until the send of its
  request plus the owner's `valid:`, with `seq`, `rid`, `owner` and `after` (`nil` at depth 0).
  The constructors refuse a missing or ill-typed term, holder, seq or time
  (`PBValidationError`).
- **Coordinator core** (`cluster/core.st`): the sans-IO core's vocabulary. `PBCoordinatorCore new`
  is the rules object, stateless: `dispatch:in:now:` (an event, a `PBNodeState`, the time now in
  microseconds of the node's clock) answers a `PBStep` (`state`, `effects`), and
  `accept:in:now:` (an acceptor event, a `PBAcceptorState`) answers a
  `PBAcceptorStep` (`state`, `appends`, `reply`: the shell writes the appends in order and
  performs the reply only once every append with `sync` true is durable, then hands the step to
  the dispatcher as `PBAcceptorDecided step:`). The event picks its rule method by double
  dispatch (`dispatchWith:in:now:`, `acceptWith:in:now:`), one per event class:
  `dispatchReceived:in:now:`, `dispatchTimerFired:in:now:`, `dispatchStartNode:in:now:`,
  `dispatchStopNode:in:now:`, `dispatchPermitWanted:in:now:`, `dispatchBaseWanted:in:now:`,
  `dispatchReplicateWanted:in:now:`, `dispatchDoneReport:in:now:`,
  `dispatchRejoinWanted:in:now:`, `dispatchAcceptorDecided:in:now:`, `acceptReceived:in:now:`
  and `acceptStart:in:now:`; a rule not yet defined by a later module answers the state
  unchanged with no effect. Events: `PBReceived message:`, `PBTimerFired token:event:`,
  `PBStartNode`, `PBStopNode`, `PBPermitWanted waiter:`, `PBBaseWanted permission:waiter:`,
  `PBReplicateWanted permission:root:pred:waiter:` (the root built and the root it was built on), `PBDoneReport permission:outcome:` (`#committed`,
  `#unknown` or `#none`), `PBRejoinWanted`, `PBAcceptorDecided step:`, `PBAcceptorDiscarded
  step:reason:` (the step the shell discarded because its append failed, and the failure's text; `dispatchAcceptorDiscarded:in:now:`). Effects, each answering
  `applyTo:` with one message the shell implements (applySend:, applyToAcceptor:, applyTimer:,
  applySettle:, applyPublishCommitted:, applyPublishAcceptor:, applyFence:, and for the base
  choice applyReadPersisted: and applyProbeRoot:): `PBSend
  to:message:`, `PBToAcceptor event:` (the node's own vote and acceptance, never through the
  transport; the event's class answers `isAcceptorEvent` true: `PBReceived` and `PBStartNode` here, and
  a later module adds its own), `PBTimer after:token:event:` (`fired` is its `PBTimerFired`), `PBSettle
  waiter:outcome:`, `PBPublishCommitted root:`, `PBPublishAcceptor state:`, `PBFence reason:`,
  and `PBLogAppend kind:label:root:sync:` (`payload` is its `PBAcceptorLog` entry), allowed only
  in the appends of an acceptor step. `PBNodeState config:inc:` answers `config`, `inc`,
  `acceptorView`, `hints`, `proposer`, `ownership`, `waiters`, `suspectTerm`, `fenced`, `rejoin`,
  `nextRid`, `withOwnership:` and `with:` (an Array of field -> value associations, the fields
  above from `acceptorView` on); `PBAcceptorStep state:appends:reply:vote:` adds `vote`: the
  grant, reject or ack of the node's own request, renewal, release or replication, which the acceptor answers to
  its dispatcher in the step instead of a `PBSend` (`state:appends:reply:` is the vote nil), and
  `state:appends:reply:vote:learnt:` adds `learnt`, the highest root label the step observed (0
  for none), from which the dispatcher clears its suspicion; `PBAcceptorState config:logged:now:` (a `PBLoggedRoots`: the
  grant state starts its grace at that time and restores the logged promise; the accepted root
  is the higher in root order of the logged accepted and committed roots) answers `config`,
  `grants`, `accepted`, `committed`, `seqSeen`, `suspectTerm`, `isRejoined`, `rejoinBallot`,
  `tierFailed`, `fenced` and `needsConfirmation` (true for a new acceptor state, L18), and `with:`
  (`#accepted`, `#committed`, `#seqSeen`, `#suspectTerm`, `#rejoinBallot`, `#confirmed`).
  Nothing in the core reads a clock; constructors refuse ill-typed
  arguments (`PBValidationError`). The deterministic simulator that drives it in the tests is
  test support (`tests/unit/_sim.st`), not part of the module.
- **Acceptor rules** (`cluster/acceptor.st`): the acceptor side of `proto_db`'s coordinator as
  rule methods of `PBCoordinatorCore`. In `core.st`, `dispatchReceived:in:now:` drops a message
  whose sender is not another member, drops a type of `fingerprintedTypes` whose vs is not this
  voter set's fingerprint with `PBCount stat: 'config_mismatches'`, then calls the handler of the
  type (`handlerFor:prefix:`: received<Type>:in:now:) when a module defines one;
  `acceptReceived:in:now:` drops a non-member and calls accept<Type>:in:now: (this node's own
  messages included: its vote travels in the step's `vote`, never counts `'grants_given'`, and its
  own release raises no suspicion); `dispatchStartNode:in:now:` hands the start to the acceptor. Here,
  `receivedQuery:in:now:` hands the message to the acceptor (`PBToAcceptor`), as do the
  handlers of requests, renewals and releases, defined in `cluster/proposer.st` only; it answers in
  `acceptRequest:in:now:` and `acceptRenew:in:now:` (nothing when fenced; a refusal of the
  state, 'learner', 'tier_failed', 'rejoining', else `PBGrantState`'s decision; a grant of a
  term above `loggedPromise` appends one synced promise, its grant carries the accepted and
  committed roots and certain, and it counts grants_given), `acceptRelease:in:now:` (dropped
  when fenced; frees the grant, closes the term, suspect for an uncertain held release) and
  `acceptQuery:in:now:` (a plain query's answer: the state `'ok'`, `'empty'`, `'learner'` or
  `'unknown'`, promised max(`termsSeen`, accepted label), 0 when unknown; answered by the
  acceptor, see [deviations.md](deviations.md#cluster-mode); a ballot query is the rejoin's
  witness rule, below). `acceptStart:in:now:` appends the
  rejoined marker for a learner or a lone voter whose log lacks it, rebuilds neither the grace
  nor the restore, and publishes the restored committed root (`PBPublishCommitted`).
  `acceptReplicate:in:now:` (CP 1.7 step 8, `proto_db` `_apply_replicate` over a shared storage)
  accepts a known root labelled with the message's term, not the empty space, whole (chunks 0),
  when `_mayAccept:term:pred:seq:in:` allows it: no refusal of the state, the ballot rule (no
  higher term granted, `_ballotAllows:in:`), not below the accepted root, not a sibling of it,
  the first root of a term after an older accepted root or on an acceptor that accepted nothing,
  a later root only on the accepted root itself (V2', `_extends:with:`), a seq not below the
  term's highest; one synced `#accepted` append, `PBPublishAcceptor`, the committed root the
  message teaches (memory only), `'accepted'`, then `'ack'` (ok, the accepted root, stored
  false). A refusal, a fenced node included, is `'ack'` ok false (`'refused'`). The node's own
  replication is decided alike, answered in the step's vote, uncounted. A `'store'` is never
  accepted (V1; ignored at DEPTH 0). `acceptDone:in:now:` learns a `'committed'` done's root and
  `PBLearnCommitted root:accept:logged:` (`acceptLearnCommitted:in:now:`, `isAccepted`,
  `isLogged`) the committed knowledge the dispatcher observes; a newer committed root is
  published and, when logged, appended `#committed` without a sync (none on a failed tier); a
  root known committed through the cluster is accepted knowledge too. A held release teaches
  its committed root after the grant it ended taints, and an uncertain one taints again; a
  committed label at or above the suspicion clears it (`_learnLabel:clears:`). The acceptor events `PBSuspect term:` (`acceptSuspect:in:now:`: raises
  `suspectTerm`) and `PBAppendFailed reason:` (`acceptAppendFailed:in:now:`: the tier fails,
  the first reason kept; the shell discards the step whose append failed). `wireSeconds:`
  converts microseconds to the wire's seconds (a reject's `remaining`). `PBCount stat:`
  (`stat`; the shell implements applyCount:), `PBAcceptorState >> log` (the identity of the
  attached log), `loggedPromise` (the promise written to that log, 0 for another log) and
  `withGrants:suspectTerm:rejoined:tierFailed:loggedPromise:` are in `core.st`.
- **Proposer rules** (`cluster/proposer.st`): the proposer side of `proto_db`'s coordinator
  (permit's acquisition loop, `_become_owner`, `_open_attempt`, `_on_reply`, `_close_attempt`,
  `_back_off`, `_own_loop_body`, `_renew`, `release` and the fairness hints) as rule methods of
  `PBCoordinatorCore`, over the immutable values `PBHints` (`hint`, `ownerTerm`, `ownerNode`,
  `waiting`, `wantingSince`, `turn`, `myTurn`, `registered`, `wakeups`, `progress`, `draw`;
  `seed:`), `PBProposer` (`phase`: `#rejoin`, `#turn`, `#attempt`, `#backoff`, `#busy` or
  `#spread`; `attempt`, `failures`, `marks`, `token`, `wakeAt`, `startedAt`, `straggling`,
  `backoffEnd`, `busyEnd`, `waited`; `start`) and `PBOwnership` (`lease`, `term`, `queue`,
  `lastDemand`, `lastLocal`, `renewal`, `renewStarted`, `straggling`, `token`, `seq`, `pipeline`,
  `base`, `isCommitted`, `isAbandoned`, `isServingAt:`, `entryOf:seq:`;
  `lease:base:committed:now:`), each answering `with:` (an Array of field -> value associations).
  `dispatchPermitWanted:in:now:` records the waiter's deadline (`acquireTimeout`), queues it at a
  serving ownership, else asks the owner the hint names (`cluster/owner.st`), else adds it to the
  waiters and starts an acquisition: it waits while the acceptor rejoins, defers to the member a
  release named until `turnSilence` (`'deferrals'`, `'deferral_timeouts'`, a `'want'` broadcast when
  nobody queues it), then opens an attempt (`'attempts'`, `'turns_taken'`): its own request to its
  own acceptor (`PBToAcceptor`, unless a learner) and the request to the other voters, with the
  ballot `ballotFor:` (the node's rank above the highest term its acceptor saw, the hint and the
  labels of its accepted and committed roots). Replies of another incarnation are counted
  `'stale_replies'` and dropped, a learner's reply is not a vote, every reply raises the hint; a
  majority of replies to an undecided attempt waits max(`minStraggle`, `straggleFactor` x elapsed)
  for the rest; the own vote arrives in `dispatchAcceptorDecided:in:now:` (a discarded own grant,
  `dispatchAcceptorDiscarded:in:now:`, is the refusal `'promise_failed'`). A win (`'acquired'`,
  `'ownerships'`) is an ownership whose lease ends at the send plus the belief (L5); a loss
  (`'lost_attempts'`) cancels to every member and its own acceptor and backs off for the jittered
  exponential delay, extended to the refusals' busy remaining (`microsFromWire:`, the inverse
  of `wireSeconds:`, total: a non-finite or huge number answers `wireMicrosCap`, 2^52 us, clamped
  to `leaseDuration` like any busy remaining): a held release or a newly learnt owner ends the back-off, any release only
  its busy extension, after which a member the release did not name waits a random spread of up
  to `wakeSpread`. An owner with demand renews at half the belief left (`'renewals'`,
  `'renewal_failures'`; a failed renewal does not end the term); without demand for `idleEnd`, or
  without local demand for `ownerIdleRelease` (`'terms_released_idle_local'`), it releases (held,
  certain), naming the member seen waiting longest (`'turns_named'`) and saying `'more'` while local
  waiters remain. `receivedRequest:in:now:`, `receivedRenew:in:now:` (the owner hint),
  `receivedRelease:in:now:` and `receivedWant:in:now:` keep the hints;
  `dispatchTimerFired:in:now:` ignores a timer whose token is not the current one. A waiter whose
  deadline passed ends in `PBTimeoutError` after a lost round, a deferral that yields to a known
  owner, or while the acceptor rejoins; the back-off never lasts past the earliest deadline.
  `PBCoordinatorCore class >> drawRange` is the Park-Miller range of the seeded draws.
- **Owner rules** (`cluster/owner.st`): rules O1-O8 at DEPTH 0 and abandoned terms (`proto_db`'s
  `_dispatch`, `_on_permit_req`, `_permit_outcome`, `_abandon`, `_refuse_queue`, `_on_done_owner`,
  'finish') and the holder side of a permit request (`_permission_from_owner`,
  `_on_permit_reply`), over the immutable values `PBIssued` (`node`, `seq`, `inc`, `rid`,
  `deadline`, `permit`, `base`), `PBPermitAsk` (`waiter`, `rid`, `sentAt`, `term`, `target`,
  `request`, `retryAt`, `endAt`, `token`) and `PBHolder` (`asks`, `deadlines`, `seen`,
  `replications`, `choices`, `permits`, `deadlineOf:`, `askWithRid:`; `empty`, `permitsSeenLimit`,
  64), kept in `PBNodeState holder`.
  An owner issues one permission at a time (`'permits_issued'`): to a local waiter a
  `PBPermission` settled at once, to a member a `'permit'` valid for the lease's remaining time,
  certain when its base is known committed; its deadline is valid + `requestTimeout`. A
  `'committed'` done retires it and makes its root the base (O3), a `'none'` from the only entry
  removes it (O5), anything else, a done of another incarnation, a missed deadline or a lease
  expiring with a permission out abandons the term (`'terms_abandoned'`, `PBSuspect` to the
  acceptor, `'permit_no'` `'abandoned'` to the queue, an uncertain release). A retried request gets
  the same permit again (O7); the term ends idle only with an empty pipeline (O8); a request for
  a term the node does not serve gets `'permit_no'` (`'not_owner'` or `'ending'`, term the highest
  seen). `receivedDone:in:now:` counts a wake-up and progress, sequences the owner's outcome and
  forwards the done to the acceptor; `dispatchDoneReport:in:now:` broadcasts the holder's done
  (`PBDoneReport permission:outcome:root:`; its copies name the holder for a committed root). A holder asks with `'permit_req'`
  (`'permit_requests_sent'`, retried every `requestTimeout`, `'permit_requests_retried'`); a
  permit of another incarnation is dropped (`'permits_foreign_dropped'`), one nobody waits for
  handed back with done `'none'`, else held (`'permits_held'`, valid from the request's send); a
  refusal (`'permits_refused'`) or a silence of `leaseDuration` forgets the owner only while the
  hint names the term asked under. A local waiter queued at the ownership leaves the queue with
  `PBTimeoutError` at its deadline (`acquireTimeout`). A certain permit, held or issued to a
  local waiter, teaches its base committed (`PBLearnCommitted`, not logged); a grant's committed
  root is committed knowledge only (`cluster/proposer.st`).
- **Holder's replication** (`cluster/holder.st`): `proto_db`'s replicate and `_on_answer` for an
  ack, at DEPTH 0 over a shared storage. `dispatchReplicateWanted:in:now:` refuses a root not
  labelled with the permission's term, and a pred other than `predFor:in:` (the root last sent
  under the permission, else the base bound to it, else its root; the empty space labelled 0
  when it has none), with `PBValidationError`; past the permission or under
  `sendReserve` it sends nothing and settles `#none` (H7); else it sends `'replicate'` (no
  records, chunks 0, the permission's seq, the pred, the committed root, vs, copies this node)
  to the other voters and the own acceptor when a voter (`'replications'`), with a timer at the
  permission's end, recorded as a `PBReplication` (`waiter`, `permission`, `rid`, `root`, `acks`,
  `nacks`, `isOwnPending`, `token`) in `PBHolder replications`. An ack of another incarnation is
  dropped (`'stale_replies'`), of another term or request ignored, of a learner never counted
  (D54); only an ack answering a replication (a learner's too) raises the hint; the own acceptor's ok counts as a
  voter's, its refusal as neither. Once the own
  acceptance answered, the replication is decided: `#committed` exactly when a majority of the
  voters acked while the permission is valid (the commit point, CP 1.7 step 9), teaching the own
  acceptor the root (logged) and clearing a suspicion it answers; more refusals than a majority
  allows, the permission's end (a timer that comes earlier is set again for the time left) or a
  failed own append end it unknown
  (`'replication_failures'`, the node and its acceptor suspect for the term): its waiter is
  settled with a `PBOutcomeUnknownError` whose text is `proto_db`'s for the case, `Node <id>:
  <why>; the root (epoch <e>) may or may not take effect`, where why is `the lease ended before
  this node observed the outcome (<n> acknowledgements, <m> needed, were counted only after the
  lease had ended)`, `<k> members refused the root, and only <n> of the <m> acknowledgements
  needed arrived` or `only <n> of the <m> acknowledgements needed arrived before the lease ended`;
  a failed own append is `Node <id>: the commit of root epoch <e> failed after the root was sent
  (<the failure>); peers may have acknowledged it, so it may or may not take effect`, the
  failure being the reason of the `PBAcceptorDiscarded`.
- **Base choice** (`cluster/holder.st`, CP 1.6): `proto_db`'s `_lease_base`, `recover_root`,
  `_phase_1_floor`, `_base_needs_commit` and the refound and hard guard, as rules over the values
  `PBBaseDecision base:needsCommit:outcome:` (`base`, `needsCommit`, `outcome`: `#ok`, `#stale` or
  `#unreachable`, `isOk`) and `PBBaseChoice` (a choice or a recovery round in progress: `waiter`,
  `permission`, `every`, `phase`, `rid`, `token`, `suspected`, `answers`, `learnt`, `current`,
  `answered:accepted:committed:state:`), kept in `PBHolder choices`. `dispatchBaseWanted:in:now:`
  is `leaseBase:waiter:in:now:`: a certain permit or a base already bound under the permission
  is the base; else a recovery round (`'query'`, ballot 0, to the other voters, a timer of
  `requestTimeout`, `receivedAnswer:in:now:`; an answer of another incarnation is dropped,
  `'stale_replies'`, a sender's later answer replaces its earlier one) that ends when
  `recoveryDone:in:` answers true: every other voter answered, or, unless `every`, a majority of
  the voters are witnesses (state `'ok'`) that answered, this node counted when it is one. The
  round counts `'recoveries'`; with fewer witnesses than a majority it settles a `PBConflictError`;
  else its result is the highest accepted root of the witnesses (this node's included), their
  committed roots are learnt (`PBLearnCommitted`, accept false, not logged), the hint rises to
  their accepted labels, and the suspicion held at the send is cleared (the acceptor's half by
  `PBRecovered suspected:`, `acceptRecovered:in:now:`, only when at most it). When
  `phase1Floor:` answers true (the permission's root is a known root other than the empty space
  labelled 0, R127) that root is the base if it orders above the result. With no root known
  anywhere the shared storage's persisted root is read (`PBReadPersisted token:`, answered by
  `PBStorageRead token:root:failure:`; `'storage_root_reads'`, learnt committed, not accepted) and
  a term below its label + `refoundStep` refounds: the hint rises to that and the decision is
  `#stale`. A committed root of a later term, or of this term above the base, makes it `#stale`;
  a base below the committed root this node knows reads the persisted root: none, one below it
  or a failed read settles the `PBCorruptionError` that names the operator's remedy (D46), one at
  or above it refounds from it. A base labelled above the term is `#stale`. `needsCommit` is true
  when the base is neither the empty space nor the committed root this node knows (R50); such a
  base is probed (`PBProbeRoot root:token:`, answered by `PBRootProbed token:readable:`,
  `isReadable`) and an unreadable one is `#unreachable` (R133). An `#ok` base is bound to the
  permission (the next choice under it is certain; `predFor:in:`), and so is each root committed
  under it (`proto_db`'s `bind_root`): a later round under the permission builds on the last
  committed root, which counts as committed knowledge. `PBRecoverWanted every:waiter:`
  (`dispatchRecoverWanted:in:now:`) runs a round alone and settles `{ known. root }` or its
  `PBConflictError`. See [deviations.md](deviations.md#cluster-mode).
- **Commit round** (`cluster/holder.st`, spec 5.6, D-LIVE-2, CC11, CC18): `proto_db`'s
  `_run_round`, `_permit_round`, `_keep`, `_take_kept`, `_await_retries` and `_drop_kept` as a
  pure state machine, `PBCoordinatorCore >> round:in:now:` (an event, a `PBRoundState`, the
  node's clock) answering a `PBStep` whose state is the new `PBRoundState` (`config:`; `queue`,
  `phase`, `batch`, `permission`, `outcome`, `committed`, `base`, `current`, `live`, `building`,
  `built`, `conflicted`, `longest`, `tried`, `rounds`, `awaiting` (the held callers),
  `awaitCount`, `stale`, `holdToken`, `rejoinBallot`, `isHeld`, `withRejoinBallot:`, which never
  lowers it). A commit is a `PBRoundEntry token:caller:willRetry:deadline:` (`caller`: its client,
  `proto_db`'s `entry.thread`; `willRetry`: its caller retries a conflict at once; `deadline`
  carried for the standalone shell). Events (`PBRoundEvent`, `roundWith:in:now:`):
  `PBRoundEnqueued entry:`, `PBPermitted permission:` (a `PBPermission` or an error value),
  `PBBaseDecided decision:` (a `PBBaseDecision` or an error value), `PBBuilt entry:root:micros:`
  (entry `nil` for the re-commit of a base that needs one; root `nil` for nothing to publish),
  `PBBuildConflict entry:error:`, `PBBuildFailed entry:error:`, `PBReplicated outcome:`
  (`#committed`, `#none`, or the replication's `PBOutcomeUnknownError`; a bare `#unknown` is
  refused; `outcome`, `error`),
  `PBHoldExpired token:`, `PBDropKept caller:`. Effects: `PBAskPermit`, `PBAskBase permission:`,
  `PBBuild entry:base:stamp:` (stamp `{ term. base epoch + 1 }`), `PBReplicate
  permission:root:pred:`, `PBSettle` of an entry's token (`true`, `false`, or an error value),
  `PBReportDone permission:outcome:root:` (a root exactly with `#committed`), `PBCount`, and the
  hold `PBTimer`. One round at a time takes the whole queue under one permission; a base that
  needs a commit is re-committed first (its unchanged root, one replication); each entry builds
  on the previous root and a conflict fails alone; before each build after the first,
  `groupBoundAllows:now:` (CC11) asks for `sendReserve` plus the longest build of the round, the
  rest going back to the head of the queue, not as attempts; before any send `mayReplicate:now:`
  refuses, with a retryable `PBConflictError` and nothing sent, less than `sendReserve` left
  (R121, `'sends_refused_reserve'` while the permission is valid; the text names the time left, `sendReserve`, the round's
  longest build, the belief and `leaseDuration`, CC18) and a term below the rejoin ballot (L14;
  `dispatchReplicateWanted:` checks it again at the send against the acceptor's ballot and then
  sends nothing, `#none`). A build error that is a `PBDBError` fails its commit alone; any other
  ends the round, nothing sent.
  `#committed` settles the built entries `true`; `#none` is a retryable conflict; an unknown
  outcome settles every built entry with the replication's `PBOutcomeUnknownError` (its text
  says why), never retried. A `#stale` base requeues the
  round at the head of the queue and ends the permission `#unknown` (unless a round under it
  committed); after `termRetries` (5) stale permissions in a row the queued commits fail with a
  `PBConflictError`; `#unreachable`
  is a retryable conflict ending it `#unknown`. A conflicted entry that will retry, while the
  permission is valid and at most `permitRetries` rounds ran, gets a `PBConflictError` with
  `permitHeld` true (`PBConflictError held:`), and the permission is kept for
  max(min(`retryHold`, the time left), `retryWait`) (`retryWait` when no retry is held); once
  every held caller has a commit queued (with none held, as many commits as the round's
  conflicts), or a `PBDropKept caller:` says an awaited one is not coming, the next round runs
  under it; its `PBHoldExpired` ends the wait (what is queued runs, else the permission ends).
- **Rejoin rules** (`cluster/rejoin.st`, CP 'A node that lost its disk', R51, R78a, L13, L14,
  L18): `proto_db`'s `_rejoin`, `_rejoin_round`, `_gather`, `_rejoin_decision`,
  `_complete_rejoin`, `_on_ballot_query` and `force_rejoin` as rule methods of
  `PBCoordinatorCore` over `PBRejoin` (`idle`; `phase`: `#idle`, `#gather`, `#probe`, `#adopt`,
  `#retry` or `#failed`; `isForced`, `blocked`, `ballot`, `attempt`, `answers`, `pending`, `log`), kept
  in `PBNodeState rejoin`, and `PBRejoinAnswer from:` (`state`, `accepted`, `committed`,
  `promised`, `ballot`, `highestLabel`). An acceptor report still rejoining starts the rejoin
  (`rejoinCheck:now:effects:`, from `dispatchAcceptorDecided:in:now:`) unless its tier failed or
  the node is fenced. A round (`rejoinRound:now:effects:`) is a plain gather: a `'query'` to
  every other voter, re-asked up to `gatherAttempts` times, each attempt a new rid and a
  `requestTimeout` timer (`rejoinAnswered:in:now:effects:`, `rejoinTimer:in:now:effects:`).
  `rejoinDecision:forced:in:` answers `{ ids. how }` or nil: `#new` (every other voter loaded,
  none with an accepted root or a promised term), `#rootless`, `#witnesses` (at least
  `rejoinAnswersNeeded:forced:`, min(V - 1, V - majority + 1) `'ok'` answers) or `#forced`
  (majority - 1 loaded). `#witnesses` and `#rootless` take the ballot round: a gather with
  `rejoinBallotFor:in:` (above every promise and label reported, the highest term seen and the
  hint, at this node's rank), whose `'ok'` answers count only when they echo it, and that must
  decide `#witnesses` or `#rootless` again (counted `'rejoin_ballots'`), else the rejoin is
  blocked and retried. The adopted root is probed (`rejoinProbed:in:now:effects:`; unreadable:
  blocked, retried); then the acceptor takes `PBRejoinLearnt learnt:seen:accepted:committed:ballot:log:`
  (refused by an acceptor attached to another log)
  (`acceptRejoinLearnt:in:now:`): it appends the promise of learnt, the accepted root and the
  rejoined marker, in that order, synced, and adopts them (`restore:seen:`), the committed root
  as committed knowledge and the ballot as `rejoinBallot`; its step coming back ends the rejoin
  (counted `'rejoins'`, the hint raised), its append failing fails it (`rejoinDiscarded:in:`).
  `rejoinBlockedIn:` is why a rejoining node cannot complete (`proto_db`'s `rejoin_blocked`).
  The witness: a ballot query to an `'ok'` acceptor promises the ballot (`promise:`, suspect for
  a grant it ends), appends it synced when above `loggedPromise`, and answers echoing it; any
  other state answers as a plain query; a fenced node answers none. `PBRejoinWanted`
  (`dispatchRejoinWanted:in:now:`, the operator's forceRejoin) forces a rejoin not completed
  yet and hands the acceptor `PBForceRejoin` (`acceptForceRejoin:in:now:`): a survivor forgets a
  committed root above its accepted root and needs a confirmation again. `PBLogDetached`
  (`rejoinDetached:in:now:`, `proto_db`'s detach) drops the rejoin and its forced flag (a late
  report of the detached log starts nothing; a forceRejoin meanwhile is for the next log), and a
  report over another log than the one a rejoin runs for starts a fresh one. `PBConfirmed`
  (`dispatchConfirmed:in:now:`, `acceptConfirmed:in:now:`) clears `needsConfirmation`. See
  [deviations.md](deviations.md#cluster-mode).
- **Root order** (`cluster/rootlog.st`): `PBLabeledRoot` (`label:record:`, the record `nil` for
  the empty space; `label`, `record`, `epoch`, `key`: label, epoch, segment bytes, offset) and
  `PBRootOrder` (`compare:with:`, `max:with:`, and `compareKey:with:`, which takes only keys answered
  by `PBLabeledRoot key` and applies no corruption rule), the only comparison of roots.
  An unknown root is `nil` and orders below every known one; two different roots with equal
  label and epoch are `PBCorruptionError`.
- **Acceptor log** (`cluster/rootlog.st`): `PBAcceptorLog`, `proto_db`'s RootsLog (kind
  `'ROOT'`). Class side: `path:` (resolves the path to its real path, `FileReference >> realPath`,
  so a symbolic link names the real file's lock, a link loop being `PBUnexpectedError`; takes the
  lock on that path plus `lockSuffix` (`'.lock'`) first, a held lock being `PBUserError` naming
  the lock file; then opens or creates the log and its
  directory with `PBFramedLog openAppend:kind:` and syncs the file, its directory and the
  parent directory), `encode:label:root:` (the 41-byte entry of kind `#accepted`, `#committed`,
  `#promise` or `#rejoined`; the root a `PBRootRecord` or `nil`), `decode:path:` (pure: payloads
  to a `PBLoggedRoots`; kinds 1 to 6), `logKind`, `framedLogClass` (a test seam). An open log
  answers `append:label:root:` (`#accepted`, synced, or `#committed`, not synced), `promise:`
  (synced; a term not above the durable promise writes nothing), `markRejoined` (synced),
  `load`, `close` (idempotent), `isClosed`, `isFailed`, `path`. The methods are not serialized:
  one caller (the acceptor actor) owns the writes, and `load` (which reads by path) is safe from
  any caller. A failed write or sync is
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
  [deviations.md](deviations.md#cluster-wire-messages).
- **Frames** (`cluster/protocol.st`): `PBClusterFrame`, class side only. `maxFrameBytes`
  (67108864, `proto_db`'s `MAX_FRAME_BYTES`) and `tagSize` (32). `encode: aMessage to: aNodeId
  key: aKeyOrNil` answers the 4-byte big-endian length then the body; `lengthFrom:` reads the
  length from the first 4 bytes alone and refuses one above `maxFrameBytes`;
  `decodeBody:to:key:` answers the message of a body; `decode:to:key:` that of a whole frame
  (its length must be the size of its body). Without a key (`nil`) the frame is protocol 13 byte
  for byte. The receiver is a non-empty String without NUL, else `PBValidationError`. With a key
  (a `ByteArray` of at least 32 bytes, else `PBValidationError`) the body
  is the msgpack bytes followed by the tag HMAC-SHA-256(key, UTF-8(receiver id) ‖ 0x00 ‖
  msgpack bytes); the length covers both and the 64 MiB limit is unchanged. A tag that does
  not match (another key, another receiver, a changed byte, an unkeyed frame) is
  `PBClusterProtocolError` whose text names authentication; the tags are compared over all 32 bytes.
  Every refusal of received bytes is `PBClusterProtocolError`, and so is encoding a body over
  the limit, as in `proto_db`'s protocol.py. The divergence from protocol 13 and the
  trusted-network assumption are in [deviations.md](deviations.md#cluster-mode).
- **Transports** (`cluster/transport.st`): `PBInProcessTransport` and `PBTcpTransport`, the two
  implementations of `PBClusterTransport`'s protocol (`proto_db`'s `transport.py`). `start: aNodeId
  peers: aMembership key: aKeyOrNil handler: aBlock` begins receiving: the node id must be a
  member of the `PBMembership`, the key is `nil` or a `ByteArray` of at least 32 bytes, and
  the one-argument block gets each valid, decoded `PBClusterMessage`; a second `start` (or one after `stop`) is
  `PBValidationError`. `send: aMessage to: aNodeId` frames the message for that node
  (`PBClusterFrame`, with the key) and never blocks: a frame over the limit is
  `PBClusterProtocolError` and anything but a `PBClusterMessage` `PBValidationError`; before
  `start` and after `stop` it is a silent no-op; a lost frame is counted, never signalled.
  `stop` answers a `Future` that settles (with `true`) once nothing more is delivered and the
  transport's actors have finished; it is idempotent. `stats` answers a `Dictionary` of
  `'frames_sent'`, `'frames_dropped'`, `'frames_rejected'` and `'connections_dropped'`
  (`PBClusterTransport statNames`). A `PBDBError` signalled by the handler is written to stderr
  and delivery goes on. `isRunning` answers whether the transport is started and not stopped.
  - `PBInProcessNetwork new` (or `seed: anInteger`) is a network of endpoints inside one
    process; `endpoint` answers a new `PBInProcessTransport`. Every message is framed by its
    sender and decoded by its receiver, each with its own key, so a keyed endpoint and an
    unkeyed one refuse each other's frames (`'frames_rejected'`). Faults: `drop: p duplicate: q`
    (probabilities from 0 to 1, drawn from the seeded generator), `partition: anArrayOfGroups`
    (frames flow only inside a group) and `heal`; a stopped endpoint is a crashed node, its node
    id free for a new endpoint. Each endpoint delivers on an actor of its own, in arrival order.
  - `PBTcpTransport listenOn: aPort host: aHost` (port 0 picks a free port; an address that
    cannot be listened on is `PBValidationError`) and `withListener: aServerSocket` (for tests
    that publish ports first), each also with `requestTimeout:` (a positive Integer of
    milliseconds, default `defaultRequestTimeout`, 1000, the timeout of every connect and write).
    `port` answers the port listened on. Frames are length-prefixed over TCP; connections are
    one-way (a node writes only on its own outbound connections). One listener actor accepts;
    one reader actor per connection reads each frame, checking the length before it reads the
    body, and closes the connection at the first refused frame; one sender actor per peer
    drains that peer's queue (bounded at `maxFrameBytes` bytes, the oldest frames dropped first),
    connecting on demand; a failed write is retried once at once on a fresh connection, and a
    failed connect drops the frame and starts a back-off of 100 to 200 ms (`backoffBase`
    microseconds to twice it) during which the frames to that peer are dropped. The handler is called on the readers,
    concurrently with several peers. The differences from `proto_db` are in
    [deviations.md](deviations.md#cluster-mode).
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
`notation`, `framing`, `store`, `cluster/log`, `cluster/members`, `cluster/rootlog`, `cluster/protocol`, `cluster/config`, `cluster/transport`, `cluster/lease`, `cluster/core`, `cluster/acceptor`, `cluster/proposer`, `cluster/owner`, `avl`, `collections`, `records`, `indexes`, `roots`, `publisher`,
`space` and `transactions` (`src/protobase.st`, `src/protobase/*.st`, `src/protobase/cluster/*.st`); the codec itself imports
`zonekeys`. The protoST libraries it uses are `decimal`, `calendar`, `uuid` and `net`.

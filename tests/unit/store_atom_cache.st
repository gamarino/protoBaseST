"EXPECT: ok 36"
"The atom cache of PBFileStorage (_PBAtomCache): the loaded envelopes of the records the
 storage decoded or wrote, keyed by pointer, bounded, emptied on close and on a write
 failure, one per storage instance.

 - What a save caches is what a decode gives: for every record a workload writes (every
   kind of root, every scalar kind, references), a stub loaded from the cache has the
   oid, the kind of memo (the record shape, or an envelope of the same type tag), the
   keys, values (atoms as stubs of the same class and pointer) and slots of a stub
   loaded by a storage with no cache (plan Task 12: the cache keeps what the atom keeps).
 - A hit decodes nothing; a stub of another class at a cached pointer is decoded, and
   refused, as before.
 - The bound holds (two generations), an evicted record is decoded again, correctly; 0
   disables the cache.
 - A closed storage answers PBClosedError for an unloaded stub, cached or not; a failed
   write empties the cache.
 - Another storage of the same directory (another process, for the space) that commits
   is read by this one: new records are decoded, the unchanged ones it cached serve."
Import from: 'protobase'.
Import from: 'decimal'.
Import from: 'calendar'.
Import from: 'uuid'.
Import from: '_check'.
Import from: '_seams'.

"Counts the decodes (loadAt:expecting:within:) and remembers what it saved."
PBFileStorage subclass: #CountingStorage instanceVariableNames: 'loads saved'.
CountingStorage >> loads
  ^ loads ifNil: [0].
CountingStorage >> savedRecords
  ^ saved ifNil: [saved := OrderedCollection new].
CountingStorage >> loadAt: aPointer expecting: aTag within: aChain
  loads := self loads + 1.
  ^ super loadAt: aPointer expecting: aTag within: aChain.
"Each record saved: { class. pointer. whether the cache can serve it (no reference inside
 a container) }."
CountingStorage >> _pbSaved: anAtom at: aPointer
  self savedRecords add: { anAtom class. aPointer. (anAtom _pbStoredStateIn: self) notNil }.
  ^ super _pbSaved: anAtom at: aPointer.

| c base dir st plain space db mismatches stub loads ptrs fresh s2 space2 seam other scanned reached gens |
c := Check new.
base := FileSystem temp / ('pbst-store-atom-cache-' , Smalltalk pid printString).
base deleteAll.
dir := base / 'space'.

"--- what a save caches is what a decode gives ---"
st := CountingStorage path: dir pathString.
space := PBObjectSpace storage: st.
db := space newDatabase: 'cache'.
db newTransactionDo: [:tr | | other recs |
  other := tr newObject: { 'name' -> 'other' }.
  recs := tr newDictionary.
  0 to: 9 do: [:r |
    recs := recs setAt: r value: (tr newObject: {
      'name' -> ('account ' , r printString). 'ratio' -> (r / 4) asFloat. 'big' -> (2 raisedTo: 70 + r).
      'flag' -> r even. 'none' -> nil. 'blob' -> (ByteArray withAll: { r. 255 - r }).
      'price' -> (Decimal fromString: r printString , '.25'). 'day' -> (CalendarDate year: 2026 month: 11 day: r + 1).
      'when' -> (DateTime utcOrdinalMicroseconds: 63900000000000000 + r zone: ZoneOffset utc).
      'span' -> (TimeSpan microseconds: r * 1000). 'id' -> UUID new.
      'pair' -> (PBTuple withAll: { r. 'x' }). 'list' -> { 1. { 2. 3 } }. 'map' -> (PBFrozenDict withAssociations: { 'k' -> r }).
      'ref' -> other. 'refs' -> { other } })].
  tr setRootObject: 'records' value: recs.
  tr setRootObject: 'list' value: ((tr newList appendLast: 'a') appendLast: other).
  tr setRootObject: 'set' value: ((tr newSet add: 'a') add: 3).
  tr setRootObject: 'cset' value: ((tr newCountedSet add: 'a') add: 'a').
  tr setRootObject: 'hd' value: (tr newHashDictionary setAt: 'h' value: other).
  tr newMutable: 'cell' value: 0].
db run: [:tr | tr setRootObject: 'records' value: ((tr getRootObject: 'records') setAt: 3 value: 'three')].
plain := PBFileStorage path: dir pathString atomCacheEntries: 0.
c that: 'a storage with no cache' is: { plain atomCacheEntries. plain atomCacheSize } equals: #(0 0).
c that: 'the workload cached what it saved' isTrue: st atomCacheSize > 0.
mismatches := OrderedCollection new.
loads := st loads.
st savedRecords do: [:each | | cls p cached decoded cs ds cm dm |
  cls := each at: 1.
  p := each at: 2.
  cached := cls unloadedAt: p storage: st.
  decoded := cls unloadedAt: p storage: plain.
  cs := cached state.
  ds := decoded state.
  cm := cached _loaded.
  dm := decoded _loaded.
  (cached oid = decoded oid and: [cm class == dm class
      and: [((cm isKindOf: PBAtomEnvelope) not or: [(PBTypeRegistry nameOfTag: cm tag) = (PBTypeRegistry nameOfTag: dm tag)])
      and: [cs keys asArray = ds keys asArray and: [cached _slots size = decoded _slots size]]]])
    ifFalse: [mismatches add: p]
    ifTrue: [
      1 to: cs size do: [:i | | a b |
        a := cs _valueAt: i.
        b := ds _valueAt: i.
        ((a isKindOf: PBAtom)
            ifTrue: [(b isKindOf: PBAtom) and: [a class == b class and: [a pointer = b pointer]]]
            ifFalse: [a class == b class and: [a = b]])
          ifFalse: [mismatches add: p -> (cs keys at: i)]].
      1 to: cached _slots size do: [:i | | a b |
        a := cached _slots at: i.
        b := decoded _slots at: i.
        ((a isKindOf: PBAtom) ifTrue: [a pointer = b pointer] ifFalse: [a = b]) ifFalse: [mismatches add: p -> i]]]].
c that: 'every record saved is cached as its decode' is: mismatches asArray equals: #().
c that: 'the records the saves cached were served without a decode' is: st loads - loads
  equals: (st savedRecords count: [:each | (each at: 3) not]).
c that: 'most were cached; those with references inside containers were left to a decode' isTrue:
  ((st savedRecords count: [:each | each at: 3]) > (st savedRecords size // 2)
    and: [(st savedRecords count: [:each | (each at: 3) not]) > 0]).

"--- hits, and the class check ---"
loads := st loads.
stub := PBObject unloadedAt: ((st savedRecords detect: [:e | (e at: 1) == PBObject]) at: 2) storage: st.
c that: 'a stub of a cached record loads it' is: (stub stateAt: 'name') notNil equals: true.
c that: 'without decoding it' is: st loads - loads equals: 0.
stub := PBObject unloadedAt: (st save: (PBObject withAll: { 'ref' -> (PBObject withAll: { 'name' -> 'x' }) })) storage: st.
other := stub stateAt: 'ref'.
other stateAt: 'name'.
c that: 'its references are its own: another load of the record answers a new, unloaded stub'
  is: ((PBObject unloadedAt: stub pointer storage: st) stateAt: 'ref') isLoaded equals: false.
c that: 'of the same record' is: ((PBObject unloadedAt: stub pointer storage: st) stateAt: 'ref') pointer equals: other pointer.
c that: 'a stub of another class at a cached pointer is refused as before' signals: PBCorruptionError during: [
  (PBSpaceRoot unloadedAt: stub pointer storage: st) state].
c that: 'that refusal decoded the record' is: st loads - loads equals: 1.

"--- another storage of the directory commits; this one reads it ---"
s2 := PBFileStorage path: dir pathString.
space2 := PBObjectSpace storage: s2.
(space2 openDatabase: 'cache') run: [:tr | tr setMutable: 'cell' value: 7].
space2 close.
loads := st loads.
c that: 'this storage reads the other''s commit' is: ((space openDatabase: 'cache') newTransaction getMutable: 'cell') equals: 7.
c that: 'decoding the new records' isTrue: st loads - loads > 0.
space close.
c that: 'close empties the cache' is: st atomCacheSize equals: 0.
c that: 'a closed storage refuses an unloaded stub, cached before' signals: PBClosedError during: [
  (PBObject unloadedAt: stub pointer storage: st) state].
plain close.

"--- the bound and eviction ---"
st := CountingStorage path: (base / 'bounded') pathString atomCacheEntries: 4.
c that: 'the bound is configurable' is: st atomCacheEntries equals: 4.
ptrs := (1 to: 10) collect: [:i | st save: (PBObject withAll: { 'i' -> i })].
c that: 'the cache holds at most its bound' isTrue: st atomCacheSize <= 4.
loads := st loads.
c that: 'an evicted record is decoded again, correctly' is: ((PBObject unloadedAt: ptrs first storage: st) stateAt: 'i') equals: 1.
c that: 'by a decode' is: st loads - loads equals: 1.
loads := st loads.
c that: 'the newest is served' is: ((PBObject unloadedAt: ptrs last storage: st) stateAt: 'i') equals: 10.
c that: 'from the cache' is: st loads - loads equals: 0.
st close.
fresh := PBFileStorage path: (base / 'none') pathString atomCacheEntries: 0.
fresh save: (PBObject withAll: { 'i' -> 1 }).
c that: '0 disables the cache' is: fresh atomCacheSize equals: 0.
fresh close.
c that: 'a negative bound is refused' signals: PBValidationError during: [
  PBFileStorage path: (base / 'neg') pathString atomCacheEntries: -1].

"--- nothing a transaction loaded stays reachable from the cache ---"
st := PBFileStorage path: (base / 'reach') pathString.
space := PBObjectSpace storage: st.
db := space newDatabase: 'reach'.
db newTransactionDo: [:tr | | d |
  d := tr newDictionary.
  1 to: 300 do: [:k | d := d setAt: k value: k].
  tr setRootObject: 'kv' value: d].
db newTransactionDo: [:tr | | d |
  d := tr getRootObject: 'kv'.
  scanned := d keys size.
  tr setRootObject: 'kv' value: (d setAt: 1 value: -1)].
c that: 'a transaction scanned the whole tree, then wrote one key' is: scanned equals: 300.
reached := OrderedCollection new.
gens := ((st instVarNamed: 'atomCache') instVarNamed: 'cell') value.
{ gens at: 1. gens at: 2 } do: [:g | g do: [:entry | | record |
  record := entry at: 4.
  ((record isKindOf: PBAtomEnvelope) ifTrue: [record state _values] ifFalse: [record])
    do: [:v | (v isKindOf: PBAtom) ifTrue: [reached add: v]]]].
c that: 'the cache holds references' isTrue: reached notEmpty.
c that: 'every one an unloaded stub: nothing the transactions loaded or built is reachable from it'
  is: (reached count: [:v | v isLoaded or: [(v instVarNamed: 'pointer') isNil]]) equals: 0.
space close.

"--- the byte bound ---"
st := PBFileStorage path: (base / 'bytes') pathString atomCacheEntries: 1000 atomCacheBytes: 2000.
c that: 'the byte bound is configurable' is: { st atomCacheEntries. st atomCacheBytes } equals: #(1000 2000).
c that: 'the default byte bound is 64 MiB' is: PBFileStorage defaultAtomCacheBytes equals: 67108864.
1 to: 50 do: [:i | st save: (PBObject withAll: { 'i' -> i. 's' -> (String new: 100 withAll: $x) })].
c that: 'the cache holds at most its bytes' isTrue: (st atomCacheWeight <= 2000 and: [st atomCacheWeight > 0]).
c that: 'so fewer records than were saved' isTrue: st atomCacheSize < 50.
fresh := st atomCacheSize.
st save: (PBObject withAll: { 's' -> (String new: 1500 withAll: $y) }).
c that: 'a record heavier than half the bound is not cached' isTrue: st atomCacheSize <= fresh.
c that: 'a negative byte bound is refused' signals: PBValidationError during: [
  PBFileStorage path: (base / 'negbytes') pathString atomCacheEntries: 10 atomCacheBytes: -1].
st close.

"--- a failed write empties the cache ---"
seam := SeamStorage path: (base / 'failing') pathString.
seam save: (PBObject withAll: { 'i' -> 1 }).
c that: 'a write cached its record' is: seam atomCacheSize equals: 1.
ptrs := seam save: (PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> PBDictionary new })).
seam failOn: #_syncDirectory call: 1.
seam tryLockRoot.
c that: 'a publish whose directory sync fails' signals: PBUnexpectedError during: [
  seam replaceRoot: (PBRootRecord segment: ptrs segmentBytes offset: ptrs offset epoch: 1)].
c that: 'fails the storage' is: seam isFailed equals: true.
c that: 'and empties the cache' is: seam atomCacheSize equals: 0.
seam close.
base deleteAll.
c report displayNl.

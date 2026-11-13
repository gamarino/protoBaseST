"EXPECT: ok 4"
"The bytes a fixed workload writes are pinned: the SHA-256 of each segment and of space.root
 after the same transactions must stay what they were when the performance work of
 2026-11-13 began (commit 7ef11d7). The work changes how records are saved, encoded,
 verified and cached, never what is written, so the format cannot drift unnoticed. Every
 source of variation is fixed: the oids (the seam PBAtom >> _newOid), the segment name (the
 seam newSegmentId), the clock (DateTime nowUTC) and the database origin (UUID new).

 The workload: a database made by the publisher; one transaction with every kind of root
 (a Dictionary of 60 Integer keys; a Dictionary of records holding every scalar kind of the
 codec, a NaN with a payload, -0.0 and a TimeOfDay among them, and a reference inside a
 list; a List, a Set, a CountedSet, a HashDictionary, a mutable cell, a record referring to
 another); 30 tiny commits (one key each); 10 record updates (3 fields each); 3 batches of
 100 keys; a blind write merged into a root; a removal; a cell write. Segments roll over at
 64 KiB, so the space spans three. The digests were taken with the source of 7ef11d7 and
 hold unchanged on the source after the work."
Import from: 'protobase'.
Import from: 'decimal'.
Import from: 'calendar'.
Import from: 'uuid'.
Import from: '_check'.

PBFileStorage subclass: #PinnedStorage.
PinnedStorage >> newSegmentId
  ^ UUID fromString: '5a5a5a5a5a5a4a5a8a5a5a5a5a5a5a' , PinnedSeeds nextSegment.

Object subclass: #PinnedSeeds classVariableNames: 'Oid Clock Uuid Segment'.
PinnedSeeds class >> nextSegment
  Segment := (Segment ifNil: [0]) + 1.
  ^ Segment < 16 ifTrue: ['0' , (Segment printString: 16) asLowercase] ifFalse: [(Segment printString: 16) asLowercase].
PinnedSeeds class >> nextOid
  Oid := (Oid ifNil: [0]) + 1.
  ^ ByteArray withAll: ((1 to: 16) asArray collect: [:i | (Oid bitShift: (16 - i) * -8) bitAnd: 255]).
PinnedSeeds class >> nextClock
  Clock := (Clock ifNil: [0]) + 1.
  ^ DateTime utcOrdinalMicroseconds: 63900000000000000 + (Clock * 1000000) zone: ZoneOffset utc.
PinnedSeeds class >> nextUuid
  Uuid := (Uuid ifNil: [0]) + 1.
  ^ UUID fromBytes: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | i = 7 ifTrue: [16r40] ifFalse: [i = 9 ifTrue: [16r80] ifFalse: [Uuid]]])).

PBAtom >> _newOid
  ^ PinnedSeeds nextOid.
DateTime class >> nowUTC
  ^ PinnedSeeds nextClock.
UUID class >> new
  ^ PinnedSeeds nextUuid.

| c base dir space db records digest segs |
c := Check new.
base := FileSystem temp / ('pbst-bytes-pinned-' , Smalltalk pid printString).
base deleteAll.
dir := base / 'space'.
"Segments roll over at 64 KiB, so the space spans several."
space := PBObjectSpace storage: (PinnedStorage path: dir pathString segmentMaxBytes: 65536).
[db := space newDatabase: 'pin'.
 db newTransactionDo: [:tr | | kv recs other |
   kv := tr newDictionary.
   1 to: 60 do: [:i | kv := kv setAt: i value: i * 7].
   tr setRootObject: 'kv' value: kv.
   other := tr newObject: { 'name' -> 'other'. 'n' -> 1 }.
   recs := tr newDictionary.
   0 to: 19 do: [:r |
     recs := recs setAt: r value: (tr newObject: {
       'name' -> ('account ' , r printString). 'balance' -> 0. 'hits' -> 0. 'stamp' -> 0.
       'ratio' -> (r / 4) asFloat. 'big' -> (2 raisedTo: 70 + r). 'neg' -> r negated.
       'flag' -> r even. 'none' -> nil. 'blob' -> (ByteArray withAll: { r. 255 - r }).
       'price' -> (Decimal fromString: r printString , '.25'). 'day' -> (CalendarDate year: 2026 month: 11 day: r + 1).
       'when' -> (DateTime utcOrdinalMicroseconds: 63900000000000000 + r zone: ZoneOffset utc).
       'span' -> (TimeSpan microseconds: r * 1000). 'id' -> (UUID fromString: '0123456789abcdef0123456789abcd' , (r + 16) printString).
       'pair' -> (PBTuple withAll: { r. 'x' }). 'list' -> { 1. { 2. 3 } }. 'map' -> (PBFrozenDict withAssociations: { 'k' -> r }).
       'ref' -> other. 'refs' -> { other. r }.
       'nan' -> (PBCodec decode: (Check bytes: 'cb7ff8000000000001')). 'negzero' -> (PBCodec decode: (Check bytes: 'cb8000000000000000')).
       'clock' -> (TimeOfDay hour: r minute: 30 second: 0 microsecond: r fold: 0 zone: ZoneOffset utc) })].
   tr setRootObject: 'records' value: recs.
   tr setRootObject: 'list' value: ((tr newList appendLast: 'a') appendLast: 2).
   tr setRootObject: 'set' value: ((tr newSet add: 'a') add: 3).
   tr setRootObject: 'cset' value: (((tr newCountedSet add: 'a') add: 'a') add: 'b').
   tr setRootObject: 'hd' value: ((tr newHashDictionary setAt: 'h' value: 1) setAt: 2 value: 'two').
   tr newMutable: 'cell' value: 0].
 1 to: 30 do: [:i | db run: [:tr | tr setRootObject: 'kv' value: ((tr getRootObject: 'kv') setAt: 100 + i value: i)]].
 1 to: 10 do: [:i | db run: [:tr | | recs rec |
   recs := tr getRootObject: 'records'.
   rec := recs getAt: i \\ 20.
   rec := rec withAll: { 'balance' -> ((rec at: 'balance') + i). 'hits' -> ((rec at: 'hits') + 1). 'stamp' -> i }.
   tr setRootObject: 'records' value: (recs setAt: i \\ 20 value: rec)]].
 1 to: 3 do: [:i | db run: [:tr | | d |
   d := tr getRootObject: 'kv'.
   1000 * i + 1 to: 1000 * i + 100 do: [:k | d := d setAt: k value: k \\ 97].
   tr setRootObject: 'kv' value: d]].
 db run: [:tr | tr setRootObject: 'hd' value: (tr newHashDictionary setAt: 'blind' value: true)].
 db run: [:tr | tr setRootObject: 'kv' value: ((tr getRootObject: 'kv') removeAt: 1)].
 db run: [:tr | tr setMutable: 'cell' value: 42]]
  ensure: [space close].

digest := [:file | file binaryContents sha256 hex asLowercase].
segs := ((dir files select: [:f | f basename endsWith: '.seg']) asArray) sorted: [:a :b | a basename <= b basename].
c that: 'several segments, the pinned names' is: (segs collect: [:f | f basename]) equals: #('5a5a5a5a5a5a4a5a8a5a5a5a5a5a5a01.seg' '5a5a5a5a5a5a4a5a8a5a5a5a5a5a5a02.seg' '5a5a5a5a5a5a4a5a8a5a5a5a5a5a5a03.seg').
c that: 'the segment bytes' is: (segs collect: [:f | digest value: f]) equals: #('94cdd14fc6ab3b97ef1cfbda985ec5d2ef80100863529adda88c6ae1fb54f21a'
  'd653b38dfa9c5f36b85bf9334a28909dd672203f7be61c40d5dcba49c8da7450'
  '5827569eff91d29a09174a03e6a0f0b4d5c8cd2716cb5de4aaf6a65218277961').
c that: 'the root bytes' is: (digest value: dir / 'space.root') equals: '233b7658ddee26e7b979290eb62997e79e9f835cf2e560614636fb2ff9c8cedd'.
c that: 'the read back' is: [| s | s := PBObjectSpace storage: (PBFileStorage path: dir pathString).
  [| tr | tr := (s openDatabase: 'pin') newTransaction.
   { (tr getRootObject: 'kv') keys size. ((tr getRootObject: 'records') getAt: 10) at: 'hits'. tr getMutable: 'cell' }]
    ensure: [s close]] value equals: #(389 1 42).
base deleteAll.
c report displayNl.

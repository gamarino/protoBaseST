"_st_every_record.st: protoST's side of st_every_record_to_py.sh.

  protost _st_every_record.st <dir> <out>

 Commits a workload through the transaction API (every root kind, every scalar kind of the
 codec, a reference inside a list, record updates, batches; segments roll over at 16 KiB).
 Then it writes two records raw, as a format-3 writer would (a format-3 zone datetime, an
 instant within a day of year 1), and copies each forward (PBObject >> withAll:) and around
 a tree write: every such save must be refused. Last, it lists every record of every segment
 but the two raw ones in <out>, one 'segment-hex offset' per line, and prints 'written'.
 Any failure is an error (a non-zero exit)."
Import from: 'protobase'.
Import from: 'decimal'.
Import from: 'calendar'.
Import from: 'uuid'.

PBAtomEnvelope subclass: #RawEnvelope.
RawEnvelope >> encode
  | ref |
  ref := PBCodec pointerRef.
  ^ MessagePack encode: (MessagePackMap withAll: {
    't' -> (PBTypeRegistry writerTag: self tag). 'oid' -> self oid.
    's' -> (MessagePackMap withAll: (self state associations collect: [:each |
      each key -> (PBCodec _wire: each value ref: ref)])) }).

| args dir out st space db raw skip refused leg inst p d dstub node pn pd lines |
args := Smalltalk arguments.
dir := args at: 1.
out := args at: 2.
st := PBFileStorage path: dir segmentMaxBytes: 16384.
space := PBObjectSpace storage: st.
db := space newDatabase: 'every'.
db newTransactionDo: [:tr | | kv recs other |
  kv := tr newDictionary.
  1 to: 60 do: [:i | kv := kv setAt: i value: i * 7].
  tr setRootObject: 'kv' value: kv.
  other := tr newObject: { 'name' -> 'other' }.
  recs := tr newDictionary.
  0 to: 9 do: [:r |
    recs := recs setAt: r value: (tr newObject: {
      'name' -> ('account ' , r printString). 'balance' -> 0. 'ratio' -> (r / 4) asFloat. 'big' -> (2 raisedTo: 70 + r).
      'flag' -> r even. 'none' -> nil. 'blob' -> (ByteArray withAll: { r. 255 - r }).
      'price' -> (Decimal fromString: r printString , '.25'). 'day' -> (CalendarDate year: 2026 month: 11 day: r + 1).
      'when' -> (DateTime utcOrdinalMicroseconds: 63900000000000000 + r zone: ZoneOffset utc).
      'span' -> (TimeSpan microseconds: r * 1000). 'id' -> UUID new.
      'clock' -> (TimeOfDay hour: r minute: 30 second: 0 microsecond: r fold: 0 zone: ZoneOffset utc).
      'pair' -> (PBTuple withAll: { r. 'x' }). 'list' -> { 1. { 2. 3 } }. 'map' -> (PBFrozenDict withAssociations: { 'k' -> r }).
      'ref' -> other. 'refs' -> { other. r } })].
  tr setRootObject: 'records' value: recs.
  tr setRootObject: 'list' value: ((tr newList appendLast: 'a') appendLast: other).
  tr setRootObject: 'set' value: ((tr newSet add: 'a') add: 3).
  tr setRootObject: 'cset' value: ((tr newCountedSet add: 'a') add: 'a').
  tr setRootObject: 'hd' value: (tr newHashDictionary setAt: 'h' value: other).
  tr newMutable: 'cell' value: 0].
1 to: 20 do: [:i | db run: [:tr | tr setRootObject: 'kv' value: ((tr getRootObject: 'kv') setAt: 100 + i value: i)]].
1 to: 10 do: [:i | db run: [:tr | | recs rec |
  recs := tr getRootObject: 'records'.
  rec := recs getAt: i \\ 10.
  rec := rec withAll: { 'balance' -> ((rec at: 'balance') + i) }.
  tr setRootObject: 'records' value: (recs setAt: i \\ 10 value: rec)]].
1 to: 3 do: [:i | db run: [:tr | | d1 |
  d1 := tr getRootObject: 'kv'.
  1000 * i + 1 to: 1000 * i + 100 do: [:k | d1 := d1 setAt: k value: k \\ 97].
  tr setRootObject: 'kv' value: d1]].
db run: [:tr | tr setMutable: 'cell' value: 42].

"Values a reader accepts and a writer must refuse, written raw, then copied forward."
skip := OrderedCollection new.
raw := [:aClass :aState | | ptr |
  ptr := st pushAtom: (RawEnvelope basicNew _setTag: (PBTypeRegistry tagFor: aClass) oid: _PBOidPool next
    state: (PBFrozenDict withAssociations: aState)).
  skip add: ptr.
  ptr].
refused := [:label :aBlock |
  [aBlock value. ^ Error signal: label , ': the save was not refused'] on: PBDBError do: [:e | nil]].
leg := PBLegacyZoneDateTime wallClockFields: #(2020 1 1 0 0 0 0) fold: 0 zoneName: (ZoneName key: 'Europe/Madrid').
inst := DateTime utcFields: #(1 1 1 0 0 0 0) zoneName: (ZoneName key: 'America/New_York').
{ leg. inst } do: [:v |
  p := raw value: PBObject value: { 'when' -> v. 'n' -> 1 }.
  st flushSegment.
  refused value: 'withAll: of ' , v printString value: [st save: ((PBObject unloadedAt: p storage: st) withAll: { 'n' -> 2 })]].
d := (PBDictionary new setAt: 1 value: 'PLACEHOLDER') setAt: 0 value: 'zero'.
dstub := PBDictionary unloadedAt: (st save: d) storage: st.
node := dstub stateAt: 'root'.
pn := raw value: node class value: (node state associations collect: [:each |
  each key -> ((each value = 'PLACEHOLDER') ifTrue: [leg] ifFalse: [each value])]).
pd := raw value: PBDictionary value: (dstub state associations collect: [:each |
  each key -> (each key = 'root' ifTrue: [node class unloadedAt: pn storage: st] ifFalse: [each value])]).
st flushSegment.
refused value: 'a tree write around a format-3 value' value: [st save: ((PBDictionary unloadedAt: pd storage: st) setAt: 2 value: 'two')].
st flushSegment.

lines := WriteStream on: String new.
((dir asFileReference files select: [:f | f basename endsWith: '.seg']) asArray) do: [:f | | hex |
  hex := f basename copyFrom: 1 to: 32.
  (st recordsOfSegment: hex) do: [:r | | off |
    off := r at: 1.
    (skip anySatisfy: [:ptr | ptr segmentHex = hex and: [ptr offset = off]]) ifFalse: [
      lines nextPutAll: hex; nextPutAll: ' '; nextPutAll: off printString; nextPut: Character lf]]].
out asFileReference contents: lines contents.
space close.
'written' displayNl.

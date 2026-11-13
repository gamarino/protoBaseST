"EXPECT: ok 11"
"A save refuses every value a writer may not write, wherever it came from (review C1 of the
 commit performance work). A reader accepts values a writer must refuse: a format-3
 ['zone', key] datetime (PBLegacyZoneDateTime), an instant within one day of year 1 or
 9999 (D58). Such a value reaches a new atom without being made canonical when a decoded
 record is copied forward: PBObject >> withAll: keeps the fields it does not change, and a
 tree write rebuilds the nodes around a stored value. The save must still refuse it, with
 the codec's text, before anything is written.

 The records holding them are written raw (RawEnvelope), as a format-3 writer or a damaged
 writer would."
Import from: 'protobase'.
Import from: 'calendar'.
Import from: '_check'.

"An envelope whose payload is the wire form of its state as is, unchecked."
PBAtomEnvelope subclass: #RawEnvelope.
RawEnvelope >> encode
  | ref |
  ref := PBCodec pointerRef.
  ^ MessagePack encode: (MessagePackMap withAll: {
    't' -> (PBTypeRegistry writerTag: self tag). 'oid' -> self oid.
    's' -> (MessagePackMap withAll: (self state associations collect: [:each |
      each key -> (PBCodec _wire: each value ref: ref)])) }).

| c base st leg inst raw p1 p2 segSize rec d dstub node nodeState newNode pn pd sizeBefore |
c := Check new.
base := FileSystem temp / ('pbst-save-refuses-' , Smalltalk pid printString).
base deleteAll.
st := PBFileStorage path: base pathString.
leg := PBLegacyZoneDateTime wallClockFields: #(2020 1 1 0 0 0 0) fold: 0 zoneName: (ZoneName key: 'Europe/Madrid').
inst := DateTime utcFields: #(1 1 1 0 0 0 0) zoneName: (ZoneName key: 'America/New_York').
raw := [:aClass :aState |
  st pushAtom: (RawEnvelope basicNew _setTag: (PBTypeRegistry tagFor: aClass) oid: _PBOidPool next
    state: (PBFrozenDict withAssociations: aState))].
segSize := [(base / (st currentSegment hex asLowercase , '.seg')) size].

"--- copied forward by withAll: ---"
p1 := raw value: PBObject value: { 'when' -> leg. 'n' -> 1 }.
p2 := raw value: PBObject value: { 'when' -> inst. 'n' -> 1 }.
st flushSegment.
c that: 'the reader accepts a format-3 zone datetime' isTrue:
  (((PBObject unloadedAt: p1 storage: st) at: 'when') isKindOf: PBLegacyZoneDateTime).
rec := (PBObject unloadedAt: p1 storage: st) withAll: { 'n' -> 2 }.
sizeBefore := segSize value.
c that: 'a copied-forward format-3 zone datetime is refused at the save' signals: PBValidationError
  containing: 'Attribute ''when'': PBCodec: the format-3 zone datetime' during: [st save: rec].
c that: 'and nothing was written' is: segSize value equals: sizeBefore.
c that: 'the record stays unsaved' is: rec isSaved equals: false.
rec := (PBObject unloadedAt: p2 storage: st) withAll: { 'n' -> 2 }.
c that: 'a copied-forward instant near year 1 is refused at the save' signals: PBNotSupportedError
  containing: 'lies within one day of year 1' during: [st save: rec].
c that: 'and nothing was written either' is: segSize value equals: sizeBefore.

"--- copied forward by a tree rebuild ---"
d := (PBDictionary new setAt: 1 value: 'PLACEHOLDER') setAt: 0 value: 'zero'.
pd := st save: d.
dstub := PBDictionary unloadedAt: pd storage: st.
"Every node of the stored tree written again raw, the placeholder replaced by the legacy value."
node := dstub stateAt: 'root'.
nodeState := node state associations collect: [:each |
  each key -> ((each value = 'PLACEHOLDER') ifTrue: [leg] ifFalse: [each value])].
c that: 'the placeholder sits in the root node' isTrue: (nodeState anySatisfy: [:each | each value == leg]).
pn := raw value: node class value: nodeState.
pd := raw value: PBDictionary value: (dstub state associations collect: [:each |
  each key -> (each key = 'root' ifTrue: [node class unloadedAt: pn storage: st] ifFalse: [each value])]).
st flushSegment.
dstub := PBDictionary unloadedAt: pd storage: st.
c that: 'the stored tree reads the legacy value' isTrue: ((dstub getAt: 1) isKindOf: PBLegacyZoneDateTime).
newNode := dstub setAt: 2 value: 'two'.
sizeBefore := segSize value.
c that: 'a tree write that rebuilds the node holding it is refused at the save' signals: PBValidationError
  containing: 'the format-3 zone datetime' during: [st save: newNode].
"Its dependents, saved first (dependents first, as before), are written; it is not: nothing
 refers to them."
c that: 'the refused record is not saved' is: newNode isSaved equals: false.

"--- what a writer may write is still written ---"
c that: 'a valid record saves' isTrue: (st save: (PBObject withAll: { 'when' -> (DateTime utcOrdinalMicroseconds: 63900000000000000 zone: ZoneOffset utc) })) notNil.
st close.
base deleteAll.
c report displayNl.

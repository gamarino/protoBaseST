"EXPECT: ok 20"
"The save-dependents-first invariant (plan Task 15; ProtoBase Atom._save): the save writes
 every atom a record refers to (attribute values, map keys, collection nodes and boxes)
 before the record itself, so every reference in a written record points to an earlier
 record and never to itself or forward. Records written by protoBaseST (a record keyed by
 another record, a dictionary keyed by records, a chain of three records, a list of
 records, and a record saved later that refers to saved ones) are walked with
 PBFileStorage recordsOfSegment:, and every @ref in each record must point to a lower
 offset of the segment. Each atom is written once, with the oid it drew in memory (D21:
 drawn by the save when no need drew it before), and records its place: a second save
 writes nothing. The records read back as written. A class that is not registered is
 refused when saved, as ProtoBase refuses a class with no declared type name. The file
 storage's write side is plan Task 17: the records go to the SegmentSink double
 (_sink.st), whose segment file is then opened with PBFileStorage."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_sink'.

PBObject subclass: #Unregistered.
Unregistered class >> typeName
  ^ 'tests.dependents.Unregistered'.

| c seg sink k r k2 k3 d cc bb aa r1 r2 r3 l late drawn base st records refs forward oids walk
  loaded count before |
c := Check new.
seg := ByteArray fromHex: '0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e'.
sink := SegmentSink segment: seg.

"A record keyed by another record."
k := PBObject withAll: { 'k' -> 1 }.
r := PBObject withAll: { 'm' -> (PBFrozenDict withAssociations: { k -> 'v' }) }.
drawn := k oid.
r _saveInto: sink.
c that: 'the key record is written first' isTrue: k pointer offset < r pointer offset.
c that: 'with the oid it drew in memory' is: k oid equals: drawn.
"A dictionary keyed by records."
k2 := PBObject withAll: { 'k' -> 2 }.
k3 := PBObject withAll: { 'k' -> 3 }.
d := (PBDictionary new setAt: k2 value: 'two') setAt: k3 value: 'three'.
d _saveInto: sink.
c that: 'k2 and k3 saved before the dictionary' isTrue: (k2 pointer offset < d pointer offset and: [k3 pointer offset < d pointer offset]).
"A chain of three records."
cc := PBObject withAll: { 'n' -> 3 }.
bb := PBObject withAll: { 'n' -> 2. 'next' -> cc }.
aa := PBObject withAll: { 'n' -> 1. 'next' -> bb }.
c that: 'no oid drawn before the save' is: aa knownOid equals: nil.
aa _saveInto: sink.
c that: 'the chain is written tail first' isTrue: (cc pointer offset < bb pointer offset and: [bb pointer offset < aa pointer offset]).
c that: 'the save drew the oid' isTrue: aa knownOid notNil.
"A list of records (and a large value, boxed)."
r1 := PBObject withAll: { 'i' -> 1 }.
r2 := PBObject withAll: { 'i' -> 2 }.
r3 := PBObject withAll: { 'i' -> 3 }.
l := (PBList new extend: { r1. r2. r3 }) appendLast: (String new: 300 withAll: $z).
l _saveInto: sink.
"A record saved later, referring to records saved before."
late := PBObject withAll: { 'refs' -> { aa. k. r2 } }.
before := sink offsets size.
late _saveInto: sink.
c that: 'only the new record is written' is: sink offsets size equals: before + 1.
c that: 'a second save writes nothing' is: (aa _saveInto: sink; yourself) pointer equals: aa pointer.
c that: 'and pushes no record' is: sink offsets size equals: before + 1.
c that: 'an unregistered class is refused' signals: PBValidationError containing: 'Unregistered'
  during: [(Unregistered withAll: { 'x' -> 1 }) _saveInto: sink].
c that: 'and nothing was written' is: sink offsets size equals: before + 1.

"Walk the segment: every @ref points to a lower offset."
base := FileSystem temp / ('pbst-dependents-' , Smalltalk pid printString).
base deleteAll.
st := PBFileStorage path: (sink writeTo: base).
records := st recordsOfSegment: seg.
c that: 'one record per atom pushed' is: records size equals: sink offsets size.
refs := 0.
forward := OrderedCollection new.
oids := Set new.
walk := nil.
walk := [:tree :offset |
  (tree isKindOf: MessagePackMap)
    ifTrue: [
      (tree size = 1 and: [tree associations first key = '@ref'])
        ifTrue: [
          | body |
          body := tree associations first value.
          refs := refs + 1.
          ((body at: 1) = seg and: [(body at: 2) >= offset]) ifTrue: [forward add: offset -> (body at: 2)]]
        ifFalse: [tree associations do: [:each | walk value: each key value: offset. walk value: each value value: offset]]]
    ifFalse: [(tree isKindOf: Array) ifTrue: [tree do: [:each | walk value: each value: offset]]]].
records do: [:rec |
  | map |
  map := MessagePack decodeOrdered: (rec at: 3).
  oids add: (map at: 't' ifAbsent: [nil]) printString , (map at: 'oid' ifAbsent: [nil]) hex.
  walk value: (map at: 's' ifAbsent: [nil]) value: (rec at: 1)].
"Counted by hand: 1 in r, 5 in d (2 nodes, the dictionary), 2 in the chain, 9 in the list
 (4 nodes, the list), 3 in late."
c that: 'every reference was checked' is: refs equals: 20.
c that: 'no reference to itself or forward' is: forward asArray equals: #().
c that: 'each atom written once (distinct oids)' is: oids size equals: records size.
"Read back."
loaded := PBTypeRegistry unloadedAtomFor: 19 at: aa pointer storage: st.
c that: 'the chain reads back' is: (((loaded at: 'next') at: 'next') at: 'n') equals: 3.
c that: 'with the oid of the record in memory' is: loaded oid equals: aa oid.
c that: 'the stored map key finds the record' is: (((PBTypeRegistry unloadedAtomFor: 19 at: r pointer storage: st) at: 'm') at: k) equals: 'v'.
count := (PBTypeRegistry unloadedAtomFor: 5 at: l pointer storage: st).
c that: 'the list reads back' is: ((count elements copyFrom: 1 to: 3) collect: [:each | each at: 'i']) equals: #(1 2 3).
c that: 'its stored tree is valid' is: (PBAvl check: (count stateAt: 'root')) notNil equals: true.
st close.
base deleteAll.
c report displayNl.

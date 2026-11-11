"EXPECT: ok 23"
"PBNotation at the value nesting limit (format spec v2.0.0rc2, 'Value nesting depth'; plan
 Task 17b fix round 1, review I1): describe:, build:, describeObject: and describeRaw: walk
 with explicit stacks, as ProtoBase's tools/notation.py, so 1022 lists, 511 tuples and 340
 maps are described and built back, a record holding 1022 lists and a chain of 1100 records
 are described, and a raw record 1024 containers deep is described, on the main thread and
 inside an actor. Descriptions are never compared by = or printString (both would recurse):
 a description is checked by building it back and comparing the bytes, or by following it
 down with a loop."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

"Follows a description down through the first item of each container description, with a
 loop: answers { levels. the leaf description's kind }."
Object subclass: #Descent.
Descent class >> of: aDescription
  | d levels kind |
  d := aDescription.
  levels := 0.
  [kind := d keys asArray first.
   #('list' 'tuple' 'array') includes: kind] whileTrue: [
    levels := levels + 1.
    d := (d at: kind) first].
  ^ { levels. kind }.

Object subclass: #NotationWorker.
"Whether aValue describes and builds back to its own bytes, on this actor's thread."
NotationWorker >> roundTrips: aValue
  ^ (PBCodec encode: (PBNotation build: (PBNotation describe: aValue))) = (PBCodec encode: aValue).
NotationWorker >> describeObjectOf: anObject
  ^ Descent of: (((PBNotation describeObject: anObject) at: 'attrs') first at: 2).
NotationWorker >> describeRaw: aByteArray
  ^ Descent of: (PBNotation describeRaw: (MessagePack decodeOrdered: aByteArray strictKeys: false)).

| c nest lists tuples maps roundTrips record chain d n raw worker json shallow deepText base b ref dumped |
c := Check new.
nest := [:k :seed :wrap | | v | v := seed. k timesRepeat: [v := wrap value: v]. v].
lists := PBCodec canonical: (nest value: 1022 value: 1 value: [:v | Array with: v]).
tuples := nest value: 511 value: 1 value: [:v | PBTuple withAll: { v }].
maps := nest value: 340 value: 1 value: [:v | PBFrozenDict withAssociations: { 'k' -> v }].
roundTrips := [:v | (PBCodec encode: (PBNotation build: (PBNotation describe: v))) = (PBCodec encode: v)].

c that: 'describe: of 1022 lists, followed down' is: (Descent of: (PBNotation describe: lists)) equals: #(1022 'int').
c that: '1022 lists: describe: then build: gives the bytes' isTrue: (roundTrips value: lists).
c that: '511 tuples: describe: then build:' isTrue: (roundTrips value: tuples).
c that: '340 maps: describe: then build:' isTrue: (roundTrips value: maps).
c that: 'a map keyed by 509 tuples: describe: then build:' isTrue: (roundTrips value:
  (PBFrozenDict withAssociations: { (nest value: 509 value: 1 value: [:v | PBTuple withAll: { v }]) -> 'v' })).
c that: 'a malformed description deep down is still refused' signals: PBValidationError containing: 'unknown kind'
  during: [PBNotation build: (nest value: 1000 value: (Dictionary new at: 'nope' put: 1; yourself)
    value: [:v | Dictionary new at: 'list' put: { v }; yourself])].
c that: 'an unstorable value deep down is still refused' signals: PBValidationError containing: 'no description'
  during: [PBNotation describe: (PBFrozenList withAll: { nest value: 1000 value: Object new value: [:v | PBFrozenList withAll: { v }] })].

"describeObject: a record holding 1022 lists, and a chain of 1100 records (each the 'next' of
 the one before), which nests records, not values."
record := PBObject withAll: { 'v' -> lists }.
d := PBNotation describeObject: record.
c that: 'describeObject: of a record: its kind' is: (d at: 'object') equals: 'proto_db.core.dbobject.DBObject'.
c that: 'describeObject: of a record holding 1022 lists' is: (Descent of: ((d at: 'attrs') first at: 2)) equals: #(1022 'int').
chain := PBObject withAll: { 'next' -> nil }.
1100 timesRepeat: [chain := PBObject withAll: { 'next' -> chain }].
d := PBNotation describeObject: chain.
n := 0.
[(d includesKey: 'object')] whileTrue: [n := n + 1. d := (d at: 'attrs') first at: 2].
c that: 'describeObject: of a chain of 1101 records' is: n equals: 1101.
c that: 'the end of the chain' is: (d at: 'nil' ifAbsent: [#absent]) equals: nil.
c that: 'describeObject: of a PBList whose element is 1022 lists' is:
  (Descent of: (((PBNotation describeObject: (PBList new appendLast: lists)) at: 'elements') first)) equals: #(1022 'int').
c that: 'describeObject: of a PBDictionary from 511 tuples' is:
  (Descent of: ((((PBNotation describeObject: (PBDictionary new setAt: tuples value: 1)) at: 'items') first) at: 1))
  equals: #(511 'int').

"describeRaw: a record payload is up to 1024 containers deep."
raw := (ByteArray withAll: ((1 to: 1024) asArray collect: [:i | 16r91])) , (ByteArray withAll: #(1)).
c that: 'describeRaw: of 1024 nested arrays' is: (Descent of: (PBNotation describeRaw: (MessagePack decodeOrdered: raw strictKeys: false)))
  equals: #(1024 'int').
c that: 'describeRaw: of a map holding 1023 arrays' is: (Descent of: ((((PBNotation describeRaw: (MessagePack decodeOrdered:
    ((ByteArray fromHex: '81a176') , (raw copyFrom: 2 to: raw size)) strictKeys: false)) at: 'mpmap') first) at: 2))
  equals: #(1023 'int').

"jsonText: writes stringify:'s text with an explicit stack, so dumpSpace:to: writes a database
 holding 1022 lists (two JSON levels per list)."
json := Import from: 'json'.
shallow := Dictionary new.
shallow at: 'a' put: { 1. 'x"y'. nil. true. 2.5. Dictionary new. #() }; at: 'b' put: (OrderedCollection with: -3).
c that: 'jsonText: of a shallow value is stringify:''s text' is: (PBNotation jsonText: shallow) equals: (json JSON stringify: shallow).
deepText := ((1 to: 1022) inject: '' into: [:s :i | s , '{"list":[']) , '{"int":"1"}'
  , ((1 to: 1022) inject: '' into: [:s :i | s , ']}']).
c that: 'jsonText: of the description of 1022 lists' is: (PBNotation jsonText: (PBNotation describe: lists)) equals: deepText.
base := FileSystem temp / ('pbst-notation-depth-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
b := SpaceBuilder segment: (ByteArray fromHex: '3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d').
ref := b add: 19 oid: 1 state: { 'v' -> lists }.
dumped := PBObjectSpace storage: (PBFileStorage path: (b writeTo: base / 'deep'
  root: (b spaceWithDatabase: 'db' roots: { 'deep' -> ref } mutables: #() oids: 10))).
PBNotation dumpSpace: dumped to: base / 'dump.json'.
dumped close.
c that: 'dumpSpace:to: of a record holding 1022 lists' isTrue: ((base / 'dump.json') contents includesSubstring: deepText).
base deleteAll.

"On a worker thread."
worker := NotationWorker new asActor.
c that: 'an actor: 1022 lists' isTrue: (worker roundTrips: lists) wait.
c that: 'an actor: 511 tuples' isTrue: (worker roundTrips: tuples) wait.
c that: 'an actor: 340 maps' isTrue: (worker roundTrips: maps) wait.
c that: 'an actor: describeObject: of a record holding 1022 lists' is: (worker describeObjectOf: record) wait equals: #(1022 'int').
c that: 'an actor: describeRaw: of 1024 nested arrays' is: (worker describeRaw: raw) wait equals: #(1024 'int').
c report displayNl.

"_queries.st: the seeded data sets and the scan oracle of the indexed-queries tests (plan call
 IP4; a helper: the runner never runs files whose name starts with _).

  QData people: n seed: s     n records (PBObject) with id (0..n-1), name, city and age: a city is
                              absent in about one record in ten and nil in one in ten; an age is an
                              Integer, a Float or a Decimal (equal numbers of different types
                              occur), absent in about one in ten and nil in one in twenty
  QData values: n seed: s     n values of every rank, as proto_db's index contract draws them
                              (tests/contracts/index_contract.py mixed_value): numbers of every type
                              (1, 1.0, Decimal 1, Decimal 1.00, 0.0, -0.0 among them), Strings,
                              nil, Booleans, ByteArrays, dates, instants in several offsets,
                              tuples, records, and the unorderable values (lists, maps, NaN, a
                              tuple holding a list)
  QData pinOids: aValues       gives each record among aValues the oid of 15 zero bytes then its r,
                              before anything draws one, so atoms (ordered by oid) order the same
                              way in every run and in proto_db (tests/interop/py_term_cases.py)
  QData scan: aCollection where: aBlock
                              the oracle: the elements for which aBlock answers true, as a counted
                              bag, a Dictionary from PBMemberKeys identityOf: to the occurrences
  QData bagOf: aCollection    the same bag of every element
  QData dump: anIndex         the index and every node of its trees, one line each in preorder:
                              class and MessagePack state, a reference to a node by its line, to
                              any other atom by its oid (node for node comparisons)
  QData strippedDump: anIndex the same with every other atom written as one placeholder (the
                              stored data without the identities, as proto_db's key-neutrality
                              test strips oids)
  QData contents: anIndex     the index's definition and totals, then every node of its key tree
                              and of each group's members tree in key order (class, key and value,
                              written as their MessagePack bytes, an atom by its oid), then the side
                              group's: equal for two indexes that hold the same entries in the
                              same order, whatever the shapes of their trees
  QData seeds: aDefault       PBST_PROP_SEEDS as a positive Integer (plan call IP16), or aDefault"
Import from: 'random'.
Import from: 'protobase'.

Object subclass: #QData instanceVariableNames: 'random records'.

QData class >> on: aSeed
  ^ self basicNew setRandom: (Random seed: aSeed).

QData >> setRandom: aRandom
  random := aRandom.
  records := (1 to: 4) asArray collect: [:i | PBObject withAll: { 'r' -> i }].

"An Integer in lo..hi from the high bits of the generator (as AvlOps between:and:)."
QData >> between: lo and: hi
  ^ lo + (random next * (hi - lo + 1)) truncated.

QData >> chance: aFloat
  ^ random next < aFloat.

QData >> pick: anArray
  ^ anArray at: (self between: 1 and: anArray size).

QData class >> people: n seed: aSeed
  | data |
  data := self on: aSeed.
  ^ (0 to: n - 1) asArray collect: [:i | data personWithId: i].

QData >> personWithId: anInteger
  | fields r |
  fields := OrderedCollection new.
  fields addLast: 'id' -> anInteger; addLast: 'name' -> ('p' , anInteger printString).
  r := random next.
  r < 0.1 ifFalse: [
    fields addLast: 'city' -> (r < 0.2 ifTrue: [nil] ifFalse: [self pick: #('Oslo' 'Rome' 'Paris' 'Lima' 'Kyiv' 'Quito')])].
  r := random next.
  r < 0.1 ifFalse: [
    fields addLast: 'age' -> (r < 0.15 ifTrue: [nil] ifFalse: [self age])].
  ^ PBObject withAll: fields asArray.

QData >> age
  | years |
  years := self between: 18 and: 40.
  ^ self pick: { years. years asFloat. Decimal fromString: years printString. years + 0.5 }.

QData class >> values: n seed: aSeed
  | data |
  data := self on: aSeed.
  ^ (1 to: n) asArray collect: [:i | data value].

"A value of almost every rank, plus the unorderable ones (index_contract.py mixed_value, with
 records and every ZoneOffset instant built in protoST)."
QData >> value
  | pick |
  pick := self between: 0 and: 16.
  pick = 0 ifTrue: [^ self between: -3 and: 5].
  pick = 1 ifTrue: [^ (self between: -3 and: 5) + (self pick: #(0.0 0.5))].
  pick = 2 ifTrue: [^ Decimal fromString: ((self between: 0 and: 5) / 2) asFloat printString].
  pick = 3 ifTrue: [^ 's' , (self between: 0 and: 4) printString].
  pick = 4 ifTrue: [^ nil].
  pick = 5 ifTrue: [^ self chance: 0.5].
  pick = 6 ifTrue: [^ ByteArray withAll: { self between: 0 and: 3 }].
  pick = 7 ifTrue: [^ CalendarDate year: 2026 month: 1 day: (self between: 1 and: 4)].
  pick = 8 ifTrue: [^ PBTuple withAll: { self between: 0 and: 2. 't' , (self between: 0 and: 1) printString }].
  pick = 9 ifTrue: [^ PBFrozenList withAll: { self between: 0 and: 2 }].
  pick = 10 ifTrue: [
    (self chance: 0.5) ifTrue: [^ PBFrozenDict withAssociations: { 'k' -> (self between: 0 and: 1) }].
    ^ self pick: {
      PBFrozenDict withAssociations: { 'a' -> 1. 'b' -> 2 }.
      PBFrozenDict withAssociations: { 'b' -> 2. 'a' -> 1 }.
      PBFrozenDict withAssociations: { 'a' -> 1.0. 'b' -> 2 } }].
  pick = 11 ifTrue: [^ Float nan].
  pick = 12 ifTrue: [^ PBTuple withAll: { PBFrozenList withAll: #(1). self between: 0 and: 1 }].
  pick = 13 ifTrue: [^ self pick: records].
  pick = 14 ifTrue: [
    ^ self pick: { 1. 1.0. Decimal fromString: '1'. Decimal fromString: '1.00'. 0.0. -0.0.
      Decimal fromString: '0E-3'. true }].
  pick = 15 ifTrue: [^ self instant].
  ^ self between: 0 and: 2.

"12:00 or 13:00 UTC on 2026-01-01, written in the offset -3, 0, 1 or 5 hours: equal instants in
 different offsets are equal keys with distinct exact tokens."
QData >> instant
  | hours offset |
  hours := 12 + (self between: 0 and: 1).
  offset := self pick: #(-3 0 1 5).
  ^ DateTime year: 2026 month: 1 day: 1 hour: hours + offset minute: 0 second: 0 microsecond: 0 fold: 0
    zone: (ZoneOffset microseconds: offset * 3600000000).

QData class >> pinOids: aValues
  aValues do: [:each |
    (each isKindOf: PBObject) ifTrue: [
      | oid |
      oid := (ByteArray new: 15) , (ByteArray withAll: { each at: 'r' }).
      ((each instVarNamed: 'oid') value: oid ifCurrent: nil) ifFalse: [
        each oid = oid ifFalse: [^ Error signal: 'QData pinOids: an oid was drawn already']]]].
  ^ aValues.

QData class >> scan: aCollection where: aBlock
  | bag |
  bag := Dictionary new.
  aCollection do: [:each |
    (aBlock value: each) ifTrue: [
      | id |
      id := PBMemberKeys identityOf: each.
      bag at: id put: (bag at: id ifAbsent: [0]) + 1]].
  ^ bag.

QData class >> bagOf: aCollection
  ^ self scan: aCollection where: [:each | true].

QData class >> dump: anIndex
  ^ self dump: anIndex identities: true.

QData class >> strippedDump: anIndex
  ^ self dump: anIndex identities: false.

QData class >> dump: anIndex identities: aBoolean
  | lines |
  lines := OrderedCollection new.
  self dumpAtom: anIndex into: lines identities: aBoolean.
  ^ lines asArray.

"Adds the line of anAtom, then those of the nodes it holds, to aLines; answers its line number."
QData class >> dumpAtom: anAtom into: aLines identities: aBoolean
  | n ref map |
  n := aLines size.
  aLines addLast: nil.
  ref := [:atom |
    ((atom isKindOf: PBNode) or: [atom isKindOf: PBValueBox])
      ifTrue: [PBCodec _tagged: '@ref' body: { 'node'. self dumpAtom: atom into: aLines identities: aBoolean }]
      ifFalse: [PBCodec _tagged: '@ref' body: { 'atom'. aBoolean ifTrue: [atom oid] ifFalse: [nil] }]].
  map := MessagePackMap withAll: (anAtom state associations collect: [:each |
    each key -> (PBCodec toWire: each value atomRef: ref)]).
  aLines at: n + 1 put: anAtom class typeName , ' ' , (MessagePack encode: map) hex.
  ^ n.

QData class >> contents: anIndex
  | out wire ref members |
  ref := [:atom | PBCodec _tagged: '@ref' body: { 'atom'. atom oid }].
  wire := [:v | (MessagePack encode: (PBCodec toWire: v atomRef: ref)) hex].
  out := OrderedCollection new.
  out addLast: { anIndex class name. anIndex state keys. anIndex name. wire value: anIndex keySpec.
    anIndex totalCount. anIndex stateAt: 'member_tokens'. anIndex side at: 2 }.
  members := [:group |
    PBAvl nodesDo: [:node |
      out addLast: { 'member'. node class name. wire value: node key. wire value: node value }] over: (group at: 1)].
  PBAvl nodesDo: [:node |
    out addLast: { 'group'. node class name. wire value: node key. node value at: 2 }.
    members value: node value] over: anIndex groups.
  out addLast: 'side'.
  members value: anIndex side.
  ^ out asArray.

QData class >> seeds: aDefault
  | text |
  text := Smalltalk getenv: 'PBST_PROP_SEEDS'.
  (text isNil or: [text isEmpty]) ifTrue: [^ aDefault].
  ((text allSatisfy: [:d | d isDigit]) and: [text asInteger > 0]) ifFalse: [
    ^ Error signal: 'PBST_PROP_SEEDS must be a positive integer, not ' , text printString].
  ^ text asInteger.

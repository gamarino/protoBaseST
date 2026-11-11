"EXPECT: ok 16"
"Records and index flags on the read path (plan Task 12, review m2 and m3).
 DBObject's behaviour names (with_, has_defined_attr) are refused in every PBObject
 subclass, also one that overrides reservedAttributeNames with names of its own,
 which are refused too. hasMemberTokens answers member_tokens == 1 as ProtoBase
 compares it: true, 1, 1.0, Decimal 1 and Decimal 1.00 count; 0, 2, a NaN, a
 string and an absent field do not. The space is built here, in a temporary
 directory named after the process id."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

PBObject subclass: #Ledger.
Ledger class >> typeName
  ^ 'acme.books.Ledger'.
Ledger class >> reservedAttributeNames
  ^ #('cached_total').
PBObjectSpace registerAtomClass: Ledger.

| c base b st load ok withName definedName ownName plain dbWith idx keySpec tokens refs n |
c := Check new.
base := FileSystem temp / ('pbst-read-records-' , Smalltalk pid printString).
base deleteAll.
b := SpaceBuilder segment: (ByteArray fromHex: '0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c').
ok := b add: 'acme.books.Ledger' oid: 1 state: { 'total' -> 3 }.
withName := b add: 'acme.books.Ledger' oid: 2 state: { 'with_' -> 1 }.
definedName := b add: 'acme.books.Ledger' oid: 3 state: { 'has_defined_attr' -> 1 }.
ownName := b add: 'acme.books.Ledger' oid: 4 state: { 'cached_total' -> 1 }.
plain := b add: 19 oid: 5 state: { 'cached_total' -> 1 }.
dbWith := b add: 19 oid: 6 state: { 'with_' -> 1 }.

keySpec := PBTuple withAll: { 'path'. 'a' }.
tokens := { true -> true. 1 -> true. 1.0 -> true. (Decimal fromString: '1') -> true.
  (Decimal fromString: '1.00') -> true. 0 -> false. 2 -> false. Float nan -> false. 'x' -> false }.
n := 10.
refs := tokens collect: [:each |
  n := n + 1.
  (b add: 14 oid: n state: { 'name' -> 'by_a'. 'key_spec' -> keySpec. 'groups' -> nil. 'side' -> nil.
    'total_count' -> 0. 'member_tokens' -> each key }) -> each value].
n := n + 1.
refs := refs copyWith: (b add: 14 oid: n state: { 'name' -> 'by_a'. 'key_spec' -> keySpec. 'groups' -> nil.
  'side' -> nil. 'total_count' -> 0 }) -> false.
b writeTo: base root: ok.
st := PBFileStorage path: base.
load := [:ref | PBTypeRegistry unloadedAtomFor: ref tag at: ref pointer storage: st].

c that: 'a Ledger without reserved names loads' is: ((load value: ok) at: 'total') equals: 3.
c that: 'Ledger with_ (DBObject''s, kept despite the override)' signals: PBCorruptionError containing: 'with_'
  during: [(load value: withName) state].
c that: 'Ledger has_defined_attr' signals: PBCorruptionError containing: 'has_defined_attr'
  during: [(load value: definedName) state].
c that: 'Ledger cached_total (its own reserved name)' signals: PBCorruptionError containing: 'cached_total'
  during: [(load value: ownName) state].
c that: 'a DBObject may hold cached_total' is: ((load value: plain) at: 'cached_total') equals: 1.
c that: 'a DBObject with_' signals: PBCorruptionError containing: 'with_' during: [(load value: dbWith) state].
refs doWithIndex: [:each :i |
  | label |
  label := i > tokens size
    ifTrue: ['no member_tokens']
    ifFalse: ['member_tokens ' , (PBNotation describe: (tokens at: i) key) printString].
  c that: label is: (load value: each key) hasMemberTokens equals: each value].
st close.
base deleteAll.
c report displayNl.

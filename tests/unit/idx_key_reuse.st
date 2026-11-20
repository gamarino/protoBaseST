"EXPECT: ok 10"
"The index writes compute each order key once (diag/index-cost): PBMemberKeys
 memberKeyAndOrderKeyOf: answers memberKeyOf: and the order key of that key (or both signal the
 same error class), PBKeys exactToken: answers an atom's constant token without encoding it (a
 stub, an opaque atom, a tag with a lone surrogate refused alike), checkDepth: fires alike with the
 reused member key, and the order key of an atom read from its 16 oid bytes as two words equals the
 byte-by-byte reading. Each check gathers its mismatches over many elements and requires none. The tree writes that take an order key (keyAt:orderKey:,
 keyPut:key:orderKey:value:nodeClass:, keyRemove:orderKey:) build the same trees as the plain
 ones; idx_keygroups checks build: against the fold of withAdded: node for node."
Import from: 'protobase'.
Import from: '_check'.

"An atom whose tag holds a lone surrogate: both token paths must refuse it (PBCodec
 _checkReference:)."
PBObject subclass: #SurrogateTagged.
SurrogateTagged >> tag
  ^ 'tests.idx_key_reuse.' , (String with: (Character value: 16rD800)).

"A storage that loads every pointer as an empty record with a fixed oid (the stubs below)."
Object subclass: #FixedOidStorage.
FixedOidStorage >> loadAt: aPointer expecting: aTag
  ^ PBAtomEnvelope tag: aTag oid: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | aPointer offset \\ 256]))
    state: (PBFrozenDict withAssociations: #()).
FixedOidStorage >> loadAt: aPointer expecting: aTag within: aChain
  ^ self loadAt: aPointer expecting: aTag.

| c atoms values fails root1 root2 keys shape outcome seg storage deep idx |
c := Check new.
"The answer of aBlock, or the class of the error it signals."
outcome := [:aBlock | [aBlock value] on: Error do: [:e | e return: e class]].
seg := ByteArray withAll: (101 to: 116) asArray.
storage := FixedOidStorage new.
atoms := (1 to: 200) asArray collect: [:i | PBObject withAll: { 'id' -> i }].
atoms := atoms , { PBCountedKeyNode key: 1 value: (PBTuple withAll: { 1. 1 }) left: nil right: nil.
  PBEqualityIndex name: 'i' path: 'a' }.
values := atoms , { nil. true. false. 0. 1. 1.0. -7. (2 raisedTo: 80). 0.5. Decimal fromString: '1.00'.
  'text'. ''. #[1 2 3]. PBMissing default. PBTuple withAll: { 1. 'a' }.
  PBTuple withAll: { PBTuple withAll: { 1. 2 }. 3 }. PBFrozenList withAll: #(1 2). PBTuple withAll: { 1. PBFrozenList withAll: #(2) }.
  PBFrozenDict withAssociations: { 'a' -> 1 }. Float nan. PBMutableObject name: 'm'.
  PBTuple withAll: { atoms first. 2 }.
  1 / 3. Float infinity. Float infinity negated. Decimal infinity: 0. Decimal infinity: 1. #sym.
  Decimal fromString: 'NaN'. CalendarDate year: 2026 month: 11 day: 19.
  DateTime year: 2026 month: 11 day: 19 hour: 12 minute: 0 second: 0 microsecond: 0 fold: 0 zone: nil.
  UUID new.
  PBTuple withAll: { 1. PBFrozenList withAll: #(2) }. PBTuple withAll: { 1. Float nan }.
  PBUnresolvedRef pointer: (PBAtomPointer segment: seg offset: 26) tag: 'tests.idx_key_reuse.Ref'.
  PBObject unloadedAt: (PBAtomPointer segment: seg offset: 40) storage: storage.
  PBOpaqueAtom named: 'tests.idx_key_reuse.Opaque' unloadedAt: (PBAtomPointer segment: seg offset: 41) storage: storage.
  SurrogateTagged withAll: { 'id' -> 1 } }.

"Each value either gives the same member key and order key both ways, or makes both ways signal
 the same error class (a Symbol, a Fraction, a reference without a resolver, a lone surrogate)."
fails := OrderedCollection new.
values do: [:v |
  | pair general |
  pair := outcome value: [PBMemberKeys memberKeyAndOrderKeyOf: v].
  general := outcome value: [{ PBMemberKeys memberKeyOf: v. PBKeys orderKey: (PBMemberKeys memberKeyOf: v) }].
  (pair isKindOf: Array) = (general isKindOf: Array)
    ifFalse: [fails add: v printString , ': ' , pair printString , ' against ' , general printString]
    ifTrue: [
      (pair isKindOf: Array)
        ifTrue: [
          (pair at: 1) = (general at: 1) ifFalse: [fails add: v printString , ' member key'].
          (pair at: 2) = (general at: 2) ifFalse: [fails add: v printString , ' order key'].
          ((pair at: 2) compareWith: (general at: 2)) = 0 ifFalse: [fails add: v printString , ' compare']]
        ifFalse: [pair == general ifFalse: [fails add: v printString , ': ' , pair name , ' against ' , general name]]]].
c that: 'memberKeyAndOrderKeyOf: answers memberKeyOf: and its order key, or the same error' is: fails asArray equals: #().
"A Symbol is the equal String in protoST (STATUS D35), so #sym is an ordinary String here."
c that: 'the negative cases signal' is: ({ 1 / 3. values at: values size - 3. values last }
  collect: [:v | outcome value: [PBMemberKeys memberKeyAndOrderKeyOf: v]])
  equals: { PBValidationError. PBNotSupportedError. PBValidationError }.

fails := OrderedCollection new.
values do: [:v |
  | slow fast |
  slow := [MessagePack encode: (PBCodec toWire: v atomRef: PBCodec tokenRef)] on: Error do: [:e | e return: e class].
  fast := [PBKeys exactToken: v] on: Error do: [:e | e return: e class].
  slow = fast ifFalse: [fails add: v printString]].
c that: 'exactToken: answers the encoded token' is: fails asArray equals: #().
c that: 'a stub, an opaque atom and an unsaved atom have the atom token' is: ({ values at: values size - 2. values at: values size - 1. atoms first }
  collect: [:v | PBKeys exactToken: v]) equals: { PBKeys atomToken. PBKeys atomToken. PBKeys atomToken }.
c that: 'an atom''s token is {''@ref'': nil}' is: (PBKeys exactToken: atoms first) equals: (MessagePack encode: (PBCodec toWire: atoms first atomRef: PBCodec tokenRef)).

fails := OrderedCollection new.
(atoms collect: [:a | PBKeys _oidBytes: a oid]) , { ByteArray withAll: ((1 to: 16) asArray collect: [:i | 255]). ByteArray withAll: ((1 to: 16) asArray collect: [:i | 0]). #[1 2 3] } do: [:b |
  | slow |
  slow := 0.
  b do: [:x | slow := slow * 256 + x].
  (PBKeys _unsignedBigEndian: b) = slow ifFalse: [fails add: b printString]].
c that: 'oid bytes read as two words equal the bytes read one by one' is: fails asArray equals: #().

"An element whose member key would nest too deep: checkDepth: refuses it with the same sentence
 whether it is given the member key memberKeyAndOrderKeyOf: answers or computes one itself."
deep := 7.
300 timesRepeat: [deep := PBFrozenList withAll: { deep }].
idx := PBEqualityIndex name: 'deep' path: 'a'.
c that: 'checkDepth: fires alike with the reused member key' is: {
  [PBMemberKeys checkDepth: deep memberKey: ((PBMemberKeys memberKeyAndOrderKeyOf: deep) at: 1) index: idx. nil]
    on: PBValidationError do: [:e | e return: e messageText].
  (([PBMemberKeys checkDepth: deep memberKey: nil index: idx. nil] on: PBValidationError do: [:e | e return: e messageText])
    ifNil: ['no error']) }
  equals: (Array new: 2 withAll: (([PBMemberKeys checkDepth: deep memberKey: nil index: idx. nil]
    on: PBValidationError do: [:e | e return: e messageText]) ifNil: ['no error'])).
c that: 'and it does fire' isTrue: (([PBMemberKeys checkDepth: deep memberKey: nil index: idx. '']
  on: PBValidationError do: [:e | e return: e messageText]) includesSubstring: 'its member key would nest').

"The writes with a given order key make the trees of the plain writes, node for node."
shape := [:root | | out | out := OrderedCollection new.
  PBAvl nodesDo: [:n | out add: { n key. n value. n height. n count. n weight }] over: root. out asArray].
"Integer, String and tuple keys (the tuples nest and mix ranks), inserted in a scattered order,
 then a third of them removed."
keys := ((1 to: 300) asArray collect: [:i | (i * 7919) \\ 101])
  , ((1 to: 150) asArray collect: [:i | 'k' , ((i * 37) \\ 89) printString])
  , ((1 to: 150) asArray collect: [:i | PBTuple withAll: { (i * 13) \\ 41. 'b' , (i \\ 7) printString.
    PBTuple withAll: { i \\ 3. 0.5 } }]).
root1 := nil. root2 := nil.
keys doWithIndex: [:k :i |
  root1 := (PBAvl keyPut: root1 key: k value: (PBTuple withAll: { i. 1 }) nodeClass: PBCountedKeyNode) at: 1.
  root2 := (PBAvl keyPut: root2 key: k orderKey: (PBKeys orderKey: k) value: (PBTuple withAll: { i. 1 }) nodeClass: PBCountedKeyNode) at: 1].
((1 to: keys size by: 3) collect: [:i | keys at: i]) do: [:k |
  root1 := (PBAvl keyRemove: root1 key: k) at: 1.
  root2 := (PBAvl keyRemove: root2 orderKey: (PBKeys orderKey: k)) at: 1].
c that: 'keyPut:/keyRemove: with an order key make the same tree' is: (shape value: root2) equals: (shape value: root1).
c that: 'keyAt:orderKey: finds what keyAt:key: finds' is: (keys collect: [:k | (PBAvl keyAt: root2 orderKey: (PBKeys orderKey: k)) ifNotNil: [:n | n value]])
  equals: (keys collect: [:k | (PBAvl keyAt: root1 key: k) ifNotNil: [:n | n value]]).
c report displayNl.

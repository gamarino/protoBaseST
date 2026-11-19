"-- keygroups.st: the member keys and the groups of the key-group indexes --

A port of proto_db's proto_db/indexing/keyed.py at v2.0.0rc4, lines 81-258: surrogate, the exact
member keys, the equal-member bounds, the nesting depth of member keys, and the group operations
(PBKeyGroups; the indexes that use them are in indexes.st). A key-group index files each element of a group in a members tree under its member key:

  ((0, element), exact token)      for an orderable element (an atom by its oid, a value by its
                                   order key)
  ((1, surrogate), exact token)    for an unorderable one (a list, a map, a NaN, or a tuple
                                   holding one)

The equality part is shared by every element equal to this one; the exact token (PBKeys
exactToken:, the canonical encoding, D58) tells apart values that are equal but not identical
(1, 1.0, Decimal 1.00), so a plan answers exactly the stored elements a scan answers.

  PBMemberKeys surrogate: aValue     an orderable stand-in for aValue: equal values give equal
                                     surrogates
  PBMemberKeys memberKeyOf: anElement
                                     the member key, a PBTuple
  PBMemberKeys lowestOf: aValue      the order keys enclosing every member key whose equality
  PBMemberKeys highestOf: aValue     part is aValue's (keyed.py _equal_members_bounds)
  PBMemberKeys checkDepth: anElement index: anIndex
                                     anElement, or PBValidationError (proto_db's sentence, naming
                                     anIndex) when its member key would nest deeper than
                                     MAX_VALUE_DEPTH
  PBMemberKeys depthLimits           the deepest elements an index can store, by shape
  PBMemberKeys identityOf: anElement proto_db's element_identity, for comparing multisets
  PBMemberKeys orderKeyOrNil: aValue the order key of aValue, nil when it is unorderable

A group is the PBTuple (members, total): members a PBCountedKeyNode tree from member key to the
PBTuple (element, count). PBKeyGroups empty, group:with:memberKey:, group:without:,
group:do: and sortedMembers:total: are keyed.py's EMPTY_GROUP, _group_add, _group_remove,
_group_iter and _GroupBuilder.group.

Every walk keeps an explicit stack (_PBValueFrame fold:...), so a value of any depth is walked
on any actor."

Import from: 'protobase/errors'.
Import from: 'protobase/keys'.
Import from: 'protobase/values'.
Import from: 'protobase/codec'.

Object subclass: #PBMemberKeys.

"=== surrogates ==============================================================="

"An orderable stand-in for the unorderable value aValue (keyed.py surrogate): a list becomes
 ('l', items), a map ('d', pairs sorted by the order key of each key's surrogate), a tuple
 holding an unorderable value ('t', items), a NaN ('n'), and every orderable value ('v',
 value); items are encoded at any depth. The tags make the encoding injective up to value
 equality (every NaN equal to every NaN)."
PBMemberKeys class >> surrogate: aValue
  ^ _PBValueFrame fold: aValue
    children: [:v | self _surrogateChildren: v]
    leaf: [:v | self _surrogateLeaf: v]
    node: [:v :results | self _surrogateOf: v results: results].

"The items keyed.py _surrogate_expand walks: a list's items, a map's keys and values
 interleaved, the items of an unorderable tuple; nil for a leaf."
PBMemberKeys class >> _surrogateChildren: v
  v isClassObject ifTrue: [^ nil].
  (v isKindOf: PBFrozenList) ifTrue: [^ v asArray].
  (v isKindOf: PBFrozenDict) ifTrue: [
    | items |
    items := OrderedCollection new.
    v keysAndValuesDo: [:k :x | items add: k; add: x].
    ^ items asArray].
  ((v isKindOf: PBTuple) and: [(PBKeys isOrderable: v) not]) ifTrue: [^ v asArray].
  ^ nil.

PBMemberKeys class >> _surrogateLeaf: v
  ((v isFloat or: [v isClassObject not and: [v isKindOf: Decimal]]) and: [v isNaN]) ifTrue: [
    ^ PBTuple withAll: #('n')].
  ^ PBTuple withAll: { 'v'. v }.

PBMemberKeys class >> _surrogateOf: v results: anArray
  | pairs okeys order |
  (v isKindOf: PBFrozenList) ifTrue: [^ PBTuple withAll: { 'l'. PBTuple withAll: anArray }].
  (v isKindOf: PBTuple) ifTrue: [^ PBTuple withAll: { 't'. PBTuple withAll: anArray }].
  "A map: (key surrogate, value surrogate) pairs, sorted by the key surrogate's order key
   (keyed.py _dict_surrogate). Two keys of one map never have equal surrogates."
  pairs := (1 to: anArray size // 2) asArray collect: [:i |
    PBTuple withAll: { anArray at: 2 * i - 1. anArray at: 2 * i }].
  okeys := pairs collect: [:p | PBKeys orderKey: (p at: 1)].
  order := (1 to: pairs size) asArray sort: [:i :j | (okeys at: i) <= (okeys at: j)].
  ^ PBTuple withAll: { 'd'. PBTuple withAll: (order collect: [:i | pairs at: i]) }.

"=== member keys =============================================================="

"The member key of anElement, (equality part, exact token), a PBTuple (keyed.py _member_key):
 members equal to one another are adjacent in a members tree."
PBMemberKeys class >> memberKeyOf: anElement
  ^ PBTuple withAll: { self _equalityPart: anElement. PBKeys exactToken: anElement }.

"(0, element) for an orderable element, (1, surrogate) for an unorderable one (keyed.py
 _equality_part)."
PBMemberKeys class >> _equalityPart: anElement
  (PBKeys isOrderable: anElement) ifTrue: [^ PBTuple withAll: { 0. anElement }].
  ^ PBTuple withAll: { 1. self surrogate: anElement }.

"The order key below every member key whose equality part is aValue's: the one-item tuple
 (equality part), which orders before every (equality part, token)."
PBMemberKeys class >> lowestOf: aValue
  ^ PBOrderKey rank: self _tupleRank payload: { PBKeys orderKey: (self _equalityPart: aValue) }.

"The order key above every member key whose equality part is aValue's: (equality part, a key
 above every rank) (keyed.py _equal_members_bounds and _ABOVE_EVERY_RANK)."
PBMemberKeys class >> highestOf: aValue
  ^ PBOrderKey rank: self _tupleRank payload: { PBKeys orderKey: (self _equalityPart: aValue). self _aboveEveryRank }.

"The rank of a tuple's order key (keyed.py _R_TUPLE, order_key(())[0])."
PBMemberKeys class >> _tupleRank
  ^ (PBKeys orderKey: (PBTuple withAll: #())) rank.

"keyed.py _ABOVE_EVERY_RANK, order_key(MISSING)[0] + 1000 as a one-item key: its rank exceeds
 every order key's, so it compares above any of them. It is a bound, never the key of a value,
 so it is built past PBOrderKey rank:payload:, which admits the ranks of values only."
PBMemberKeys class >> _aboveEveryRank
  ^ PBOrderKey basicNew _setRank: (PBKeys orderKey: PBMissing default) rank + 1000 payload: 0.

"=== nesting depth ============================================================

A member key is the key of a members-tree node, an attribute value, so the format's
MAX_VALUE_DEPTH applies to it (format spec, 'Value nesting depth'): its two tuples wrap the
element in 4 containers, and a surrogate adds 4 per list level (('l', (items...)), two tuples),
6 per map level (('d', ((k, v), ...)), three) and 2 around an orderable leaf (('v', value))."

"keyed.py MEMBER_KEY_WRAPPING."
PBMemberKeys class >> memberKeyWrapping
  ^ 4.

"keyed.py SURROGATE_LIST_LEVEL, SURROGATE_MAP_LEVEL and SURROGATE_LEAF."
PBMemberKeys class >> surrogateListLevel
  ^ 4.

PBMemberKeys class >> surrogateMapLevel
  ^ 6.

PBMemberKeys class >> surrogateLeaf
  ^ 2.

"The deepest elements a key-group index can store (keyed.py element_depth_limits): 'orderable'
 (the containers of an orderable element, its own wire depth), 'lists' and 'maps' (levels of an
 element of nested lists, or of nested maps, around a scalar leaf, through the surrogate)."
PBMemberKeys class >> depthLimits
  | room |
  room := PBCodec maxValueDepth - self memberKeyWrapping.
  ^ PBFrozenDict withAssociations: {
    'orderable' -> room.
    'lists' -> (room - self surrogateLeaf // self surrogateListLevel).
    'maps' -> (room - self surrogateLeaf // self surrogateMapLevel) }.

"anElement, or PBValidationError when its member key would nest deeper than MAX_VALUE_DEPTH, with
 proto_db's sentence naming anIndex (keyed.py check_member_key): a scalar or an atom nests a few
 containers only; a container is bounded first from its own depth, and only an element that could
 pass the limit costs the walk of its member key. There is no outer parameter: in proto_db only the
 vector index stores member keys inside more containers, and protoBaseST never writes a vector
 index (ruling IQ5)."
PBMemberKeys class >> checkDepth: anElement index: anIndex
  ^ self checkDepth: anElement memberKey: nil index: anIndex.

"As checkDepth:index:, for a caller that has the member key aKeyOrNil already (nil: computed when
 the bound needs it), as with_added passes it to check_member_key."
PBMemberKeys class >> checkDepth: anElement memberKey: aKeyOrNil index: anIndex
  | max depth limits |
  (anElement isClassObject not and: [
      (anElement isKindOf: _PBSequence) or: [anElement isKindOf: PBFrozenDict]]) ifFalse: [^ anElement].
  max := PBCodec maxValueDepth.
  self memberKeyWrapping + (self surrogateListLevel * (PBCodec valueDepth: anElement)) + self surrogateLeaf <= max
    ifTrue: [^ anElement].
  depth := PBCodec valueDepth: (aKeyOrNil isNil ifTrue: [self memberKeyOf: anElement] ifFalse: [aKeyOrNil]).
  depth <= max ifTrue: [^ anElement].
  limits := self depthLimits.
  ^ PBValidationError signal: anIndex _subject , ' cannot store this element: its member key would nest '
    , depth printString , ' MessagePack containers deep, more than MAX_VALUE_DEPTH = ' , max printString
    , ' (format spec, "Value nesting depth"). The index stores an orderable element inside '
    , self memberKeyWrapping printString , ' containers, so it may nest at most ' , (limits at: 'orderable') printString
    , '; an unorderable one (holding a list, a map or NaN) through its surrogate, '
    , self surrogateListLevel printString , ' containers per list level and ' , self surrogateMapLevel printString
    , ' per map level: at most ' , (limits at: 'lists') printString , ' nested lists or '
    , (limits at: 'maps') printString , ' nested maps'.

"=== identities ==============================================================="

"The order key of aValue, or nil when aValue is unorderable (PBKeys isOrderable: false: a list, a
 map, a NaN, or a tuple holding one): the test and the key in one computation."
PBMemberKeys class >> orderKeyOrNil: aValue
  ^ [PBKeys orderKey: aValue] on: PBValidationError do: [:e | e return: nil].

"An identity of anElement, equal for equal elements, for comparing multisets (proto_db
 indexing.element_identity): the order key of its equality part. Atoms are identified by oid,
 orderable values by their order key (1 and 1.0 are one element, true another), and lists, maps
 and unorderable tuples item by item at any depth through their surrogates (a list never equals a
 tuple; every NaN equals every NaN). PBMissing and nil are two identities."
PBMemberKeys class >> identityOf: anElement
  ^ PBKeys orderKey: (self _equalityPart: anElement).

"=== groups (keyed.py _group_add, _group_remove, _group_iter) ==================

A group is the PBTuple (members, total): members a PBCountedKeyNode tree from member key to the
PBTuple (element, count), total the occurrences the group holds. Every operation answers a new
group and shares the rest of the tree (path copying)."

Object subclass: #PBKeyGroups.

"keyed.py EMPTY_GROUP: (None, 0)."
PBKeyGroups class >> empty
  ^ PBTuple withAll: { nil. 0 }.

"aGroup with one more occurrence of anElement, whose member key is aKey (keyed.py _group_add)."
PBKeyGroups class >> group: aGroup with: anElement memberKey: aKey
  | members node entry |
  members := aGroup at: 1.
  node := PBAvl keyAt: members key: aKey.
  entry := node isNil
    ifTrue: [PBTuple withAll: { anElement. 1 }]
    ifFalse: [PBTuple withAll: { node value at: 1. (node value at: 2) + 1 }].
  members := (PBAvl keyPut: members key: aKey value: entry nodeClass: PBCountedKeyNode) at: 1.
  ^ PBTuple withAll: { members. (aGroup at: 2) + 1 }.

"aGroup with one occurrence of anElement fewer, or nil when it holds none (keyed.py
 _group_remove): only the member whose member key is anElement's is taken, never an equal member
 with another token (D58)."
PBKeyGroups class >> group: aGroup without: anElement
  | members key node entry |
  members := aGroup at: 1.
  key := PBMemberKeys memberKeyOf: anElement.
  node := PBAvl keyAt: members key: key.
  node isNil ifTrue: [^ nil].
  entry := node value.
  members := (entry at: 2) = 1
    ifTrue: [(PBAvl keyRemove: members key: key) at: 1]
    ifFalse: [(PBAvl keyPut: members key: key value: (PBTuple withAll: { entry at: 1. (entry at: 2) - 1 })
      nodeClass: PBCountedKeyNode) at: 1].
  ^ PBTuple withAll: { members. (aGroup at: 2) - 1 }.

"Evaluates aBlock with each stored element of aGroup and its count, in member order (keyed.py
 _group_iter yields each occurrence; the count stands for them)."
PBKeyGroups class >> group: aGroup do: aBlock
  PBAvl keysAndValuesDo: [:key :entry | aBlock value: (entry at: 1) value: (entry at: 2)] over: (aGroup at: 1).

"The group of anArray's { member order key. member key. element. count } entries, sorted by
 member order key, built balanced (keyed.py _GroupBuilder.group): total is its occurrences."
PBKeyGroups class >> sortedMembers: anArray total: anInteger
  | sorted |
  sorted := anArray asArray sort: [:a :b | (a at: 1) <= (b at: 1)].
  ^ PBTuple withAll: {
    PBAvl keyFromSortedOrderKeys: (sorted collect: [:each |
        { each at: 1. each at: 2. PBTuple withAll: { each at: 3. each at: 4 } }])
      nodeClass: PBCountedKeyNode.
    anInteger }.

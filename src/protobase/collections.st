"-- collections.st: the collections of format 4, read side --

ProtoBase's collections (format spec v2.0.0rc2, 'Collections'; ProtoBase
proto_db/collections/*.py at the tag), with the read API of the design spec
5.2. Every collection persists count and indexes (a reference to a
PBIndexSet) plus its own fields:

  PBIndexSet                 proto_db.collections.IndexSet: root, a KeyNode tree
                             from index name to index (not a collection)
  PBIndexedCollection        proto_db.collections.IndexedCollection (abstract)
  PBList                     List: root, a PosNode tree of the elements in order
  PBDictionary               Dictionary: root, a KeyNode tree by the order key of
                             the key, node value the mapped value
  PBHashDictionary           HashDictionary: root, a KeyNode tree from the hash
                             key of a key to a bucket tuple of (key, value) tuples
  PBHashBuckets              sets._HashBuckets (abstract): the bucket trees of
  PBSet                      Set (a bucket holds elements) and
  PBCountedSet               CountedSet (a bucket holds (element, count) pairs;
                             count distinct elements, total_count their sum)
  PBRepeatedKeysDictionary   RepeatedKeysDictionary: root, a KeyNode tree by key
                             whose values are non-empty CountedSets of records

Every collection message answers a new version; the receiver never changes
(plan Tasks 15-16). The read messages:

  count, size                  the persisted count (size is the synonym)
  do: aBlock                   the elements, in the collection's own order
  elements                     the same, as an Array
  indexNames, getIndex: aName  the indexes (sorted names; nil when absent)
  PBList >> getAt: i           the element at the 0-based position i; a negative
                               i counts from the end; another i (out of range, not
                               an Integer) is PBValidationError (plan call C15)
  getAt: k, getAt: k default: d, has: k
                               the dictionaries (and has: of the sets): a key is
                               found by its order key, so 1, 1.0 and Decimal 1.00
                               find one key and true another; an unorderable key
                               is PBValidationError (ProtoBase: order_key raises)
  keys, values, items, keysAndValuesDo: aBlock
                               the dictionaries; items are Associations
  countOf: e, items            PBCountedSet (items: element -> count)
  totalCount                   PBCountedSet and PBRepeatedKeysDictionary

The writes (plan Tasks 15 and 16). Each answers a new collection, a new atom
with its own oid (drawn on first need), and leaves the receiver as it was;
values (and keys and elements) pass through PBCodec canonical: at once:

  PBList new, PBDictionary new, PBSet new, ...
                               an empty collection with an empty PBIndexSet
  PBList >> setAt: i value: v, insertAt: i value: v, removeAt: i,
            appendFirst: v, appendLast: v, extend: aCollection,
            sliceFrom: a to: b, head: n, tail: n
                               ProtoBase's List: 0-based positions, a
                               negative one counting from the end; a position
                               out of range or not an Integer is
                               PBValidationError (insertAt: count appends);
                               slices clamp like Python slices (a bound may
                               be nil); extend: of nothing answers the
                               receiver, as ProtoBase's
  PBDictionary >> setAt: k value: v, removeAt: k
  PBHashDictionary >> setAt: k value: v, removeAt: k
                               an absent key's removeAt: answers a new version
                               with the same content, as ProtoBase's
  PBSet >> add: e, remove: e   the same for a present element's add: and an
                               absent element's remove:
  PBCountedSet >> add: e, remove: e
                               one occurrence more or fewer (the last one takes the
                               element out; an absent element's remove: answers a new
                               version with the same content), count and totalCount
                               kept, as ProtoBase's CountedSet
  PBSet >> union: c, intersection: c, difference: c
                               ProtoBase's folds of add: and remove: (c is a
                               set or anything answering do:, not a String):
                               union: adds each element of c in c's order,
                               intersection: removes the receiver's members
                               absent from c in the receiver's order,
                               difference: removes each element of c in c's
                               order; always a new version

Operation logs (ProtoBase ConcurrentOptimized, D33; design spec 7.2). A
PBDictionary, a PBHashDictionary, a PBSet and a PBCountedSet are
ConcurrentOptimized: every version carries two runtime-only fields, never
persisted, and a cell:

  opLog          a PBFrozenList of PBTuples, the intents of the mutator calls
                 that derived the version, ProtoBase's ops: ('set' k v) and
                 ('remove' k) for the dictionaries, ('add' e) and ('remove' e)
                 for a set and a counted set, ('transform' e removes adds) for a
                 counted set's rebase. Every call logs, a blind write (one that changes
                 nothing) included; a PBDictionary logs a large value in its
                 stored form, the PBValueBox its node holds, so a replay reuses
                 the box (ProtoBase D51)
  logComplete    whether replaying the log onto an empty collection rebuilds
                 the content: true for a version built by new and derived
                 only by logged mutators, false for a loaded version and
                 everything derived from it; isMergeable answers it
  consumed       an Atom holding false; markConsumed (the publisher, after a
                 commit) sets it to true. A version derived later reads its
                 parent's cell at derivation time (its logComplete is the
                 parent's logComplete, which is false once the parent is
                 consumed), as ProtoBase copies _log_complete in _with after the
                 commit cleared it on the parent; an earlier sibling keeps its
                 own. The consumed version itself answers false from then on.

  rebaseOnto: current          ProtoBase rebase_onto: current with the net
                               effect of the log replayed through the public
                               mutators. The net effect is the last op per key
                               (element), keys compared by order key, in order
                               of last occurrence; for a PBCountedSet, the
                               composed counter transform per element (D26,
                               see _netOps). current must be of the
                               receiver's exact class (PBValidationError
                               otherwise), and a current with an index is
                               PBNotSupportedError (design spec 7.4). The
                               answer's log is current's extended by the
                               replay, so a rebase onto a loaded current (what
                               a commit meets) is incomplete, and one onto a
                               version built in memory keeps that version's
                               completeness, as ProtoBase's.

The log is a persistent chain (_PBOpLog): a mutator adds one link in O(1),
and opLog builds the PBFrozenList on request. A PBList has no log (ProtoBase's
List is not ConcurrentOptimized): it is never mergeable, rebaseOnto: is
PBNotSupportedError, and markConsumed changes nothing that matters.
PBRepeatedKeysDictionary is ConcurrentOptimized too, but it has no mutators
here (its writes are a non-goal, design spec 'Non-goals'), so its log is
always empty, a new one is mergeable, and its rebase answers current
unchanged, as ProtoBase's.

The trees are built by PBAvl, as ProtoBase's avl.py builds them, so one
sequence of operations gives the same nodes in both implementations. A hash
dictionary and a set file an entry under _bucketHash: of its key (element),
the hash key (PBKeys hashKey:) unless a subclass overrides it (ProtoBase's
_bucket_hash, the seam its tests use to force collisions; it must stay a pure
function of the value, since persisted trees are ordered by it),
in a bucket, a tuple of the entries of that hash in insertion order (a hash
dictionary's entries are (key, value) tuples, a counted set's (element, count)
tuples); a bucket emptied by a removal
leaves the tree. A
collection with an index refuses every change with PBNotSupportedError naming
the indexes (design spec 7.4): ProtoBase maintains the indexes in the same
step, which protoBaseST cannot do. A new collection writes its fields in the
order ProtoBase sets them: indexes, count, then its own fields for an empty
one, persistedFields for a later version.

These names keep ProtoBase's meaning, which differs from Pharo's for add:,
remove: and removeAt: (design spec 5.3): their result is the new version, and
a statement that discards it changes nothing.

The iteration orders are ProtoBase's: a List by position, a Dictionary and a
RepeatedKeysDictionary by key order; a HashDictionary, a Set and a CountedSet
in tree order (the hash key), then bucket order. A Dictionary's elements (what
its indexes see) are its values; a RepeatedKeysDictionary's are the distinct
records of each key, key by key.

A probe key is made canonical first (PBCodec canonical:, so an Array finds a
list) and then ordered or hashed (PBKeys). A bucket that is not a tuple, or an
entry that is not a pair, is PBCorruptionError."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/keys'.
Import from: 'protobase/codec'.
Import from: 'protobase/avl'.

"=== PBIndexSet ==============================================================="

PBAtom subclass: #PBIndexSet.

PBIndexSet class >> typeName
  ^ 'proto_db.collections.IndexSet'.

PBIndexSet class >> requiredFields
  ^ #('root').

PBIndexSet class >> persistedFields
  ^ #('root').

"The names of the indexes, sorted."
PBIndexSet >> names
  | out |
  out := OrderedCollection new.
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node | out add: node key].
  ^ out asArray.

"The index named aName, or nil."
PBIndexSet >> get: aName
  | node |
  (aName isString and: [aName isSymbol not]) ifFalse: [^ nil].
  node := _PBTree nodeWithKey: (PBKeys orderKey: aName) of: (self stateAt: 'root') in: self.
  ^ node isNil ifTrue: [nil] ifFalse: [node value].

PBIndexSet >> size
  ^ _PBTree count: (self stateAt: 'root') kind: PBKeyNode in: self.

"An empty index set (ProtoBase IndexSet())."
PBIndexSet class >> new
  ^ self _unsavedWithState: (PBFrozenDict withAssociations: { 'root' -> nil }).

PBIndexSet >> isEmpty
  ^ (self stateAt: 'root') isNil.

"=== _PBOpLog ================================================================"

"One link of an operation log: the op (a PBTuple) and the log before it (a
 _PBOpLog, or nil for the first op), with the number of ops up to it. A log
 is extended by a new link, never changed, so versions share their common
 prefix and a mutator logs in O(1)."
Object subclass: #_PBOpLog instanceVariableNames: 'previous op size'.

"The log aLog (a _PBOpLog, or nil when empty) followed by aTuple."
_PBOpLog class >> after: aLog op: aTuple
  ^ self basicNew _setPrevious: aLog op: aTuple.

_PBOpLog >> _setPrevious: aLog op: aTuple
  "Runs once, on a fresh instance."
  size isNil ifFalse: [^ PBUserError signal: '_PBOpLog is immutable'].
  previous := aLog.
  op := aTuple.
  size := aLog isNil ifTrue: [1] ifFalse: [aLog size + 1].
  ^ self.

_PBOpLog >> size
  ^ size.

"The ops of aLog (a _PBOpLog, or nil), oldest first, in a new Array."
_PBOpLog class >> opsOf: aLog
  | out link |
  aLog isNil ifTrue: [^ Array new: 0].
  out := Array new: aLog size.
  link := aLog.
  [link isNil] whileFalse: [
    out at: link size put: link _op.
    link := link _previous].
  ^ out.

_PBOpLog >> _op
  ^ op.

_PBOpLog >> _previous
  ^ previous.

"=== PBIndexedCollection ======================================================"

"log, complete and consumed are the runtime-only fields of the operation log
 (see the module comment); every instance has them, set once by _setLog:complete:
 before the atom is initialised."
PBAtom subclass: #PBIndexedCollection instanceVariableNames: 'log complete consumed'.

PBIndexedCollection class >> typeName
  ^ 'proto_db.collections.IndexedCollection'.

PBIndexedCollection class >> requiredFields
  ^ #('count' 'indexes').

PBIndexedCollection class >> persistedFields
  ^ #('count' 'indexes').

"The persisted count."
PBIndexedCollection >> count
  ^ _PBTree integer: (self stateAt: 'count') field: 'count' of: self.

PBIndexedCollection >> size
  ^ self count.

PBIndexedCollection >> isEmpty
  ^ self count = 0.

PBIndexedCollection >> notEmpty
  ^ self isEmpty not.

"The PBIndexSet of the collection."
PBIndexedCollection >> indexes
  | set |
  set := self stateAt: 'indexes'.
  (set isKindOf: PBIndexSet) ifTrue: [^ set].
  ^ _PBTree node: set kind: PBIndexSet in: self.

PBIndexedCollection >> indexNames
  | set |
  set := self indexes.
  ^ set isNil ifTrue: [#()] ifFalse: [set names].

"The index named aName, or nil."
PBIndexedCollection >> getIndex: aName
  | set |
  set := self indexes.
  ^ set isNil ifTrue: [nil] ifFalse: [set get: aName].

"Evaluates aBlock with each element (what the indexes see), in order."
PBIndexedCollection >> do: aBlock
  ^ PBNotSupportedError signal: self class name , ': ' , self class typeName , ' is abstract: it has no elements'.

"The elements, in order, as an Array."
PBIndexedCollection >> elements
  | out |
  out := OrderedCollection new.
  self do: [:each | out add: each].
  ^ out asArray.

"The canonical form of a probe key."
PBIndexedCollection >> _probe: aKey
  ^ PBCodec canonical: aKey.

"aValue canonical, a PBValidationError of the codec naming aRole of this
 collection ('PBList element', 'PBDictionary key'), as ProtoBase's
 canonical_for names the List's element."
PBIndexedCollection >> _canonical: aValue as: aRole
  ^ PBCodec canonical: aValue for: self class name , ' ' , aRole.

"As _canonical:as:, refused (PBValidationError) also when the anInteger
 containers aWrapper adds around the value in a stored node would make it nest
 deeper than PBCodec maxValueDepth: at the call, not at commit (ProtoBase
 check_wrapped)."
PBIndexedCollection >> _canonical: aValue as: aRole wrapping: anInteger by: aWrapper
  ^ PBCodec check: (self _canonical: aValue as: aRole) wrapping: anInteger
    holder: self class name , ' ' , aRole wrapper: aWrapper.

"--- new versions ---"

"An empty collection of this class (ProtoBase's constructor): no elements, an
 empty PBIndexSet, and the fields in the order ProtoBase sets them (indexes,
 count, then the class's own)."
PBIndexedCollection class >> new
  | fields |
  (self == PBIndexedCollection or: [self == PBHashBuckets]) ifTrue: [
    ^ PBNotSupportedError signal: self name , ' is abstract: make a concrete collection'].
  fields := OrderedCollection new.
  fields addLast: 'indexes' -> PBIndexSet new; addLast: 'count' -> 0.
  self persistedFields do: [:f |
    (f = 'count' or: [f = 'indexes']) ifFalse: [fields addLast: f -> (self _emptyValueOf: f)]].
  "Built empty in this process: its (empty) log describes it all."
  ^ self _unsavedWithState: (PBFrozenDict withAssociations: fields asArray) tag: nil
    log: nil complete: self _logsOperations.

"The value of a field of an empty collection, other than count and indexes."
PBIndexedCollection class >> _emptyValueOf: aField
  ^ nil.


"=== the operation log ==="

"Whether the class is ConcurrentOptimized in ProtoBase: PBDictionary,
 PBHashDictionary, PBSet, PBCountedSet and PBRepeatedKeysDictionary (the
 last has no mutators here: its log stays empty)."
PBIndexedCollection class >> _logsOperations
  ^ false.

"An unsaved collection holding aPBFrozenDict whose operation log is aLog (a
 _PBOpLog, or nil when empty), complete or not."
PBIndexedCollection class >> _unsavedWithState: aPBFrozenDict tag: aTag log: aLog complete: aBoolean
  ^ self _unsaved: (self basicNew _setLog: aLog complete: aBoolean) withState: aPBFrozenDict tag: aTag.

"Runs once, on a fresh instance, before the atom is initialised."
PBIndexedCollection >> _setLog: aLog complete: aBoolean
  consumed isNil ifFalse: [^ PBUserError signal: self class name , ': the operation log is set once'].
  log := aLog.
  complete := aBoolean.
  consumed := Atom on: false.
  ^ self.

"Every constructor of an atom runs this once. A collection made without a log
 (a stub, a decoded twin: a loaded version) gets an empty, incomplete one."
PBIndexedCollection >> _setOid: anOid pointer: aPointer storage: aStorage
  consumed isNil ifTrue: [self _setLog: nil complete: false].
  ^ super _setOid: anOid pointer: aPointer storage: aStorage.

"The intents logged since the version was built or loaded: a PBFrozenList of
 PBTuples, oldest first."
PBIndexedCollection >> opLog
  ^ PBFrozenList withAll: (_PBOpLog opsOf: log).

"Whether replaying opLog onto an empty collection rebuilds this version's
 content (ProtoBase log_is_complete, D33): false for a loaded version, for a
 version marked consumed and for everything derived from them."
PBIndexedCollection >> logComplete
  ^ complete and: [consumed value not].

"Whether a commit may merge this version by replaying its log (D33)."
PBIndexedCollection >> isMergeable
  ^ self logComplete.

"The Atom cell that markConsumed sets (holding false until then)."
PBIndexedCollection >> consumed
  ^ consumed.

"Marks the log as replayed by a commit (D33): from now on this version and
 every version derived from it are not mergeable. The publisher calls it on
 every collection it committed."
PBIndexedCollection >> markConsumed
  consumed value: true ifCurrent: false.
  ^ self.

"current with the net effect of this version's log replayed through the
 public mutators (ProtoBase ConcurrentOptimized.rebase_onto). The order of the
 checks is protoBaseST's own: a class without a log (PBList) is refused first,
 where ProtoBase's List has no rebase_onto at all (an AttributeError); then a
 current of another class (ProtoBase's type check), then a current with an
 index (design spec 7.4)."
PBIndexedCollection >> rebaseOnto: current
  | ops target |
  self class _logsOperations ifFalse: [
    ^ PBNotSupportedError signal: self class name , ' has no operation log to rebase (ProtoBase''s '
      , self class typeName , ' is not ConcurrentOptimized)'].
  (current isClassObject not and: [current class == self class]) ifFalse: [
    ^ PBValidationError signal: 'Cannot rebase a ' , self class name , ' onto ' , (PBKeys _preview: current)].
  current _checkWritable: 'rebaseOnto:'.
  ops := self _netOps.
  target := current.
  1 to: ops size do: [:i | target := self _replay: (ops at: i) onto: target].
  ^ target.

"The ops rebaseOnto: replays (ProtoBase net_effect with the default op key):
 the last op per key, keys compared by order key, in order of last
 occurrence. O(n) in the length of the log."
PBIndexedCollection >> _netOps
  | ops keys last out |
  ops := _PBOpLog opsOf: log.
  keys := Array new: ops size.
  last := Dictionary new.
  1 to: ops size do: [:i |
    | okey |
    okey := PBKeys orderKey: ((ops at: i) at: 2).
    keys at: i put: okey.
    last at: okey put: i].
  out := OrderedCollection new.
  1 to: ops size do: [:i | (last at: (keys at: i)) = i ifTrue: [out addLast: (ops at: i)]].
  ^ out asArray.

"aTarget after one net op (a ConcurrentOptimized class answers it through
 its public mutators)."
PBIndexedCollection >> _replay: anOp onto: aTarget
  ^ PBValidationError signal: 'Unknown ' , self class name , ' op ' , anOp printString.

"--- new versions ---"

"A new version of this collection (ProtoBase IndexedCollection._with): root
 and count as given, every other field (indexes included) carried over, in
 persistedFields order. Its log is the receiver's, and it is incomplete: a
 change of content that the log does not describe (ProtoBase _with without an
 op). A PBList's writes come here."
PBIndexedCollection >> _withRoot: aRoot count: aCount
  ^ self _withRoot: aRoot count: aCount log: log complete: false.

"A new version with root and count as given and anOp (a PBTuple) logged: as
 complete as the receiver."
PBIndexedCollection >> _withRoot: aRoot count: aCount op: anOp
  ^ self _withChanges: { 'root' -> aRoot. 'count' -> aCount } op: anOp.

"A new version with the fields of aChanges (field -> value Associations) changed and anOp
 logged: as complete as the receiver."
PBIndexedCollection >> _withChanges: aChanges op: anOp
  ^ self _withChanges: aChanges log: (_PBOpLog after: log op: anOp) complete: self logComplete.

"A new version with the receiver's content and log (ProtoBase _with())."
PBIndexedCollection >> _newVersion
  ^ self _withRoot: (self stateAt: 'root') count: (self stateAt: 'count') log: log complete: self logComplete.

PBIndexedCollection >> _withRoot: aRoot count: aCount log: aLog complete: aBoolean
  ^ self _withChanges: { 'root' -> aRoot. 'count' -> aCount } log: aLog complete: aBoolean.

"A new version whose persisted fields named in aChanges (an Array of field -> value
 Associations) take those values, every other field carried over, in persistedFields
 order; its log is aLog, complete or not."
PBIndexedCollection >> _withChanges: aChanges log: aLog complete: aBoolean
  | cls shape fields values |
  cls := self class.
  shape := cls _recordShape.
  fields := shape persisted.
  values := Array new: fields size.
  1 to: fields size do: [:i |
    | f change |
    f := fields at: i.
    change := aChanges detect: [:each | each key = f] ifNone: [nil].
    values at: i put: (change isNil ifTrue: [self stateAt: f] ifFalse: [change value])].
  ^ cls _unsavedWithState: (PBFrozenDict _keys: fields index: shape persistedIndex values: values) tag: nil
    log: aLog complete: aBoolean.

"The elements of aCollection (a collection of this module, or anything else
 answering do:, but not a String), read in full, in its order (Python's
 list(other)). aSelector names the caller in the refusal."
PBIndexedCollection >> _elementsOf: aCollection for: aSelector
  | out |
  (aCollection isClassObject not and: [aCollection respondsTo: #do:]) ifFalse: [
    ^ PBValidationError signal: self class name , ' ' , aSelector , ' a collection was expected, not '
      , (PBKeys _preview: aCollection)].
  "A deviation from Python, where list('abc') is 'a', 'b' and 'c': a String's
   elements are Characters, which no format stores."
  aCollection isString ifTrue: [
    ^ PBValidationError signal: self class name , ' ' , aSelector
      , ' a String is one value, not a collection of values (store one String with appendLast:, add: or setAt:value:): '
      , (PBKeys _preview: aCollection)].
  out := OrderedCollection new.
  aCollection do: [:each | out addLast: each].
  ^ out asArray.

"Signals PBNotSupportedError naming the indexes when the collection has any:
 protoBaseST cannot maintain an index, so it refuses every change to an
 indexed collection (design spec 7.4), where ProtoBase would update the
 indexes in the same step."
PBIndexedCollection >> _checkWritable: aSelector
  | set |
  set := self indexes.
  (set isNil or: [set isEmpty]) ifTrue: [^ self].
  ^ PBNotSupportedError signal: self class name , ' ' , aSelector , ': the collection has the indexes '
    , (set names inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ', ' , each]])
    , ', which protoBaseST cannot maintain: it refuses every change to an indexed collection (design spec 7.4)'.

"=== PBList ==================================================================="

PBIndexedCollection subclass: #PBList.
PBList comment: 'Every message answers a new version; the receiver never changes. Positions are zero-based, as in ProtoBase. getAt: 0 is the first element, and a negative position counts from the end. ProtoBase''s List (proto_db.collections.List): a sequence over a positional AVL tree. setAt:value:, insertAt:value:, removeAt:, appendFirst:, appendLast:, extend:, sliceFrom:to:, head: and tail: answer the new list; a statement that discards the result changes nothing.'.

PBList class >> typeName
  ^ 'proto_db.collections.List'.

PBList class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBList class >> persistedFields
  ^ #('root' 'count' 'indexes').

PBList >> do: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBPosNode in: self do: [:node | aBlock value: node value].

"The position anIndex stands for, in 0 .. anUpper (ProtoBase List._position,
 plan call C15): a negative index counts from the end; an index that is not an
 Integer (a Boolean included), or outside, is PBValidationError."
PBList >> _position: anIndex upper: anUpper
  | position |
  (anIndex isInteger and: [anIndex ~~ true and: [anIndex ~~ false]]) ifFalse: [
    ^ PBValidationError signal: 'A list position must be an Integer, not ' , (PBKeys _preview: anIndex)].
  position := anIndex < 0 ifTrue: [anIndex + self count] ifFalse: [anIndex].
  (position between: 0 and: anUpper) ifFalse: [
    ^ PBValidationError signal: 'List position ' , anIndex printString , ' out of range for a list of '
      , self count printString].
  ^ position.

"The element at anIndex: 0-based, a negative index counts from the end."
PBList >> getAt: anIndex
  | position |
  position := self _position: anIndex upper: self count - 1.
  ^ (_PBTree nodeAt: position of: (self stateAt: 'root') in: self) value.

"--- writes (ProtoBase List mutators) ---"

"A list whose element at anIndex is aValue."
PBList >> setAt: anIndex value: aValue
  | position value |
  self _checkWritable: 'setAt:value:'.
  position := self _position: anIndex upper: self count - 1.
  value := self _canonical: aValue as: 'element'.
  ^ self _withRoot: (PBAvl posSet: (self stateAt: 'root') at: position value: value) count: self count.

"A list with aValue inserted before position anIndex (insertAt: count appends)."
PBList >> insertAt: anIndex value: aValue
  | position value |
  self _checkWritable: 'insertAt:value:'.
  position := self _position: anIndex upper: self count.
  value := self _canonical: aValue as: 'element'.
  ^ self _withRoot: (PBAvl posInsert: (self stateAt: 'root') at: position value: value) count: self count + 1.

"A list without the element at anIndex (a new list, unlike Pharo's
 removeAt:, which removes in place and answers the element)."
PBList >> removeAt: anIndex
  | position |
  self _checkWritable: 'removeAt:'.
  position := self _position: anIndex upper: self count - 1.
  ^ self _withRoot: (PBAvl posRemove: (self stateAt: 'root') at: position) count: self count - 1.

"A list with aValue before the first element."
PBList >> appendFirst: aValue
  ^ self insertAt: 0 value: aValue.

"A list with aValue after the last element."
PBList >> appendLast: aValue
  ^ self insertAt: self count value: aValue.

"A list with the elements of aCollection (anything answering do:, a PBList
 included, but not a String or Symbol) appended in order; read in full before
 anything is built. An empty aCollection answers the receiver, as ProtoBase's
 extend, an indexed list included."
PBList >> extend: aCollection
  | values |
  "A String is refused (_elementsOf:for:)."
  values := self _elementsOf: aCollection for: 'extend:'.
  1 to: values size do: [:i | values at: i put: (self _canonical: (values at: i) as: 'element')].
  "As ProtoBase: nothing to add answers the receiver before the indexes are
   looked at, so an indexed list answers itself too."
  values isEmpty ifTrue: [^ self].
  self _checkWritable: 'extend:'.
  ^ self
    _withRoot: (PBAvl posConcat: (self stateAt: 'root') with: (PBAvl posFromArray: values))
    count: self count + values size.

"The list of the elements at aStart .. aStop - 1, with Python slice rules
 (ProtoBase List.slice): a bound may be nil (the start or the end), a negative
 one counts from the end, and both are clamped to the list; a stop before the
 start gives an empty list. A new list, built in O(log n)."
PBList >> sliceFrom: aStart to: aStop
  | n lo hi |
  self _checkWritable: 'sliceFrom:to:'.
  n := self count.
  lo := self _sliceBound: aStart default: 0 count: n.
  hi := (self _sliceBound: aStop default: n count: n) max: lo.
  ^ self _withRoot: (PBAvl posSlice: (self stateAt: 'root') from: lo to: hi) count: hi - lo.

"The first anInteger elements (sliceFrom: nil to: anInteger: a negative
 anInteger drops elements from the end)."
PBList >> head: anInteger
  ^ self sliceFrom: nil to: anInteger.

"The elements from position anInteger on (sliceFrom: anInteger to: nil: a
 negative anInteger keeps the last elements)."
PBList >> tail: anInteger
  ^ self sliceFrom: anInteger to: nil.

"A slice bound as Python's slice.indices computes it for step 1: nil is
 aDefault, a negative bound counts from the end, and the result is clamped to
 0 .. n. A bound that is not an Integer (a Boolean included) is
 PBValidationError."
PBList >> _sliceBound: aBound default: aDefault count: n
  | b |
  aBound isNil ifTrue: [^ aDefault].
  (aBound isInteger and: [aBound ~~ true and: [aBound ~~ false]]) ifFalse: [
    ^ PBValidationError signal: 'A slice bound must be an Integer or nil, not ' , (PBKeys _preview: aBound)].
  b := aBound < 0 ifTrue: [aBound + n] ifFalse: [aBound].
  ^ (b max: 0) min: n.

"=== PBDictionary ============================================================="

PBIndexedCollection subclass: #PBDictionary.
PBDictionary comment: 'Every message answers a new version; the receiver never changes. ProtoBase''s Dictionary (proto_db.collections.Dictionary): a map over a keyed AVL tree ordered by the order key of the key, so 1, 1.0 and Decimal 1.00 are one key and true another. setAt:value: and removeAt: answer the new dictionary (removeAt: of an absent key a new version with the same content); a statement that discards the result changes nothing. Each version logs its intents (opLog) for rebaseOnto:.'.

PBDictionary class >> typeName
  ^ 'proto_db.collections.Dictionary'.

PBDictionary class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBDictionary class >> persistedFields
  ^ #('root' 'count' 'indexes').

PBDictionary >> _nodeAt: aKey
  | key |
  key := self _probe: aKey.
  ^ _PBTree nodeWithKey: (PBKeys orderKey: key) of: (self stateAt: 'root') in: self.

PBDictionary >> getAt: aKey
  ^ self getAt: aKey default: nil.

PBDictionary >> getAt: aKey default: aDefault
  | node |
  node := self _nodeAt: aKey.
  ^ node isNil ifTrue: [aDefault] ifFalse: [node value].

PBDictionary >> has: aKey
  ^ (self _nodeAt: aKey) notNil.

"Evaluates aBlock with each key and its value, in key order."
PBDictionary >> keysAndValuesDo: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node |
    aBlock value: node key value: node value].

"The values, in key order (the elements)."
PBDictionary >> do: aBlock
  self keysAndValuesDo: [:k :v | aBlock value: v].

PBDictionary >> keys
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k].
  ^ out asArray.

PBDictionary >> values
  ^ self elements.

"key -> value Associations, in key order."
PBDictionary >> items
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k -> v].
  ^ out asArray.

"--- writes (ProtoBase Dictionary set_at, remove_at) ---"

"A dictionary with aKey mapped to aValue. The key must be orderable (a list,
 a map or a NaN is PBValidationError); an existing key keeps its stored key
 object."
PBDictionary >> setAt: aKey value: aValue
  | key stored put |
  self _checkWritable: 'setAt:value:'.
  key := self _canonical: aKey as: 'key'.
  "The log keeps the stored form: a replay reuses the box (ProtoBase D51)."
  stored := _PBTree boxed: (self _canonical: aValue as: 'value').
  put := PBAvl keyPut: (self stateAt: 'root') key: key value: stored nodeClass: PBKeyNode.
  ^ self
    _withRoot: (put at: 1)
    count: ((put at: 2) ifTrue: [self count] ifFalse: [self count + 1])
    op: (PBTuple withAll: { 'set'. key. stored }).

"A dictionary without aKey; for an absent key, a new version with the same
 content (ProtoBase's remove_at)."
PBDictionary >> removeAt: aKey
  | key removed |
  self _checkWritable: 'removeAt:'.
  key := self _canonical: aKey as: 'key'.
  removed := PBAvl keyRemove: (self stateAt: 'root') key: key.
  ^ self
    _withRoot: (removed at: 1)
    count: ((removed at: 2) ifTrue: [self count - 1] ifFalse: [self count])
    op: (PBTuple withAll: { 'remove'. key }).

PBDictionary class >> _logsOperations
  ^ true.

PBDictionary >> _replay: anOp onto: aTarget
  | kind |
  kind := anOp at: 1.
  kind = 'set' ifTrue: [^ aTarget setAt: (anOp at: 2) value: (anOp at: 3)].
  kind = 'remove' ifTrue: [^ aTarget removeAt: (anOp at: 2)].
  ^ super _replay: anOp onto: aTarget.

"=== PBHashDictionary ========================================================="

PBIndexedCollection subclass: #PBHashDictionary.
PBHashDictionary comment: 'Every message answers a new version; the receiver never changes. ProtoBase''s HashDictionary (proto_db.collections.HashDictionary): a map over a keyed AVL tree from the hash key of a key to a bucket tuple of (key, value) tuples; keys are equal by order key, so 1, 1.0 and Decimal 1.00 are one key and true another. setAt:value: and removeAt: answer the new dictionary (removeAt: of an absent key a new version with the same content); a statement that discards the result changes nothing. Each version logs its intents (opLog) for rebaseOnto:.'.

PBHashDictionary class >> typeName
  ^ 'proto_db.collections.HashDictionary'.

PBHashDictionary class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBHashDictionary class >> persistedFields
  ^ #('root' 'count' 'indexes').

"The hash a key is filed under (ProtoBase HashDictionary._bucket_hash): its
 hash key. A subclass may override it (to force collisions in a test), but
 it must stay a pure function of the key's value."
PBHashDictionary >> _bucketHash: aCanonical
  ^ PBKeys hashKey: aCanonical.

"The (key, value) entry of aKey, or nil."
PBHashDictionary >> _entryAt: aKey
  | found |
  found := _PBBuckets find: (self _probe: aKey) in: (self stateAt: 'root') pairs: true owner: self.
  ^ (found at: 3) = 0 ifTrue: [nil] ifFalse: [(found at: 2) at: (found at: 3)].

PBHashDictionary >> getAt: aKey
  ^ self getAt: aKey default: nil.

PBHashDictionary >> getAt: aKey default: aDefault
  | entry |
  entry := self _entryAt: aKey.
  ^ entry isNil ifTrue: [aDefault] ifFalse: [entry at: 2].

PBHashDictionary >> has: aKey
  ^ (self _entryAt: aKey) notNil.

"Evaluates aBlock with each key and its value: tree order, then bucket order."
PBHashDictionary >> keysAndValuesDo: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node |
    (_PBBuckets entriesOf: node value pairs: true in: self) do: [:entry |
      aBlock value: (entry at: 1) value: (entry at: 2)]].

PBHashDictionary >> do: aBlock
  self keysAndValuesDo: [:k :v | aBlock value: v].

PBHashDictionary >> keys
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k].
  ^ out asArray.

PBHashDictionary >> values
  ^ self elements.

PBHashDictionary >> items
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k -> v].
  ^ out asArray.

"--- writes (ProtoBase HashDictionary set_at, remove_at) ---"

"The MessagePack containers a bucket node value adds around a key and its
 value (format spec, 'Value nesting depth'): the bucket tuple and the entry
 (key, value), two @tup (ProtoBase HashDictionary.ENTRY_WRAPPING)."
PBHashDictionary class >> entryWrapping
  ^ 4.

PBHashDictionary class >> wrapper
  ^ 'its bucket entry (key, value) in its bucket tuple'.

"A hash dictionary with aKey mapped to aValue. The key must be hashable and
 orderable (a list, a map or a NaN is PBValidationError); an existing key
 keeps its stored key object and its place in the bucket."
PBHashDictionary >> setAt: aKey value: aValue
  | key value found entries position |
  self _checkWritable: 'setAt:value:'.
  key := self _canonical: aKey as: 'key' wrapping: self class entryWrapping by: self class wrapper.
  value := self _canonical: aValue as: 'value' wrapping: self class entryWrapping by: self class wrapper.
  found := _PBBuckets find: key in: (self stateAt: 'root') pairs: true owner: self.
  entries := found at: 2.
  position := found at: 3.
  position > 0
    ifTrue: [
      entries := entries copy.
      entries at: position put: (PBTuple withAll: { (entries at: position) at: 1. value })]
    ifFalse: [entries := entries copyWith: (PBTuple withAll: { key. value })].
  ^ self
    _withRoot: ((PBAvl keyPut: (self stateAt: 'root') key: (found at: 1) value: (PBTuple withAll: entries) nodeClass: PBKeyNode) at: 1)
    count: (position > 0 ifTrue: [self count] ifFalse: [self count + 1])
    op: (PBTuple withAll: { 'set'. key. value }).

"A hash dictionary without aKey; for an absent key, a new version with the
 same content (ProtoBase's remove_at)."
PBHashDictionary >> removeAt: aKey
  | key found op |
  self _checkWritable: 'removeAt:'.
  key := self _canonical: aKey as: 'key'.
  found := _PBBuckets find: key in: (self stateAt: 'root') pairs: true owner: self.
  op := PBTuple withAll: { 'remove'. key }.
  (found at: 3) = 0 ifTrue: [^ self _withRoot: (self stateAt: 'root') count: self count op: op].
  ^ self _withRoot: (_PBBuckets without: found in: (self stateAt: 'root')) count: self count - 1 op: op.

PBHashDictionary class >> _logsOperations
  ^ true.

PBHashDictionary >> _replay: anOp onto: aTarget
  | kind |
  kind := anOp at: 1.
  kind = 'set' ifTrue: [^ aTarget setAt: (anOp at: 2) value: (anOp at: 3)].
  kind = 'remove' ifTrue: [^ aTarget removeAt: (anOp at: 2)].
  ^ super _replay: anOp onto: aTarget.

"=== the hash sets ==========================================================="

Object subclass: #_PBBuckets.

"The entries of a bucket: a tuple of entries; with pairs, each entry is a
 2-item tuple. Anything else is PBCorruptionError."
_PBBuckets class >> entriesOf: aBucket pairs: aBoolean in: anOwner
  | entries |
  (aBucket isKindOf: PBTuple) ifFalse: [
    ^ PBCorruptionError signal: anOwner printString , ' holds a bucket that is not a tuple: '
      , (PBKeys _preview: aBucket)].
  entries := aBucket asArray.
  aBoolean ifTrue: [
    entries do: [:entry |
      ((entry isKindOf: PBTuple) and: [entry size = 2]) ifFalse: [
        ^ PBCorruptionError signal: anOwner printString , ' holds a bucket entry that is not a pair: '
          , (PBKeys _preview: entry)]]].
  ^ entries.

"{ bucket hash (anOwner _bucketHash:). entries of its bucket (an Array,
 empty when absent). 1-based position of the entry of aCanonical in them, or
 0 } (ProtoBase _HashBuckets._find and HashDictionary._find): the bucket hash
 first, then the order key, so a value that is neither hashable nor orderable is
 PBValidationError. With pairs, an entry's key is its first item."
_PBBuckets class >> find: aCanonical in: aRoot pairs: aBoolean owner: anOwner
  | h okey node entries |
  h := anOwner _bucketHash: aCanonical.
  okey := PBKeys orderKey: aCanonical.
  node := _PBTree nodeWithKey: (PBKeys orderKey: h) of: aRoot in: anOwner.
  node isNil ifTrue: [^ { h. Array new: 0. 0 }].
  entries := self entriesOf: node value pairs: aBoolean in: anOwner.
  1 to: entries size do: [:i |
    | entry |
    entry := entries at: i.
    (PBKeys orderKey: (aBoolean ifTrue: [entry at: 1] ifFalse: [entry])) = okey ifTrue: [^ { h. entries. i }]].
  ^ { h. entries. 0 }.

"The root aRoot without the entry that find:in:pairs:owner: answered as
 aFound (ProtoBase _put_bucket): its bucket without it, or no bucket when it
 was the last entry."
_PBBuckets class >> without: aFound in: aRoot
  | entries position rest |
  entries := aFound at: 2.
  position := aFound at: 3.
  rest := (entries copyFrom: 1 to: position - 1) , (entries copyFrom: position + 1 to: entries size).
  rest isEmpty ifTrue: [^ (PBAvl keyRemove: aRoot key: (aFound at: 1)) at: 1].
  ^ (PBAvl keyPut: aRoot key: (aFound at: 1) value: (PBTuple withAll: rest) nodeClass: PBKeyNode) at: 1.

PBIndexedCollection subclass: #PBHashBuckets.

PBHashBuckets class >> typeName
  ^ 'proto_db.collections.sets._HashBuckets'.

PBHashBuckets class >> requiredFields
  ^ #('root' 'count' 'indexes').

PBHashBuckets class >> persistedFields
  ^ #('root' 'count' 'indexes').

"Whether a bucket entry is an (element, count) pair."
PBHashBuckets >> _pairs
  ^ PBNotSupportedError signal: self class name , ': ' , self class typeName , ' is abstract: it has no elements'.

PBHashBuckets >> _elementOf: anEntry
  ^ self _pairs ifTrue: [anEntry at: 1] ifFalse: [anEntry].

"Evaluates aBlock with each entry: tree order, then bucket order."
PBHashBuckets >> entriesDo: aBlock
  | pairs |
  pairs := self _pairs.
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node |
    (_PBBuckets entriesOf: node value pairs: pairs in: self) do: aBlock].

PBHashBuckets >> do: aBlock
  self entriesDo: [:entry | aBlock value: (self _elementOf: entry)].

"The hash an element is filed under (ProtoBase _HashBuckets._bucket_hash):
 its hash key. A subclass may override it (to force collisions in a test),
 but it must stay a pure function of the element's value."
PBHashBuckets >> _bucketHash: aCanonical
  ^ PBKeys hashKey: aCanonical.

"The entry of anElement, or nil."
PBHashBuckets >> _entryAt: anElement
  | found |
  found := _PBBuckets find: (self _probe: anElement) in: (self stateAt: 'root') pairs: self _pairs owner: self.
  ^ (found at: 3) = 0 ifTrue: [nil] ifFalse: [(found at: 2) at: (found at: 3)].

PBHashBuckets >> has: anElement
  ^ (self _entryAt: anElement) notNil.

PBHashBuckets subclass: #PBSet.
PBSet comment: 'Every message answers a new version; the receiver never changes. ProtoBase''s Set (proto_db.collections.Set): a hash set over a keyed AVL tree from the hash key of an element to a bucket tuple of the elements of that hash; membership is by order key, so 1, 1.0 and Decimal 1.00 are one element and true another. add:, remove:, union:, intersection: and difference: answer the new set (unlike Pharo''s add: and remove:, which change the set in place and answer the element); a statement that discards the result changes nothing. Each version logs its intents (opLog) for rebaseOnto:.'.

PBSet class >> typeName
  ^ 'proto_db.collections.Set'.

PBSet >> _pairs
  ^ false.

"--- writes (ProtoBase Set add, remove, union, intersection, difference) ---"

PBSet class >> _logsOperations
  ^ true.

"The MessagePack containers a bucket node value adds around an element: the
 bucket tuple, a @tup (ProtoBase Set.ELEMENT_WRAPPING)."
PBSet class >> elementWrapping
  ^ 2.

PBSet class >> wrapper
  ^ 'its bucket tuple'.

"A set holding anElement; when it is present already, a new version with the
 same content. The element must be orderable (PBValidationError otherwise)."
PBSet >> add: anElement
  | element found op |
  self _checkWritable: 'add:'.
  element := self _canonical: anElement as: 'element' wrapping: self class elementWrapping by: self class wrapper.
  found := _PBBuckets find: element in: (self stateAt: 'root') pairs: false owner: self.
  op := PBTuple withAll: { 'add'. element }.
  (found at: 3) > 0 ifTrue: [^ self _withRoot: (self stateAt: 'root') count: self count op: op].
  ^ self
    _withRoot: ((PBAvl keyPut: (self stateAt: 'root') key: (found at: 1)
      value: (PBTuple withAll: ((found at: 2) copyWith: element)) nodeClass: PBKeyNode) at: 1)
    count: self count + 1
    op: op.

"A set without anElement; when it is absent, a new version with the same
 content (unlike Pharo's remove:, which signals)."
PBSet >> remove: anElement
  | element found op |
  self _checkWritable: 'remove:'.
  element := self _canonical: anElement as: 'element'.
  found := _PBBuckets find: element in: (self stateAt: 'root') pairs: false owner: self.
  op := PBTuple withAll: { 'remove'. element }.
  (found at: 3) = 0 ifTrue: [^ self _withRoot: (self stateAt: 'root') count: self count op: op].
  ^ self _withRoot: (_PBBuckets without: found in: (self stateAt: 'root')) count: self count - 1 op: op.

"This set plus every element of aCollection (a set, or anything answering
 do:): add: of each element in aCollection's order, so each is logged."
PBSet >> union: aCollection
  | elements result |
  elements := self _elementsOf: aCollection for: 'union:'.
  result := self _newVersion.
  1 to: elements size do: [:i | result := result add: (elements at: i)].
  ^ result.

"The members of this set that are in aCollection (a set, or anything
 answering do:, whose elements must be orderable, read in full first):
 remove: of each other member, in this set's order."
PBSet >> intersection: aCollection
  | keep orderKeys elements members result |
  (aCollection isClassObject not and: [aCollection isKindOf: PBHashBuckets])
    ifTrue: [keep := aCollection]
    ifFalse: [
      "ProtoBase builds Set.from_iterable(other): membership by order key."
      elements := self _elementsOf: aCollection for: 'intersection:'.
      orderKeys := Dictionary new.
      1 to: elements size do: [:i | orderKeys at: (PBKeys orderKey: (self _canonical: (elements at: i) as: 'element'
        wrapping: self class elementWrapping by: self class wrapper)) put: true]].
  members := self elements.
  result := self _newVersion.
  1 to: members size do: [:i |
    | member |
    member := members at: i.
    (keep isNil
        ifTrue: [orderKeys includesKey: (PBKeys orderKey: member)]
        ifFalse: [keep has: member])
      ifFalse: [result := result remove: member]].
  ^ result.

"The members of this set that are not in aCollection (a set, or anything
 answering do:): remove: of each element of aCollection, in its order."
PBSet >> difference: aCollection
  | elements result |
  elements := self _elementsOf: aCollection for: 'difference:'.
  result := self _newVersion.
  1 to: elements size do: [:i | result := result remove: (elements at: i)].
  ^ result.

PBSet >> _replay: anOp onto: aTarget
  | kind |
  kind := anOp at: 1.
  kind = 'add' ifTrue: [^ aTarget add: (anOp at: 2)].
  kind = 'remove' ifTrue: [^ aTarget remove: (anOp at: 2)].
  ^ super _replay: anOp onto: aTarget.

PBHashBuckets subclass: #PBCountedSet.
PBCountedSet comment: 'Every message answers a new version; the receiver never changes. ProtoBase''s CountedSet (proto_db.collections.CountedSet): a hash set whose bucket entries are (element, count) pairs; count is the number of distinct elements and totalCount the sum of the counts. add: adds one occurrence and remove: removes one (an absent element: a new version with the same content), each answering the new set (unlike Pharo''s add: and remove:, which change the collection in place and answer the element); a statement that discards the result changes nothing. Each version logs its intents (opLog) for rebaseOnto:, which applies their composed counter transform per element (D26).'.

PBCountedSet class >> typeName
  ^ 'proto_db.collections.CountedSet'.

PBCountedSet class >> requiredFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBCountedSet class >> persistedFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBCountedSet class >> _emptyValueOf: aField
  aField = 'total_count' ifTrue: [^ 0].
  ^ super _emptyValueOf: aField.

PBCountedSet >> _pairs
  ^ true.

"ConcurrentOptimized, as ProtoBase's CountedSet."
PBCountedSet class >> _logsOperations
  ^ true.

"The sum of the counts."
PBCountedSet >> totalCount
  ^ _PBTree integer: (self stateAt: 'total_count') field: 'total_count' of: self.

"The number of occurrences of anElement (0 when absent)."
PBCountedSet >> countOf: anElement
  | entry |
  entry := self _entryAt: anElement.
  ^ entry isNil ifTrue: [0] ifFalse: [_PBTree integer: (entry at: 2) field: 'count of an element' of: self].

"Evaluates aBlock with each element and its count."
PBCountedSet >> keysAndValuesDo: aBlock
  self entriesDo: [:entry | aBlock value: (entry at: 1) value: (entry at: 2)].

"element -> count Associations: tree order, then bucket order."
PBCountedSet >> items
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:e :n | out add: e -> n].
  ^ out asArray.

"--- writes (ProtoBase CountedSet add, remove, _transform; D26) ---"

"The MessagePack containers a bucket node value adds around an element: the
 bucket tuple and the entry (element, count), two @tup (ProtoBase
 CountedSet.ELEMENT_WRAPPING)."
PBCountedSet class >> elementWrapping
  ^ 4.

PBCountedSet class >> wrapper
  ^ 'its bucket entry (element, count) in its bucket tuple'.

"The counter transform (removes, adds) applied to aCount (ProtoBase
 counter_transform): removes clamp at 0 before the adds."
PBCountedSet class >> transform: aCount removes: aRemoves adds: anAdds
  ^ ((aCount - aRemoves) max: 0) + anAdds.

"A counted set with one more occurrence of anElement. The element must be
 orderable (PBValidationError otherwise); a present one keeps its stored
 element object and its place in the bucket."
PBCountedSet >> add: anElement
  | element |
  self _checkWritable: 'add:'.
  element := self _canonical: anElement as: 'element' wrapping: self class elementWrapping by: self class wrapper.
  ^ self _step: element removes: 0 adds: 1 op: (PBTuple withAll: { 'add'. element }).

"A counted set with one occurrence fewer of anElement (the last one takes
 the element out); when it is absent, a new version with the same content
 (unlike Pharo's remove:, which signals). As ProtoBase's remove, the element
 is made canonical but its wrapping is not checked: it is never stored."
PBCountedSet >> remove: anElement
  | element |
  self _checkWritable: 'remove:'.
  element := self _canonical: anElement as: 'element'.
  ^ self _step: element removes: 1 adds: 0 op: (PBTuple withAll: { 'remove'. element }).

"The counter transform (removes, adds) applied to anElement as one
 adjustment, logged as ('transform' element removes adds) so that a rebased
 version can itself be rebased (ProtoBase CountedSet._transform). Only
 rebaseOnto: sends it."
PBCountedSet >> _transform: anElement removes: aRemoves adds: anAdds
  | element |
  self _checkWritable: 'rebaseOnto:'.
  element := self _canonical: anElement as: 'element' wrapping: self class elementWrapping by: self class wrapper.
  ^ self _step: element removes: aRemoves adds: anAdds
    op: (PBTuple withAll: { 'transform'. element. aRemoves. anAdds }).

"The version where aCanonical occurs as often as the counter transform
 (removes, adds) makes it, with anOp logged (ProtoBase CountedSet._step and
 _retarget_at): an unchanged count keeps the content, a count that stays
 positive replaces the entry in place, a new element is appended to its
 bucket, and a count that drops to 0 takes the entry out (and an emptied
 bucket leaves the tree)."
PBCountedSet >> _step: aCanonical removes: aRemoves adds: anAdds op: anOp
  | root found entries position n final total |
  root := self stateAt: 'root'.
  found := _PBBuckets find: aCanonical in: root pairs: true owner: self.
  entries := found at: 2.
  position := found at: 3.
  n := position = 0
    ifTrue: [0]
    ifFalse: [_PBTree integer: ((entries at: position) at: 2) field: 'count of an element' of: self].
  final := self class transform: n removes: aRemoves adds: anAdds.
  final = n ifTrue: [^ self _withRoot: root count: self count op: anOp].
  total := self totalCount + final - n.
  (n > 0 and: [final > 0]) ifTrue: [
    entries := entries copy.
    entries at: position put: (PBTuple withAll: { (entries at: position) at: 1. final }).
    ^ self _withChanges: {
        'root' -> ((PBAvl keyPut: root key: (found at: 1) value: (PBTuple withAll: entries) nodeClass: PBKeyNode) at: 1).
        'total_count' -> total }
      op: anOp].
  final > 0 ifTrue: [
    ^ self _withChanges: {
        'root' -> ((PBAvl keyPut: root key: (found at: 1)
          value: (PBTuple withAll: (entries copyWith: (PBTuple withAll: { aCanonical. final }))) nodeClass: PBKeyNode) at: 1).
        'count' -> (self count + 1).
        'total_count' -> total }
      op: anOp].
  ^ self _withChanges: {
      'root' -> (_PBBuckets without: found in: root).
      'count' -> (self count - 1).
      'total_count' -> total }
    op: anOp.

"The ops rebaseOnto: replays (ProtoBase CountedSet._net_ops and
 counter_net_effect, D26): per element, the composition of its ops as one
 counter transform (removes, adds). add is (0, 1), remove is (1, 0),
 transform its own pair, and (r1, a1) followed by (r2, a2) is
 (r1, a1 - r2 + a2) when a1 >= r2, otherwise (r1 + r2 - a1, a2), so applying
 the result to any count equals applying the ops one by one. Answers
 ('net' element removes adds) tuples in order of last occurrence, elements
 compared by order key (the first element object of each is kept); an
 identity transform (0, 0) is omitted. O(n) in the length of the log."
PBCountedSet >> _netOps
  | ops keys last net out |
  ops := _PBOpLog opsOf: log.
  keys := Array new: ops size.
  last := Dictionary new.
  net := Dictionary new.
  1 to: ops size do: [:i |
    | op kind r a okey entry |
    op := ops at: i.
    kind := op at: 1.
    kind = 'add'
      ifTrue: [r := 0. a := 1]
      ifFalse: [
        kind = 'remove'
          ifTrue: [r := 1. a := 0]
          ifFalse: [
            kind = 'transform'
              ifTrue: [r := op at: 3. a := op at: 4]
              ifFalse: [^ PBValidationError signal: 'Unknown counter op kind ' , kind printString]]].
    okey := PBKeys orderKey: (op at: 2).
    keys at: i put: okey.
    last at: okey put: i.
    entry := net at: okey ifAbsent: [net at: okey put: { op at: 2. 0. 0 }].
    (entry at: 3) >= r
      ifTrue: [entry at: 3 put: (entry at: 3) + a - r]
      ifFalse: [
        entry at: 2 put: (entry at: 2) + r - (entry at: 3).
        entry at: 3 put: a]].
  out := OrderedCollection new.
  1 to: ops size do: [:i |
    | entry |
    (last at: (keys at: i)) = i ifTrue: [
      entry := net at: (keys at: i).
      ((entry at: 2) = 0 and: [(entry at: 3) = 0]) ifFalse: [
        out addLast: (PBTuple withAll: { 'net'. entry at: 1. entry at: 2. entry at: 3 })]]].
  ^ out asArray.

PBCountedSet >> _replay: anOp onto: aTarget
  (anOp at: 1) = 'net' ifFalse: [
    ^ PBValidationError signal: 'Unknown ' , self class name , ' net op ' , anOp printString].
  ^ aTarget _transform: (anOp at: 2) removes: (anOp at: 3) adds: (anOp at: 4).

"=== PBRepeatedKeysDictionary ================================================="

PBIndexedCollection subclass: #PBRepeatedKeysDictionary.

PBRepeatedKeysDictionary class >> typeName
  ^ 'proto_db.collections.RepeatedKeysDictionary'.

PBRepeatedKeysDictionary class >> requiredFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBRepeatedKeysDictionary class >> persistedFields
  ^ #('root' 'count' 'total_count' 'indexes').

PBRepeatedKeysDictionary class >> _emptyValueOf: aField
  aField = 'total_count' ifTrue: [^ 0].
  ^ super _emptyValueOf: aField.

"ConcurrentOptimized, as ProtoBase's RepeatedKeysDictionary; it has no
 mutators here (its writes are a non-goal), so its log stays empty."
PBRepeatedKeysDictionary class >> _logsOperations
  ^ true.

PBRepeatedKeysDictionary >> totalCount
  ^ _PBTree integer: (self stateAt: 'total_count') field: 'total_count' of: self.

PBRepeatedKeysDictionary >> _recordsOf: aNode
  ^ _PBTree node: aNode value kind: PBCountedSet in: self.

"The PBCountedSet of the records under aKey (an empty one, not stored, when
 absent)."
PBRepeatedKeysDictionary >> getAt: aKey
  | node |
  node := self _nodeAt: aKey.
  ^ node isNil ifTrue: [PBCountedSet new] ifFalse: [self _recordsOf: node].

PBRepeatedKeysDictionary >> has: aKey
  ^ (self _nodeAt: aKey) notNil.

PBRepeatedKeysDictionary >> _nodeAt: aKey
  | key |
  key := self _probe: aKey.
  ^ _PBTree nodeWithKey: (PBKeys orderKey: key) of: (self stateAt: 'root') in: self.

"Evaluates aBlock with each key and its PBCountedSet, in key order."
PBRepeatedKeysDictionary >> keysAndValuesDo: aBlock
  _PBTree nodesOf: (self stateAt: 'root') kind: PBKeyNode in: self do: [:node |
    aBlock value: node key value: (self _recordsOf: node)].

"Each distinct record of each key, key by key (the elements)."
PBRepeatedKeysDictionary >> do: aBlock
  self keysAndValuesDo: [:k :records | records do: aBlock].

PBRepeatedKeysDictionary >> keys
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k].
  ^ out asArray.

PBRepeatedKeysDictionary >> values
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: v].
  ^ out asArray.

"key -> PBCountedSet Associations, in key order."
PBRepeatedKeysDictionary >> items
  | out |
  out := OrderedCollection new.
  self keysAndValuesDo: [:k :v | out add: k -> v].
  ^ out asArray.

{ PBIndexSet. PBIndexedCollection. PBList. PBDictionary. PBHashDictionary. PBHashBuckets. PBSet.
  PBCountedSet. PBRepeatedKeysDictionary } do: [:each | PBTypeRegistry register: each].

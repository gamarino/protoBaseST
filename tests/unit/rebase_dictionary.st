"EXPECT: ok 18"
"PBDictionary rebaseOnto: (plan Task 16; ProtoBase ConcurrentOptimized.rebase_onto and
 Dictionary._replay_op): the net effect of the receiver's operation log (the last intent per
 key, keys compared by order key, in order of last occurrence) replayed onto another version
 through setAt:value: and removeAt:. The expected contents are ProtoBase v2.0.0rc1's answers
 for the same calls. A current of another class is PBValidationError (ProtoBase's
 ProtoValidationError). A current with an index is merged onto, its indexes maintained (indexed
 queries plan Task 4b; before it, PBNotSupportedError, plan call IP17)."
Import from: 'protobase'.
Import from: '_check'.

| c a current merged x y ynet yr base dir space people |
c := Check new.
"The root 'people' of the database vector is a Dictionary with the indexes by_age and by_city."
base := FileSystem temp / ('pbst-rebase-dictionary-' , Smalltalk pid printString).
base deleteAll.
dir := base / 'database'.
dir ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: dir / f basename].
space := PBObjectSpace storage: (PBFileStorage path: dir).
people := ((space openDatabase: 'db') snapshotAt: (space openDatabase: 'db') history first) getRootObject: 'people'.
a := PBDictionary new setAt: 'a' value: 1.
current := PBDictionary new setAt: 'b' value: 2.
merged := a rebaseOnto: current.
c that: 'the rebase holds both' is: merged items equals: { 'a' -> 1. 'b' -> 2 }.
c that: 'the current version is unchanged' is: current items equals: { 'b' -> 2 }.
c that: 'the receiver is unchanged' is: a items equals: { 'a' -> 1 }.
c that: 'the replay goes through the mutators: current''s log then the replayed op'
  is: merged opLog equals: (PBFrozenList withAll: {
    PBTuple withAll: #('set' 'b' 2). PBTuple withAll: #('set' 'a' 1) }).

"Set then remove of one key nets to remove."
x := ((PBDictionary new setAt: 'k' value: 1) setAt: 'j' value: 7) removeAt: 'k'.
c that: 'the log holds every intent' is: x opLog size equals: 3.
c that: 'set then remove nets to remove'
  is: (x rebaseOnto: ((PBDictionary new setAt: 'k' value: 9) setAt: 'z' value: 0)) items
  equals: { 'j' -> 7. 'z' -> 0 }.

"Keys by order key: 1, 1.0 and Decimal 1.00 are one key, whose last intent wins; the order
 of replay is the order of last occurrence."
y := ((((PBDictionary new removeAt: 'k') setAt: 1 value: 'a') setAt: 1.0 value: 'b')
  setAt: 'm' value: 1) setAt: (Decimal fromString: '1.00') value: 'c'.
ynet := y _netOps.
c that: 'the net effect: one op per key' is: ynet size equals: 3.
c that: 'in order of last occurrence' is: (ynet collect: [:op | op at: 1]) asArray equals: #('remove' 'set' 'set').
c that: 'the last intent of the key 1' is: ((ynet at: 3) at: 3) equals: 'c'.
c that: 'the key object of the last intent' is: ((ynet at: 3) at: 2) class equals: Decimal.
yr := y rebaseOnto: (PBDictionary new setAt: 1.0 value: 'old').
c that: 'replayed onto a current holding 1.0: the stored key object is kept'
  is: yr keys first class equals: Float.
c that: 'and the last value wins' is: yr items equals: { 1.0 -> 'c'. 'm' -> 1 }.

"An empty log answers the current version's content."
c that: 'an empty log' is: (PBDictionary new rebaseOnto: current) items equals: current items.
c that: 'a remove of a key absent from current is a no-op there'
  is: ((PBDictionary new removeAt: 'q') rebaseOnto: current) items equals: current items.

"Refusals."
c that: 'a current of another class' signals: PBValidationError containing: 'PBHashDictionary'
  during: [a rebaseOnto: PBHashDictionary new].
c that: 'a current that is not a collection' signals: PBValidationError during: [a rebaseOnto: 3].
"Onto an indexed current (Task 4b)."
c that: 'a current with an index is merged onto: the key added, the indexes kept and valid'
  is: ([:m | { m count - people count. m getAt: 'a'. m indexNames asArray. [m validate. true] value }]
    value: (a rebaseOnto: people))
  equals: { 1. 1. people indexNames asArray. true }.
c that: 'an empty log answers the indexed current itself' is: (PBDictionary new rebaseOnto: people) == people equals: true.
space close.
base deleteAll.
c report displayNl.

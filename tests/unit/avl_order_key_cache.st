"EXPECT: ok 12"
"Fix round 1 of plan Task 14 (review I1, I2): a keyed node caches the order key of its key,
 as ProtoBase's KeyNode._okey: a write-once cell, never persisted, published by
 compare-and-swap. A node a write builds holds it from the start (the put's order key, or
 the copied node's); a stored node (a stub) fills it on its first use. And check: turns
 only an invalid key or weighted value into PBCorruptionError: a closed storage met while
 checking a stored tree is PBClosedError, as every load."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.
| c root node copy base b sorted tree storage seg stub child dbRoot okeys |
c := Check new.
root := nil.
1 to: 20 do: [:i | root := (PBAvl keyPut: root key: i value: i * 10 nodeClass: PBKeyNode) first].
node := PBAvl keyAt: root key: 7.
c that: 'a built node holds its order key' is: node knownOrderKey equals: (PBKeys orderKey: 7).
okeys := OrderedCollection new.
PBAvl nodesDo: [:n | okeys add: n knownOrderKey] over: root.
c that: 'every built node holds it' isTrue: (okeys allSatisfy: [:k | k notNil]).
copy := (PBAvl keyPut: root key: 7 value: 'seven' nodeClass: PBKeyNode) first.
c that: 'a copy keeps the stored key''s order key object' isTrue:
  (PBAvl keyAt: copy key: 7) knownOrderKey == node knownOrderKey.
c that: 'a put of 7.0 finds 7 by its cached order key' is: (PBAvl keyAt: copy key: 7.0) value equals: 'seven'.
"A stored tree: 15 KeyNode records under a space root."
base := FileSystem temp / ('pbst-avl-okey-' , Smalltalk pid printString).
base deleteAll.
seg := ByteArray fromHex: '5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a'.
b := SpaceBuilder segment: seg.
sorted := (1 to: 15) asArray collect: [:i | (i * 2) -> ('v' , i printString)].
tree := b _tree: sorted from: 1 to: 15 oids: [| n | n := 0. [n := n + 1. n]] value.
dbRoot := b spaceWithDatabase: 'db' roots: #() mutables: #() oids: 100.
storage := PBFileStorage path: (b writeTo: base / 'space' root: dbRoot).
stub := storage refTo: seg offset: tree first pointer offset tag: 0.
c that: 'a stub holds no order key before its first use' is: stub knownOrderKey equals: nil.
c that: 'a lookup finds a stored key' is: (PBAvl keyAt: stub key: 10) value equals: 'v5'.
c that: 'the stub filled it on first use' is: stub knownOrderKey equals: (PBKeys orderKey: stub key).
c that: 'check: passes on the stored tree' isTrue: (PBAvl check: stub) == stub.
"Load the root, close the storage, check: the loads inside the walk fail closed."
stub := storage refTo: seg offset: tree first pointer offset tag: 0.
stub height.
child := stub left.
c that: 'the child is not loaded yet' is: child isLoaded equals: false.
storage close.
c that: 'a closed storage during check: is PBClosedError' signals: PBClosedError during: [PBAvl check: stub].
c that: 'and not corruption' is: ([PBAvl check: stub. 'no error'] on: Error do: [:e | e return: e class name]) equals: 'PBClosedError'.
c that: 'an invalid key is still corruption' signals: PBCorruptionError during: [
  PBAvl check: (PBKeyNode _unsavedWithState: (PBFrozenDict withAssociations: {
    'key' -> (PBFrozenList withAll: #(1)). 'value' -> 0. 'left' -> nil. 'right' -> nil. 'height' -> 1. 'count' -> 1 }))].
base deleteAll.
c report displayNl.

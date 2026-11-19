"atom_weight/probe.st: the cells an atom, a node and their parts cost (plan Tasks 11 and 12;
 .superpowers analysis 'atom weight'). run_atom_weight.sh drives it.

 Usage: protost probe.st <kind> <n> <mode> [churn]
   mode alloc: n objects of the kind are built between the markers
               Smalltalk getenv: 'AW_ON:<label>' and 'AW_OFF', three rounds; count.py (under gdb)
               counts protoCore's cell allocations between them (cells allocated per object =
               count / n, from the last round).
   mode keep : n objects of the kind are kept live, then 'CHURN' is printed and short-lived
               garbage is made (churn Arrays, default 3000000), so the GC cycles that follow
               (PROTOCORE_HEAP_TRACE=1, their L= live counts) measure the settled live set;
               minus kind 'none', over n, it is the cells retained per object.
 kind build is one tree of n nodes (PBAvl keyFromSorted:, PBCountedKeyNode), not n objects:
 its figures are per node.

 kinds loaded and loadedcache (plan Task 12) read such a tree of n nodes, written by another
 process (mode write: protost probe.st loaded <n> write, into the directory AW_STORE, which
 prints 'PTR <segment hex> <offset>'), from AW_STORE at AW_PTR ('<segment hex> <offset>'):
 loaded with the atom cache off, loadedcache with the default cache. keep: every node is loaded
 (its key and order key read) and the tree kept, so the figure is the cells a loaded node
 retains (with loadedcache, plus its cache entry). alloc: each round loads every node of a new
 stub of the root, so the figure is the cells one record load allocates, the decode included
 (loadedcache: the first round fills the cache, the third reads it).
 kind oiddraw: n oids drawn (_PBOidPool next).

 Every run verifies its work and prints 'WORK <kind> <n> <checksum>' (the objects counted by
 class, the tree's count and weight), then 'atom_weight ok'."
Import from: 'protobase'.

| kind n mode churn e ok v blocks blk keep pairs check build sum storage load loadedKinds ptrArgs dir |
kind := Smalltalk arguments at: 1.
n := (Smalltalk arguments at: 2) asInteger.
mode := Smalltalk arguments at: 3.
churn := Smalltalk arguments size >= 4 ifTrue: [(Smalltalk arguments at: 4) asInteger] ifFalse: [3000000].
e := PBObject withAll: { 'id' -> 1 }.
ok := PBKeys orderKey: 5.
v := PBTuple withAll: { e. 1 }.
blocks := Dictionary new.
blocks at: 'none' put: [:i | i].
blocks at: 'tuple2' put: [:i | PBTuple withAll: { i. 1 }].
blocks at: 'tupletrusted' put: [:i | PBTuple _trustedOn: { i. 1 }].
blocks at: 'atomshell' put: [:i | PBCountedKeyNode basicNew _setOid: nil pointer: nil storage: nil].
blocks at: 'nodeshell' put: [:i | PBCountedKeyNode key: i orderKey: ok value: v left: nil right: nil].
blocks at: 'nodeown' put: [:i |
  PBCountedKeyNode key: i orderKey: (PBKeys orderKey: i) value: (PBTuple withAll: { i. 1 }) left: nil right: nil].
blocks at: 'nodeoid' put: [:i | | a | a := PBCountedKeyNode key: i orderKey: ok value: v left: nil right: nil. a oid. a].
blocks at: 'oiddraw' put: [:i | _PBOidPool next].
"The check of a kept object: 1 for an object of the expected kind, so the sum is n."
check := Dictionary new.
check at: 'none' put: [:o | o isInteger ifTrue: [1] ifFalse: [0]].
check at: 'tuple2' put: [:o | ((o isKindOf: PBTuple) and: [o size = 2]) ifTrue: [1] ifFalse: [0]].
check at: 'tupletrusted' put: (check at: 'tuple2').
check at: 'atomshell' put: [:o | ((o isKindOf: PBCountedKeyNode) and: [o isLoaded not]) ifTrue: [1] ifFalse: [0]].
check at: 'nodeshell' put: [:o | ((o isKindOf: PBCountedKeyNode) and: [o weight = 1 and: [o orderKey == ok]]) ifTrue: [1] ifFalse: [0]].
check at: 'nodeown' put: [:o | ((o isKindOf: PBCountedKeyNode) and: [o weight = 1 and: [o orderKey = (PBKeys orderKey: o key)]]) ifTrue: [1] ifFalse: [0]].
check at: 'nodeoid' put: [:o | ((o isKindOf: PBCountedKeyNode) and: [o knownOid size = 16]) ifTrue: [1] ifFalse: [0]].
check at: 'oiddraw' put: [:o | ((o isKindOf: ByteArray) and: [o size = 16 and: [((o at: 7) bitAnd: 16rF0) = 16r40]]) ifTrue: [1] ifFalse: [0]].
build := [PBAvl keyFromSorted: pairs nodeClass: PBCountedKeyNode].
loadedKinds := #('loaded' 'loadedcache').
kind = 'build' | (mode = 'write') ifTrue: [pairs := (1 to: n) asArray collect: [:i | { i. PBTuple withAll: { i. 1 } }]].
dir := Smalltalk getenv: 'AW_STORE'.
"mode write: the tree of n nodes, saved into AW_STORE (no cache), for the loaded kinds."
mode = 'write' ifTrue: [
  keep := build value.
  storage := PBFileStorage path: dir atomCacheEntries: 0.
  ptrArgs := storage save: keep.
  storage flushSegment.
  storage close.
  ('PTR ' , ptrArgs segmentHex , ' ' , ptrArgs offset printString) displayNl].
"load value: a new stub of the stored root, every node loaded (its key and order key read);
 answers the stub."
(loadedKinds includes: kind) & (mode ~= 'write') ifTrue: [
  storage := kind = 'loaded' ifTrue: [PBFileStorage path: dir atomCacheEntries: 0] ifFalse: [PBFileStorage path: dir].
  ptrArgs := (Smalltalk getenv: 'AW_PTR') subStrings: ' '.
  load := [| stub |
    stub := PBCountedKeyNode unloadedAt: (PBAtomPointer segment: (ByteArray fromHex: ptrArgs first)
      offset: ptrArgs last asInteger) storage: storage.
    PBAvl nodesDo: [:node | node key. node orderKey] over: stub.
    stub]].
mode = 'alloc' ifTrue: [
  (loadedKinds includes: kind) ifTrue: [
    1 to: 3 do: [:round |
      Smalltalk getenv: 'AW_ON:' , kind , ' x' , n printString.
      keep := load value.
      Smalltalk getenv: 'AW_OFF']].
  kind = 'build'
    ifTrue: [
      1 to: 3 do: [:round |
        Smalltalk getenv: 'AW_ON:' , kind , ' x' , n printString.
        keep := build value.
        Smalltalk getenv: 'AW_OFF']]
    ifFalse: [(loadedKinds includes: kind) ifFalse: [
      blk := blocks at: kind.
      keep := Array new: n.
      1 to: 3 do: [:round |
        Smalltalk getenv: 'AW_ON:' , kind , ' x' , n printString.
        1 to: n do: [:i | keep at: i put: (blk value: i)].
        Smalltalk getenv: 'AW_OFF']]]].
mode = 'keep' ifTrue: [
  (loadedKinds includes: kind)
    ifTrue: [keep := load value]
    ifFalse: [
      kind = 'build'
        ifTrue: [keep := build value. pairs := nil]
        ifFalse: [blk := blocks at: kind. keep := (1 to: n) asArray collect: [:i | blk value: i]]].
  'CHURN' displayNl.
  1 to: churn do: [:i | Array with: i with: i]].
(kind = 'build' or: [mode = 'write' or: [loadedKinds includes: kind]])
  ifTrue: [
    (keep count = n and: [keep weight = n]) ifFalse: [Error signal: kind , ': a tree of ' , keep count printString , ' nodes'].
    sum := keep count + keep weight]
  ifFalse: [
    sum := keep inject: 0 into: [:a :o | a + ((check at: kind) value: o)].
    sum = n ifFalse: [Error signal: kind , ': ' , sum printString , ' of ' , n printString , ' objects are of the kind']].
('WORK ' , kind , ' ' , n printString , ' ' , sum printString) displayNl.
storage isNil ifFalse: [storage isClosed ifFalse: [storage close]].
'atom_weight ok' displayNl.

"EXPECT: ok 5"
"The atom cache under concurrent loads: six actors each load, three times, 200 records
 that all refer to one other record, through new stubs, while the cache is filled and
 read at once. Every value is right, every reference is answered as a new, unloaded stub
 of its own, and loading one of them leaves every other unloaded. A second round runs with
 a cache bound far smaller than the records, so the actors insert, evict and promote at
 once; the values stay right. The outcome does not depend on the interleaving."
Import from: 'protobase'.
Import from: '_check'.

Object subclass: #CacheLoader instanceVariableNames: 'storage pointers'.
CacheLoader >> storage: aStorage pointers: anArray
  storage := aStorage.
  pointers := anArray.
"{ all values right. the reference stubs answered }"
CacheLoader >> run
  | ok refs |
  ok := true.
  refs := OrderedCollection new.
  1 to: 3 do: [:round |
    pointers doWithIndex: [:p :i | | stub r |
      stub := PBObject unloadedAt: p storage: storage.
      (stub at: 'i') = i ifFalse: [ok := false].
      r := stub at: 'ref'.
      r isLoaded ifTrue: [ok := false].
      refs add: r]].
  ^ { ok. refs }.

| c base st other ptrs results refs run |
c := Check new.
base := FileSystem temp / ('pbst-cache-actors-' , Smalltalk pid printString).
base deleteAll.
run := [:aStorage | | o ps |
  o := PBObject withAll: { 'name' -> 'other' }.
  aStorage save: o.
  ps := (1 to: 200) asArray collect: [:i | aStorage save: (PBObject withAll: { 'i' -> i. 'ref' -> o })].
  ((1 to: 6) collect: [:k | (CacheLoader new storage: aStorage pointers: ps; yourself) asActor])
    collect: [:actor | actor run]].
st := PBFileStorage path: (base / 'big') pathString.
results := (run value: st) collect: [:f | f wait].
c that: 'six actors: every value right, every reference unloaded' isTrue: (results allSatisfy: [:r | r first]).
refs := OrderedCollection new.
results do: [:r | refs addAll: r last].
(refs first) at: 'name'.
"Were any two loads to share a stub, loading one would show the other loaded."
c that: 'every load answered a stub of its own: loading one leaves every other unloaded' isTrue: (refs allButFirst noneSatisfy: [:r | r isLoaded]).
c that: 'and they all name one record' is: (refs collect: [:r | r pointer]) asSet size equals: 1.
st close.
st := PBFileStorage path: (base / 'small') pathString atomCacheEntries: 16.
results := (run value: st) collect: [:f | f wait].
c that: 'with a tiny bound (evicting while loading): every value right' isTrue: (results allSatisfy: [:r | r first]).
c that: 'and the bound holds' isTrue: st atomCacheSize <= 16.
st close.
base deleteAll.
c report displayNl.

"EXPECT: ok 10"
"A collection with an index refuses every change (plan Task 15, design spec 7.4):
 ProtoBase updates the indexes in the same step as the content, which protoBaseST cannot
 do, so it signals PBNotSupportedError naming the indexes rather than answer a version
 whose indexes are stale. Run on a copy of the database vector: its root 'people' is a
 Dictionary with the indexes by_age and by_city, 'hnsw' a List with the index hnsw. A
 collection without indexes ('tags') is written as usual. extend: of nothing answers the
 receiver even when indexed, as ProtoBase returns before it touches the indexes. Reads
 of the indexed collections are unaffected."
Import from: 'protobase'.
Import from: '_check'.

| c base dir space snap people hnsw tags |
c := Check new.
base := FileSystem temp / ('pbst-indexed-refusal-' , Smalltalk pid printString).
base deleteAll.
dir := base / 'database'.
dir ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: dir / f basename].
space := PBObjectSpace storage: (PBFileStorage path: dir).
snap := (space openDatabase: 'db') snapshotAt: (space openDatabase: 'db') history first.
people := snap getRootObject: 'people'.
hnsw := snap getRootObject: 'hnsw'.
tags := snap getRootObject: 'tags'.
c that: 'people has indexes' is: people indexNames equals: #('by_age' 'by_city').
c that: 'setAt:value: on the indexed root' signals: PBNotSupportedError containing: 'by_age'
  during: [people setAt: 'zed' value: 1].
c that: 'the text names every index' signals: PBNotSupportedError containing: 'by_city'
  during: [people setAt: 'zed' value: 1].
c that: 'removeAt: too' signals: PBNotSupportedError containing: 'by_age' during: [people removeAt: 'zed'].
c that: 'an indexed List: appendLast:' signals: PBNotSupportedError containing: 'hnsw' during: [hnsw appendLast: 1].
c that: 'an indexed List: sliceFrom:to:' signals: PBNotSupportedError containing: 'hnsw' during: [hnsw head: 1].
c that: 'extend: nothing on an indexed list answers it, as ProtoBase' isTrue: (hnsw extend: #()) == hnsw.
c that: 'reads still work' is: people count equals: (people keys size).
c that: 'a List without indexes is written' is: (tags appendLast: 'new') count equals: tags count + 1.
c that: 'and keeps its index set' isTrue: ((tags appendLast: 'new') stateAt: 'indexes') == (tags stateAt: 'indexes').
space close.
base deleteAll.
c report displayNl.

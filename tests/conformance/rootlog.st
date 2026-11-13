"EXPECT: roots log ok"
"The acceptor log of the cluster section (README, 'Using the vectors', 8) and the invalid
 vectors of layer 'roots_log', read with PBAcceptorLog:
   roots.log        decode:path: of its payloads gives the manifest's entries in order, field by
                    field (kind, label, root, seq, pred, records as segment, offset and length,
                    ranges, flags; a field the manifest does not list is nil), each payload of
                    the listed size; load of a copy (opened with path:) answers the manifest's
                    root and label as its accepted and committed roots and the manifest's loaded
                    values (accepted, committed, promised, top, empty), and counts the kind-5
                    and kind-6 entries; encode:label:root: of each kind 1-4 entry gives its
                    payload byte for byte
   invalid rootlog-* each file scans (PBFramedLog) to payloads that decode:path: refuses with
                    PBCorruptionError"
Import from: 'protobase'.
Import from: '_vectors'.
| manifest cluster failures entry scan roots listed describeRoot describeLabeled describeTriples kinds base copy log loaded loadedSpec invalid |
manifest := Vectors manifest.
cluster := manifest at: 'cluster'.
failures := OrderedCollection new.
entry := cluster at: 'roots_log'.
listed := entry at: 'entries'.

"A root as the manifest lists it: nil, or a Dictionary segment (hex), offset, epoch."
describeRoot := [:aRecord |
  aRecord isNil
    ifTrue: [nil]
    ifFalse: [Dictionary new at: 'segment' put: aRecord segmentHex; at: 'offset' put: aRecord offset; at: 'epoch' put: aRecord epoch; yourself]].
"A labeled root as the manifest lists it: nil, or { label. root }."
describeLabeled := [:aLabeledRoot |
  aLabeledRoot isNil ifTrue: [nil] ifFalse: [{ aLabeledRoot label. describeRoot value: aLabeledRoot record }]].
"Records { segment bytes. offset. data } or ranges { segment bytes. start. end } as the manifest
 lists them: { segment hex. offset. length } and { segment hex. start. end }."
describeTriples := [:anArray :lengthOfLast |
  anArray isNil ifTrue: [nil] ifFalse: [
    anArray collect: [:t | { (t at: 1) hex asLowercase. t at: 2. lengthOfLast ifTrue: [(t at: 3) size] ifFalse: [t at: 3] }]]].

"roots.log, field by field"
scan := PBFramedLog scan: (Vectors bytesOf: (entry at: 'file')) kind: (entry at: 'kind') path: (entry at: 'file').
roots := PBAcceptorLog decode: scan payloads path: (entry at: 'file').
roots entries size = listed size ifFalse: [
  failures add: 'roots.log decodes to ' , roots entries size printString , ' entries, the manifest lists ' , listed size printString].
(1 to: (roots entries size min: listed size)) do: [:i |
  | e fields name got |
  e := roots entries at: i.
  fields := (listed at: i) at: 'fields'.
  name := (listed at: i) at: 'name'.
  got := Dictionary new.
  got at: 'kind' put: e kind; at: 'label' put: e label; at: 'root' put: (describeRoot value: e root);
    at: 'seq' put: e seq; at: 'pred' put: (describeLabeled value: e pred);
    at: 'records' put: (describeTriples value: e records value: true);
    at: 'ranges' put: (describeTriples value: e ranges value: false); at: 'flags' put: e flags.
  got keysAndValuesDo: [:k :v |
    v = (fields at: k ifAbsent: [nil]) ifFalse: [
      failures add: name , ': field ' , k , ' is ' , v printString , ', the manifest says ' , (fields at: k ifAbsent: [nil]) printString]].
  (fields keys allSatisfy: [:k | got includesKey: k]) ifFalse: [failures add: name , ': the manifest lists fields this test does not compare'].
  (scan payloads at: i) size = ((listed at: i) at: 'size') ifFalse: [failures add: name , ': the payload is not of the listed size']].

"re-encoding kinds 1 to 4"
kinds := Dictionary new.
kinds at: 1 put: #accepted; at: 2 put: #committed; at: 3 put: #promise; at: 4 put: #rejoined.
(1 to: (roots entries size min: listed size)) do: [:i |
  | e |
  e := roots entries at: i.
  e kind <= 4 ifTrue: [
    (PBAcceptorLog encode: (kinds at: e kind) label: e label root: e root) = (scan payloads at: i)
      ifFalse: [failures add: ((listed at: i) at: 'name') , ': encode:label:root: does not give the payload']]].

"load of a copy"
base := FileSystem temp / ('pbst-rootlog-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
copy := base / 'n0.roots'.
copy binaryContents: (Vectors bytesOf: (entry at: 'file')).
log := PBAcceptorLog path: copy.
loaded := log load.
log close.
base deleteAll.
loadedSpec := entry at: 'loaded'.
(describeLabeled value: loaded accepted) = { entry at: 'label'. entry at: 'root' } ifFalse: [failures add: 'load: accepted is not the manifest root and label'].
(describeLabeled value: loaded accepted) = (loadedSpec at: 'accepted') ifFalse: [failures add: 'load: accepted ' , loaded accepted printString].
(describeLabeled value: loaded committed) = (loadedSpec at: 'committed') ifFalse: [failures add: 'load: committed ' , loaded committed printString].
loaded promise = (loadedSpec at: 'promised') ifFalse: [failures add: 'load: promise ' , loaded promise printString].
loaded top = (loadedSpec at: 'top') ifFalse: [failures add: 'load: top ' , loaded top printString].
loaded isRejoined = (loadedSpec at: 'empty') not ifFalse: [failures add: 'load: isRejoined ' , loaded isRejoined printString].
loaded dataEntryCount = (listed select: [:x | ((x at: 'fields') at: 'kind') >= 5]) size ifFalse: [
  failures add: 'load: dataEntryCount ' , loaded dataEntryCount printString].
loaded entries size = listed size ifFalse: [failures add: 'load: ' , loaded entries size printString , ' entries'].

"invalid vectors of layer roots_log"
invalid := (manifest at: 'invalid') select: [:e | (e at: 'layer') = 'roots_log'].
invalid size = 5 ifFalse: [failures add: 'the manifest lists ' , invalid size printString , ' invalid roots_log vectors, not 5'].
invalid do: [:e |
  | outcome |
  (e at: 'error') = 'corruption' ifFalse: [failures add: (e at: 'id') , ': the manifest expects ' , (e at: 'error')].
  outcome := [PBAcceptorLog decode: (PBFramedLog scan: (Vectors bytesOf: (e at: 'file')) kind: 'ROOT' path: (e at: 'file')) payloads
      path: (e at: 'file'). 'accepted']
    on: PBDBError do: [:x | (x isKindOf: PBCorruptionError) ifTrue: [nil] ifFalse: [x class name , ': ' , x messageText]].
  outcome isNil ifFalse: [failures add: (e at: 'id') , ': ' , outcome]].
failures isEmpty ifFalse: [failures do: [:f | ('FAIL ' , f) displayNl]. Smalltalk exit: 1].
'roots log ok'

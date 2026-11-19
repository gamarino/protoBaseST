"EXPECT: cluster segment ok"
"The cluster segment of the cluster section (README, 'Using the vectors', 8, the segment as in
 step 7): one SpaceRoot written by a cluster commit, with cluster_term 7, cluster_epoch 4 and
 its cluster_previous, in the vector's attribute order (databases cluster_term cluster_epoch
 cluster_previous). Writing: the segment name (the seam newSegmentId) and the oid (the seam
 PBAtom >> _newOid) are those of the manifest, and the two references are stubs at the
 manifest's pointers, so PBSpaceRoot databases:term:epoch:previous: saved into a fresh
 PBFileStorage must give the segment's bytes: its header and the record at its listed offset
 and size. Reading: a copy of the vector's segment, opened with PBFileStorage, answers the
 SpaceRoot at that offset with clusterTerm 7, clusterEpoch 4 and the previous root's pointer.
 The vector is checked against vectors.sha256 before anything is read (Vectors manifest)."
Import from: 'protobase'.
Import from: '_vectors'.
Import from: 'uuid'.

PBFileStorage subclass: #ClusterSegmentStorage.
ClusterSegmentStorage >> newSegmentId
  ^ UUID fromString: '5eed0000000040008000000000002002'.
PBAtom >> _newOid
  ^ (UUID fromString: '5eed0000000040008000000000002001') bytes.

| manifest entry vector refOf base write storage root ptr written failures copy reader read prev |
failures := OrderedCollection new.
manifest := Vectors manifest.
entry := ((manifest at: 'cluster') at: 'segment') at: 'records'.
entry size = 1 ifFalse: [('FAIL the segment lists ' , entry size printString , ' records') displayNl. Smalltalk exit: 1].
entry := entry first.
vector := Vectors bytesOf: (((manifest at: 'cluster') at: 'segment') at: 'file').
"The pointer of the @ref the manifest lists for attribute aName."
refOf := [:aName | | ref |
  ref := ((entry at: 'state') detect: [:pair | pair first = aName]) last at: 'ref'.
  PBAtomPointer segment: (UUID fromString: (ref at: 'segment')) offset: (ref at: 'offset')].
base := FileSystem temp / ('pbst-cluster-segment-' , Smalltalk pid printString).
base deleteAll.

"Writing."
write := base / 'write'.
storage := ClusterSegmentStorage path: write pathString.
[root := PBSpaceRoot databases: (PBDictionary unloadedAt: (refOf value: 'databases') storage: storage)
   term: 7 epoch: 4 previous: (PBSpaceRoot unloadedAt: (refOf value: 'cluster_previous') storage: storage).
 ptr := storage save: root.
 storage flushSegment] ensure: [storage close].
ptr offset = (entry at: 'offset') ifFalse: [failures add: 'the record is at ' , ptr offset printString].
written := (write / '5eed0000000040008000000000002002.seg') binaryContents.
(written copyFrom: (entry at: 'offset') + 1 to: (entry at: 'offset') + (entry at: 'size'))
    = (vector copyFrom: (entry at: 'offset') + 1 to: (entry at: 'offset') + (entry at: 'size'))
  ifFalse: [failures add: 'the record bytes differ: ' , written hex asLowercase].
written = vector ifFalse: [failures add: 'the segment bytes differ: ' , written hex asLowercase].

"Reading a copy of the vector."
copy := base / 'read'.
copy ensureCreateDirectory.
(copy / '5eed0000000040008000000000002002.seg') binaryContents: vector.
reader := PBFileStorage path: copy pathString.
[read := PBSpaceRoot unloadedAt: (PBAtomPointer segment: (UUID fromString: '5eed0000000040008000000000002002')
   offset: (entry at: 'offset')) storage: reader.
 prev := read clusterPrevious.
 { read clusterTerm. read clusterEpoch. prev pointer. read oid hex asLowercase }
   = { 7. 4. refOf value: 'cluster_previous'. entry at: 'oid' }
   ifFalse: [failures add: 'read back ' , { read clusterTerm. read clusterEpoch. prev pointer. read oid } printString]]
  ensure: [reader close].
base deleteAll.
failures do: [:f | ('FAIL ' , f) displayNl].
failures isEmpty ifFalse: [Smalltalk exit: 1].
'cluster segment ok' displayNl.

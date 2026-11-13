"EXPECT: ok 7"
"PBLabeledRoot and PBRootOrder (cluster/rootlog.st): the order of roots of proto_db
 cluster/rootlog.py root_key and compare_roots, on the key (label, epoch, segment bytes,
 offset); the empty space (a known root with no record) has epoch 0 and 16 zero segment bytes,
 and an unknown root (nil) orders below every known one. Two different roots that share
 (label, epoch) are a protocol violation: PBCorruptionError, never a tie. Segment bytes and
 offset only decide between keys of equal (label, epoch), so their order is checked on the
 keys (compareKey:with:, the comparison compare:with: applies)."
Import from: 'protobase'.
Import from: '_check'.
| c seg root empty a b |
c := Check new.
seg := [:last | ByteArray withAll: ((1 to: 16) collect: [:i | i = 16 ifTrue: [last] ifFalse: [0]])].
root := [:label :epoch :last :offset |
  PBLabeledRoot label: label record: (PBRootRecord segment: (seg value: last) offset: offset epoch: epoch)].
empty := [:label | PBLabeledRoot label: label record: nil].
c that: 'label dominates epoch' is: (PBRootOrder compare: (root value: 2 value: 1 value: 0 value: 26)
  with: (root value: 1 value: 9 value: 255 value: 900)) equals: 1.
c that: 'epoch dominates segment' is: (PBRootOrder compare: (root value: 1 value: 2 value: 0 value: 26)
  with: (root value: 1 value: 3 value: 0 value: 26)) equals: -1.
c that: 'segment bytes dominate offset' is: (PBRootOrder compareKey: { 1. 2. seg value: 1. 26 }
  with: { 1. 2. seg value: 0. 900 }) equals: 1.
c that: 'nil orders below the empty space' is: { PBRootOrder compare: nil with: (empty value: 0).
  PBRootOrder compare: (empty value: 0) with: nil. PBRootOrder compare: nil with: nil } equals: #(-1 1 0).
c that: 'the empty space of label 3 is above a root of label 2' is: (PBRootOrder compare: (empty value: 3)
  with: (root value: 2 value: 7 value: 9 value: 26)) equals: 1.
c that: 'two roots of equal (label, epoch) are a protocol violation' signals: PBCorruptionError containing: 'label 4 and epoch 5'
  during: [PBRootOrder compare: (root value: 4 value: 5 value: 1 value: 26) with: (root value: 4 value: 5 value: 1 value: 184)].
a := root value: 5 value: 1 value: 0 value: 26.
b := root value: 6 value: 1 value: 0 value: 26.
c that: 'max:with: is symmetric' isTrue: ((PBRootOrder max: a with: b) == b and: [(PBRootOrder max: b with: a) == b
  and: [(PBRootOrder max: nil with: a) == a and: [(PBRootOrder max: a with: nil) == a]]]).
c report displayNl.

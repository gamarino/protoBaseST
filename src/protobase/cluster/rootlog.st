"-- cluster/rootlog.st: the order of the roots of a cluster --

The root order of proto_db cluster/rootlog.py (root_key, compare_roots). A root of a cluster is
a PBRootRecord with the label (the lease term) it was accepted under; roots order by the key
(label, epoch, segment bytes, offset), as Raft orders log entries by (term, index) (lesson L9:
ordering by (epoch, term) was shown unsafe with a fork). PBRootOrder is the only comparison of
roots in the code base.

  PBLabeledRoot  a known root: its label and its PBRootRecord, or nil for the empty space (a
                 space with no root yet, known to be empty: epoch 0, 16 zero segment bytes,
                 offset 0, as the acceptor log writes it). An unknown root is nil, never a
                 PBLabeledRoot.
  PBRootOrder    compare:with: (-1, 0 or 1; nil orders below every known root), max:with:.
                 Two different roots with equal (label, epoch) are a protocol violation the
                 protocol makes impossible: PBCorruptionError, never broken as a tie.

The acceptor log (kinds 1 to 6) joins this module in cluster Task 4. Every value here is
immutable."

Import from: 'protobase/errors'.
Import from: 'protobase/framing'.

"=== PBLabeledRoot ==========================================================="

Object subclass: #PBLabeledRoot instanceVariableNames: 'label record'.

"A known root: anInteger (the label, >= 0) and aPBRootRecordOrNil (nil: the empty space). A
 record of epoch 0 is refused (PBValidationError): epoch 0 is the empty space's, which the
 acceptor log writes as no record (proto_db decodes it as None), so a key never stands for two
 roots."
PBLabeledRoot class >> label: anInteger record: aPBRootRecordOrNil
  (anInteger isInteger and: [anInteger >= 0]) ifFalse: [
    ^ PBValidationError signal: 'PBLabeledRoot: a label is an Integer >= 0, not ' , anInteger printString].
  aPBRootRecordOrNil isNil ifFalse: [
    ((aPBRootRecordOrNil isKindOf: PBRootRecord) and: [aPBRootRecordOrNil epoch > 0]) ifFalse: [
      ^ PBValidationError signal: 'PBLabeledRoot: a record is a PBRootRecord of epoch > 0 or nil (the empty space), not '
        , aPBRootRecordOrNil printString]].
  ^ self basicNew _setLabel: anInteger record: aPBRootRecordOrNil.

PBLabeledRoot >> _setLabel: anInteger record: aPBRootRecordOrNil
  "Runs once, on a fresh instance."
  label isNil ifFalse: [^ PBUserError signal: 'PBLabeledRoot is immutable'].
  label := anInteger.
  record := aPBRootRecordOrNil.
  ^ self.

PBLabeledRoot >> label
  ^ label.

"The PBRootRecord, or nil for the empty space."
PBLabeledRoot >> record
  ^ record.

"The record's epoch, 0 for the empty space."
PBLabeledRoot >> epoch
  ^ record isNil ifTrue: [0] ifFalse: [record epoch].

"The ordering key { label. epoch. segment bytes (16 zero bytes for the empty space). offset }
 (proto_db root_key), a fresh Array."
PBLabeledRoot >> key
  record isNil ifTrue: [^ { label. 0. ByteArray new: 16. 0 }].
  ^ { label. record epoch. record segment. record offset }.

PBLabeledRoot >> printOn: aStream
  aStream nextPutAll: 'PBLabeledRoot('; print: label; nextPutAll: ', '; print: record; nextPut: $).

"=== PBRootOrder ============================================================="

Object subclass: #PBRootOrder.

"-1, 0 or 1 as the root a (a PBLabeledRoot, or nil: unknown) orders before, equal to or after
 the root b (proto_db compare_roots). nil orders below every known root. Two different roots
 with equal (label, epoch) are PBCorruptionError."
PBRootOrder class >> compare: a with: b
  | ka kb |
  ka := self _keyOf: a.
  kb := self _keyOf: b.
  ka isNil ifTrue: [^ kb isNil ifTrue: [0] ifFalse: [-1]].
  kb isNil ifTrue: [^ 1].
  (((ka at: 1) = (kb at: 1)) and: [(ka at: 2) = (kb at: 2) and: [ka ~= kb]]) ifTrue: [
    ^ PBCorruptionError signal: 'Protocol violation: two different roots carry label ' , (ka at: 1) printString
      , ' and epoch ' , (ka at: 2) printString , ' (segment ' , (ka at: 3) hex asLowercase , ' offset '
      , (ka at: 4) printString , ' and segment ' , (kb at: 3) hex asLowercase , ' offset ' , (kb at: 4) printString , ')'].
  ^ self compareKey: ka with: kb.

"The greater of the roots a and b (either may be nil); a when they are equal."
PBRootOrder class >> max: a with: b
  ^ (self compare: a with: b) < 0 ifTrue: [b] ifFalse: [a].

"-1, 0 or 1 as the key ka orders before, equal to or after the key kb (two PBLabeledRoot keys):
 label, then epoch, then the segment bytes (unsigned, byte by byte), then the offset, as
 Python compares the tuples root_key answers."
PBRootOrder class >> compareKey: ka with: kb
  | segA segB |
  1 to: 2 do: [:i | (ka at: i) = (kb at: i) ifFalse: [^ (ka at: i) < (kb at: i) ifTrue: [-1] ifFalse: [1]]].
  segA := ka at: 3.
  segB := kb at: 3.
  1 to: 16 do: [:i | (segA at: i) = (segB at: i) ifFalse: [^ (segA at: i) < (segB at: i) ifTrue: [-1] ifFalse: [1]]].
  (ka at: 4) = (kb at: 4) ifTrue: [^ 0].
  ^ (ka at: 4) < (kb at: 4) ifTrue: [-1] ifFalse: [1].

"The key of aRoot, nil for an unknown root; PBValidationError for anything else."
PBRootOrder class >> _keyOf: aRoot
  aRoot isNil ifTrue: [^ nil].
  (aRoot isClassObject not and: [aRoot class == PBLabeledRoot]) ifFalse: [
    ^ PBValidationError signal: 'PBRootOrder: a root is a PBLabeledRoot or nil, not ' , aRoot printString].
  ^ aRoot key.

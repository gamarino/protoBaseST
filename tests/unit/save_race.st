"EXPECT: ok 8"
"Two saves of one atom at once (plan Task 15, review I2): the atom's saved cell is filled
 once, by compare-and-swap, and the outcome never depends on the interleaving. The race
 is forced through a seam, never by timing: a storage subclass whose pushAtom: runs a second
 save of the same atom before it answers, so the second save installs its place first and
 the first save loses the compare-and-swap. Into the same storage, the loser answers the
 winner's pointer, as ProtoBase's _save answers the pointer the first save published (the
 loser's record is an orphan nothing refers to). Into another storage, the loser signals
 the PBValidationError of an atom stored elsewhere, the same error a sequential second
 save meets."
Import from: 'protobase'.
Import from: '_check'.

"A storage whose first pushAtom: first saves the atom held in its cell into another
 storage (itself, or a second one)."
PBFileStorage subclass: #RacingSink instanceVariableNames: 'racer into'.
RacingSink >> racer: anAtom into: aStorage
  racer := anAtom.
  into := aStorage.
RacingSink >> pushAtom: anEnvelope
  | r |
  r := racer.
  racer := nil.
  r isNil ifFalse: [r _saveInto: into].
  ^ super pushAtom: anEnvelope.

| c sink other third x y parent winner base offsets |
c := Check new.
base := FileSystem temp / ('pbst-save-race-' , Smalltalk pid printString).
base deleteAll.
"The offsets of the records pushed into aStorage, in order."
offsets := [:aStorage | (aStorage recordsOfSegment: aStorage currentSegment) collect: [:r | r at: 1]].
"Same storage."
sink := RacingSink path: (base / 'same') pathString.
x := PBObject withAll: { 'n' -> 1 }.
parent := PBObject withAll: { 'child' -> x }.
sink racer: x into: sink.
parent _saveInto: sink.
c that: 'two records were pushed for x' is: (offsets value: sink) size equals: 3.
winner := (offsets value: sink) first.
c that: 'x keeps the winner''s pointer' is: x pointer offset equals: winner.
c that: 'the parent refers to the winner' is: ((sink loadAt: parent pointer expecting: 19) state at: 'child') pointer offset equals: winner.
sink racer: (y := PBObject withAll: { 'n' -> 2 }) into: sink.
c that: 'a direct save answers the winner''s pointer' is: (y _saveInto: sink) equals: y pointer.
c that: 'which is the first record pushed' is: y pointer offset equals: ((offsets value: sink) at: 4).
"Another storage."
sink close.
other := PBFileStorage path: (base / 'other') pathString.
sink := RacingSink path: (base / 'racing') pathString.
x := PBObject withAll: { 'n' -> 3 }.
sink racer: x into: other.
c that: 'the loser into another storage' signals: PBValidationError containing: 'stored in' during: [x _saveInto: sink].
c that: 'x stays in the winner''s storage' is: x pointer segmentBytes equals: other currentSegment.
c that: 'a sequential second save meets the same error' signals: PBValidationError containing: 'stored in'
  during: [x _saveInto: (third := PBFileStorage path: (base / 'third') pathString)].
sink close.
other close.
third close.
base deleteAll.
c report displayNl.

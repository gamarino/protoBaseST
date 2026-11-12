"EXPECT: ok 26"
"Mutable cells (plan Task 18, design spec 7.1 D35 and the mutable rows of 10.4; ProtoBase
 new_mutable, set_mutable, remove_mutable and _check_mutables), step by step in one process:
  - two newMutable: of one name: the second commit conflicts (the absence was read);
  - a blind setMutable: of a cell the other removed: conflict (mexpected);
  - a blind removeMutable: of a cell already removed: both commit (a no-op);
  - a blind setMutable: concurrent with another set: both commit, the later value wins;
  - a cell read, then changed by a concurrent commit: conflict;
  - cells are never merged: a dictionary in a cell is replaced.
 The rules in one transaction: newMutable: of an existing cell, setMutable: and
 removeMutable: of an absent one are PBValidationError; a transaction reads its own cell
 writes; mutableNames shows them; a refused newMutable: still records the read."
Import from: 'protobase'.
Import from: '_check'.

| c base space db a b t |
c := Check new.
base := FileSystem temp / ('pbst-tx-mutables-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.

"Two newMutable: of one name."
a := db newTransaction.
b := db newTransaction.
a newMutable: 'm' value: 'A'.
b newMutable: 'm' value: 'B'.
c that: 'newMutable: records the absence' is: (b mutableReadSet at: 'm') == #absent equals: true.
b commit.
c that: 'the second newMutable: conflicts' signals: PBConflictError containing: 'm' during: [a commit].
c that: 'the first one''s value' is: (db newTransaction getMutable: 'm') equals: 'B'.

"A blind setMutable: of a cell the other removed."
a := db newTransaction.
b := db newTransaction.
a setMutable: 'm' value: 'A'.
c that: 'a blind set records no read' is: a mutableReadSet size equals: 0.
b removeMutable: 'm'.
b commit.
c that: 'the cell is gone' is: (db newTransaction getMutable: 'm') equals: nil.
c that: 'a blind set of a removed cell conflicts' signals: PBConflictError containing: 'removed' during: [a commit].
c that: 'it stays removed' is: db newTransaction mutableNames asArray equals: #().

"A blind removeMutable: of a cell already removed: both commit."
db newTransactionDo: [:x | x newMutable: 'r' value: 1].
a := db newTransaction.
b := db newTransaction.
a removeMutable: 'r'.
b removeMutable: 'r'.
b commit.
a commit.
c that: 'both removals committed' is: { a isActive. b isActive. db newTransaction mutableNames asArray } equals: { false. false. #() }.
c that: 'and A published a version' is: db _currentRoot version equals: 5.

"A blind set concurrent with another set: the later value wins."
db newTransactionDo: [:x | x newMutable: 'n' value: 0].
a := db newTransaction.
b := db newTransaction.
a setMutable: 'n' value: 'A'.
b setMutable: 'n' value: 'B'.
a commit.
b commit.
c that: 'last writer wins' is: (db newTransaction getMutable: 'n') equals: 'B'.

"A cell read, then changed concurrently."
a := db newTransaction.
b := db newTransaction.
c that: 'A reads n' is: (a getMutable: 'n') equals: 'B'.
b setMutable: 'n' value: 'C'.
b commit.
a setMutable: 'n' value: 'D'.
c that: 'a read cell changed: conflict' signals: PBConflictError containing: 'changed' during: [a commit].
c that: 'C stays' is: (db newTransaction getMutable: 'n') equals: 'C'.

"Cells are never merged."
db newTransactionDo: [:x | x newMutable: 'd' value: (x newDictionary setAt: 'k1' value: 1)].
db newTransactionDo: [:x | x setMutable: 'd' value: (x newDictionary setAt: 'k2' value: 2)].
c that: 'a dictionary in a cell is replaced' is: (db newTransaction getMutable: 'd') keys asArray equals: #('k2').

"The rules in one transaction."
t := db newTransaction.
c that: 'newMutable: of an existing cell' signals: PBValidationError containing: 'already exists' during: [
  t newMutable: 'n' value: 1].
c that: 'the refused newMutable: recorded the read' is: (t mutableReadSet includesKey: 'n') equals: true.
c that: 'setMutable: of an absent cell' signals: PBValidationError containing: 'does not exist' during: [
  t setMutable: 'none' value: 1].
c that: 'removeMutable: of an absent cell' signals: PBValidationError containing: 'does not exist' during: [
  t removeMutable: 'none'].
c that: 'still active' is: t isActive equals: true.
t newMutable: 'fresh' value: 10.
c that: 'reads its own new cell' is: (t getMutable: 'fresh') equals: 10.
t setMutable: 'fresh' value: 11.
c that: 'a set after a new in one transaction' is: (t getMutable: 'fresh') equals: 11.
t removeMutable: 'n'.
c that: 'a removed cell reads nil' is: (t getMutable: 'n') equals: nil.
c that: 'setMutable: of a cell removed in the transaction' signals: PBValidationError during: [t setMutable: 'n' value: 1].
t newMutable: 'n' value: 'again'.
c that: 'newMutable: after a removal in the transaction' is: (t getMutable: 'n') equals: 'again'.
c that: 'mutableNames' is: t mutableNames asArray equals: #('d' 'fresh' 'n').
t commit.
c that: 'committed cells' is: { db newTransaction getMutable: 'fresh'. db newTransaction getMutable: 'n' } equals: #(11 'again').

space close.
base deleteAll.
c report displayNl.

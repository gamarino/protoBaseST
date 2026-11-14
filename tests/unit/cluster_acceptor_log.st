"EXPECT: ok 10"
"PBAcceptorLog (cluster/rootlog.st): the acceptor log of proto_db's rootlog.py RootsLog. Its
 lock file, its synced and unsynced entries, the poisoning of a failed write and the refusal of a
 log file with two hard links. The syncs are observed through a PBFramedLog subclass (the
 framedLogClass seam): it counts each sync of an append and fails the next one on request."
Import from: 'protobase'.
| failures tests check base path log other roots rec rec2 syncsOf refusal linked |
failures := OrderedCollection new.
tests := Set new.
check := [:name :ok | ok ifFalse: [failures add: name]].
"The message of the PBDBError aBlock signals when it is of errorClass, else nil."
refusal := [:aBlock :errorClass | aBlock on: PBDBError do: [:e | (e isKindOf: errorClass) ifTrue: [e messageText] ifFalse: [nil]]].
base := FileSystem temp / ('pbst-acceptor-log-' , Smalltalk pid printString).
base deleteAll.
path := base / 'cluster' / 'n0.roots'.
rec := PBRootRecord segment: (ByteArray fromHex: '5eed0000000040008000000000002002') offset: 26 epoch: 4.
rec2 := PBRootRecord segment: (ByteArray fromHex: '5eed0000000040008000000000002002') offset: 90 epoch: 5.

PBFramedLog subclass: #SeamFramedLog instanceVariableNames: '' classVariableNames: 'Syncs FailNext'.
SeamFramedLog class >> _setSyncs: aCounter failNext: aFlag
  Syncs := aCounter.
  FailNext := aFlag.
SeamFramedLog class >> syncs
  ^ Syncs.
SeamFramedLog class >> failNext
  ^ FailNext.
SeamFramedLog >> sync
  | n |
  (FailNext value: false ifCurrent: true) ifTrue: [^ FileSystemError signal: 'injected sync failure'].
  [n := Syncs value. Syncs value: n + 1 ifCurrent: n] whileFalse: [nil].
  ^ super sync.
SeamFramedLog _setSyncs: (Atom on: 0) failNext: (Atom on: false).
PBAcceptorLog subclass: #SeamAcceptorLog.
SeamAcceptorLog class >> framedLogClass
  ^ SeamFramedLog.
"The syncs of the appends aBlock makes."
syncsOf := [:aBlock |
  | before |
  before := SeamFramedLog syncs value.
  aBlock value.
  SeamFramedLog syncs value - before].

tests add: 1.
"1. a fresh log (and its directory) is created and loads empty"
log := PBAcceptorLog path: path.
roots := log load.
check value: 'fresh log loads empty' value: (roots accepted isNil and: [roots committed isNil and: [roots promise = 0
  and: [roots top = 0 and: [roots isRejoined not and: [roots dataEntryCount = 0 and: [roots entries isEmpty]]]]]]).
check value: 'fresh log file holds its header' value: path binaryContents = (PBFramedLog header: 'ROOT').

tests add: 2.
"2. promise, accepted, committed, rejoined: reloaded in a new instance"
log promise: 7.
log append: #accepted label: 7 root: rec.
log append: #committed label: 7 root: rec.
log markRejoined.
log close.
log := PBAcceptorLog path: path.
roots := log load.
check value: 'reloaded accepted' value: (roots accepted label = 7 and: [roots accepted record offset = 26 and: [roots accepted epoch = 4]]).
check value: 'reloaded committed' value: (roots committed label = 7 and: [roots committed record offset = 26]).
check value: 'reloaded promise and marker' value: (roots promise = 7 and: [roots isRejoined and: [roots entries size = 4]]).
check value: 'entries in order' value: ((roots entries collect: [:e | e kind]) = #(3 1 2 4)).

tests add: 3.
"3. top is the highest label or term, the rejoined marker's label ignored; the newest root by
 root order wins"
roots := PBAcceptorLog decode: {
    PBAcceptorLog encode: #promise label: 9 root: nil.
    PBAcceptorLog encode: #accepted label: 7 root: rec2.
    PBAcceptorLog encode: #accepted label: 7 root: rec.
    PBAcceptorLog encode: #rejoined label: 99 root: nil } path: 'x.roots'.
check value: 'top ignores the rejoined marker' value: (roots top = 9 and: [roots promise = 9]).
check value: 'the greatest accepted root' value: roots accepted record == (roots entries at: 2) root.
check value: 'two roots with one label and epoch' value: (refusal value: [PBAcceptorLog decode: {
    PBAcceptorLog encode: #accepted label: 7 root: rec.
    PBAcceptorLog encode: #accepted label: 7 root: (PBRootRecord segment: rec segment offset: 27 epoch: 4) } path: 'x.roots'] value: PBCorruptionError) notNil.
"A kind-5 head of 93 bytes: with no records it decodes, with one byte more it has trailing
 bytes, with a record count of 1 and no item it is cut inside an item."
check value: 'empty kind-5 entry' value: (PBAcceptorLog decode: { #[5] , (ByteArray new: 92) } path: 'x.roots') accepted notNil.
check value: 'kind-5 trailing bytes' value: ((refusal value: [PBAcceptorLog decode: { #[5] , (ByteArray new: 93) } path: 'x.roots'] value: PBCorruptionError)
  includesSubstring: 'trailing').
"Kind 6 (98-byte head; flags at offset 1, label at 2, range count at 90): stored without ACCEPTED
 it is no accepted root and leaves top alone (proto_db _decode adds only accepted entries);
 97 bytes is short; a range count of 1 with no range is cut inside a range."
roots := PBAcceptorLog decode: {
    PBAcceptorLog encode: #promise label: 9 root: nil.
    #[6 0 50] , (ByteArray new: 95) } path: 'x.roots'.
check value: 'an unaccepted kind 6 leaves top' value: (roots top = 9 and: [roots accepted isNil and: [roots dataEntryCount = 1]]).
check value: 'an accepted kind 6 raises top' value: (PBAcceptorLog decode: { #[6 1 50] , (ByteArray new: 95) } path: 'x.roots') top = 50.
check value: 'short kind-6 entry' value: ((refusal value: [PBAcceptorLog decode: { #[6] , (ByteArray new: 96) } path: 'x.roots'] value: PBCorruptionError)
  includesSubstring: 'short replica entry').
check value: 'kind-6 cut inside a range' value: ((refusal value: [PBAcceptorLog decode: { #[6 1] , (ByteArray new: 88) , #[1 0 0 0 0 0 0 0] } path: 'x.roots'] value: PBCorruptionError)
  includesSubstring: 'cut inside a range').
check value: 'kind-5 cut inside an item' value: ((refusal value: [PBAcceptorLog decode: { #[5] , (ByteArray new: 88) , #[1 0 0 0] } path: 'x.roots'] value: PBCorruptionError)
  includesSubstring: 'cut inside an item').

tests add: 4.
"4. a second open while the first is open is PBUserError naming the lock file; the first is unaffected"
other := refusal value: [PBAcceptorLog path: path] value: PBUserError.
check value: 'second open refused' value: (other notNil and: [other includesSubstring: 'n0.roots.lock']).
log append: #accepted label: 8 root: rec2.
check value: 'first open unaffected' value: log load accepted label = 8.

tests add: 5.
"5. after close the log opens again; a closed log refuses writes"
log close.
check value: 'closed log refuses' value: (refusal value: [log promise: 20] value: PBClosedError) notNil.
"proto_db order: promise and markRejoined check the handle first (a closed log given a bad term
 is closed); append checks its kind and encodes the entry before it looks at the handle."
check value: 'closed before a bad term' value: (refusal value: [log promise: -1] value: PBClosedError) notNil.
check value: 'append checks its kind first' value: (refusal value: [log append: #promise label: 1 root: nil] value: PBValidationError) notNil.
log close.
log := PBAcceptorLog path: path.
check value: 'opens after close' value: (log load accepted label = 8 and: [log isFailed not]).
log close.

tests add: 6.
"6. a failed sync poisons the log: the append and every later call are PBUnexpectedError"
log := SeamAcceptorLog path: path.
SeamFramedLog failNext value: true ifCurrent: false.
check value: 'failed sync is PBUnexpectedError' value: (refusal value: [log append: #accepted label: 9 root: rec2] value: PBUnexpectedError) notNil.
check value: 'the log is failed' value: log isFailed.
other := refusal value: [log promise: 30] value: PBUnexpectedError.
check value: 'next call refused' value: (other notNil and: [other includesSubstring: 'failed']).
check value: 'committed refused too' value: (refusal value: [log append: #committed label: 9 root: rec2] value: PBUnexpectedError) notNil.
log close.

tests add: 7.
"7. syncs: one per promise, accepted root and marker, none per committed root; a promise not
 above the durable one writes nothing (proto_db RootsLog.promise)"
log := SeamAcceptorLog path: path.
check value: 'one sync per promise' value: (syncsOf value: [log promise: 40]) = 1.
check value: 'no sync per committed' value: (syncsOf value: [log append: #committed label: 40 root: rec2]) = 0.
check value: 'one sync per accepted' value: (syncsOf value: [log append: #accepted label: 40 root: rec2]) = 1.
check value: 'one sync per marker' value: (syncsOf value: [log markRejoined]) = 1.
other := log load entries size.
check value: 'a lower promise writes nothing' value: ((syncsOf value: [log promise: 39]) = 0 and: [log load entries size = other]).
log close.

tests add: 8.
"8. the arguments: kinds #accepted and #committed only, a label in [0, 2^64), an epoch-0 record refused"
log := PBAcceptorLog path: path.
check value: 'append of a promise kind' value: (refusal value: [log append: #promise label: 50 root: nil] value: PBValidationError) notNil.
check value: 'negative label' value: (refusal value: [log append: #accepted label: -1 root: rec] value: PBValidationError) notNil.
check value: 'label of 65 bits' value: (refusal value: [log append: #accepted label: (2 raisedTo: 64) root: rec] value: PBValidationError) notNil.
check value: 'epoch-0 record' value: (refusal value: [log append: #accepted label: 50
  root: (PBRootRecord segment: rec segment offset: 1 epoch: 0)] value: PBValidationError) notNil.
check value: 'promise and marker carry no root' value: (refusal value: [PBAcceptorLog encode: #promise label: 1 root: rec] value: PBValidationError) notNil.
check value: 'refusals wrote nothing' value: (log isFailed not and: [log load entries size = other]).
log close.

tests add: 9.
"9. a log file with two hard links is refused (PBLockingError) after the lock is taken (an open
 through a held lock is still the lock's PBUserError), and nothing is left held"
log := PBAcceptorLog path: path.
linked := base / 'cluster' / 'alias.roots'.
check value: 'hard link made' value: (OSProcess run: 'ln' arguments: { path pathString. linked pathString }) exitCode = 0.
other := refusal value: [PBAcceptorLog path: path] value: PBUserError.
check value: 'the held lock is refused first' value: (other notNil and: [other includesSubstring: '.lock']).
other := refusal value: [PBAcceptorLog path: linked] value: PBLockingError.
check value: 'the second name is refused' value: (other notNil and: [other includesSubstring: '2 hard links']).
log close.
check value: 'refused through the first name' value: (refusal value: [PBAcceptorLog path: path] value: PBLockingError) notNil.
linked delete.
log := PBAcceptorLog path: path.
check value: 'one name again: it opens' value: (log load promise = 40).
log close.

tests add: 10.
"10. a corrupt log is refused at open and leaves its lock free"
(base / 'bad') ensureCreateDirectory.
(base / 'bad' / 'n1.roots') binaryContents: (PBFramedLog header: 'ROOT') , (PBFramedLog frame: (ByteArray new: 40)).
check value: 'corrupt log refused' value: (refusal value: [PBAcceptorLog path: base / 'bad' / 'n1.roots'] value: PBCorruptionError) notNil.
(base / 'bad' / 'n1.roots') binaryContents: (PBFramedLog header: 'ROOT').
log := PBAcceptorLog path: base / 'bad' / 'n1.roots'.
check value: 'its lock was released' value: log load entries isEmpty.
log close.
base deleteAll.
failures isEmpty ifFalse: [failures do: [:f | ('FAIL ' , f) displayNl]. Smalltalk exit: 1].
'ok ' , tests size printString

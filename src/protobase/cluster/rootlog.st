"-- cluster/rootlog.st: the order of the roots of a cluster and the acceptor log --

The root order and the acceptor log of proto_db cluster/rootlog.py (root_key, compare_roots,
_decode, RootsLog). A root of a cluster is a PBRootRecord with the label (the lease term) it was
accepted under; roots order by the key (label, epoch, segment bytes, offset), as Raft orders log
entries by (term, index) (lesson L9: ordering by (epoch, term) was shown unsafe with a fork).
PBRootOrder is the only comparison of roots in the code base.

  PBLabeledRoot  a known root: its label and its PBRootRecord, or nil for the empty space (a
                 space with no root yet, known to be empty: epoch 0, 16 zero segment bytes,
                 offset 0, as the acceptor log writes it). An unknown root is nil, never a
                 PBLabeledRoot.
  PBRootOrder    compare:with: (-1, 0 or 1; nil orders below every known root), max:with:.
                 Two different roots with equal (label, epoch) are a protocol violation the
                 protocol makes impossible: PBCorruptionError, never broken as a tie.
  PBAcceptorLog  what one node must remember across a crash to keep its promises: the highest
                 term it granted (promise), the highest root it accepted, the newest root it
                 knows committed and the rejoined marker, in a framed log of kind ROOT
                 (PBFramedLog). Entries, little-endian:
                   kinds 1-4  41 bytes <BQQ16sQ>: kind (1 accepted, 2 committed, 3 promise,
                              4 rejoined), label (the term of a promise), epoch, segment, offset;
                              epoch 0 is the empty space (no record)
                   kind 5     an accepted root with the records of its replication: head of 93
                              bytes <BQQ16sQQQQ16sQI> (kind, label, root, seq, pred label, pred
                              root, record count), then per record <16sQI> (segment, offset,
                              length) and its bytes
                   kind 6     the same with the commit's byte ranges: head of 98 bytes
                              <BBQQ16sQQQQ16sQII> (kind, flags, ..., range count, record count),
                              the ranges <16sQQ> (segment, start, end), then the records; flag
                              bit 0 (ACCEPTED) set when the root is accepted
                 This port writes kinds 1 to 4 and reads 1 to 6 (kind 5 and accepted kind-6
                 entries count as accepted roots). Every promise, accepted root and rejoined
                 marker is synced before the call answers, whatever the space's durability; a
                 committed entry is knowledge (R67) and rides on the next sync. Any failed
                 write or sync poisons the log: every later write is PBUnexpectedError until it
                 is reopened. The log holds <real path>.lock (tryLock, the lock proto_db's OwnerLock
                 takes; the path resolved as os.path.realpath) from before it opens the file until close, so a second open, in this
                 process or another, is PBUserError naming the lock file; a log file with more
                 than one hard link is PBLockingError (PBFramedLog openAppend:kind:). One caller
                 at a time: the acceptor actor owns the log (the methods are not serialized; load
                 reads by path and is safe from any caller).
  PBLoggedRoots  what a log holds (load, decode:path:).
  PBLogEntry     one entry of a log, field by field.

Every value here is immutable; a PBAcceptorLog holds an open file, its lock and two Atoms (the
durable promise, the failure that poisoned it)."

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

"-1, 0 or 1 as the key ka orders before, equal to or after the key kb: label, then epoch, then
 the segment bytes (unsigned, byte by byte), then the offset, as Python compares the tuples
 root_key answers. ka and kb are only keys answered by PBLabeledRoot >> key (four elements,
 16 segment bytes); nothing else is checked. It does not apply the (label, epoch) corruption
 rule: compare:with: does, and is the comparison of roots."
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

"=== PBLogEntry =============================================================="

"One entry of an acceptor log. kind 1 to 6; label; root (a PBRootRecord, nil for epoch 0);
 seq and pred (a PBLabeledRoot, nil when its label and epoch are 0) for kinds 5 and 6;
 records ({ segment bytes. offset. record bytes }) for kinds 5 and 6; ranges
 ({ segment bytes. start. end }, the shape of PBClusterMessage rangesFrom:) and flags for
 kind 6. A field the kind does not carry is nil."
Object subclass: #PBLogEntry instanceVariableNames: 'kind label root seq pred records ranges flags'.

PBLogEntry class >> kind: aKind label: aLabel root: aRoot seq: aSeq pred: aPred records: aRecords ranges: aRanges flags: aFlags
  ^ self basicNew _setKind: aKind label: aLabel root: aRoot seq: aSeq pred: aPred records: aRecords ranges: aRanges flags: aFlags.

PBLogEntry >> _setKind: aKind label: aLabel root: aRoot seq: aSeq pred: aPred records: aRecords ranges: aRanges flags: aFlags
  "Runs once, on a fresh instance."
  kind isNil ifFalse: [^ PBUserError signal: 'PBLogEntry is immutable'].
  kind := aKind.
  label := aLabel.
  root := aRoot.
  seq := aSeq.
  pred := aPred.
  records := aRecords.
  ranges := aRanges.
  flags := aFlags.
  ^ self.

PBLogEntry >> kind
  ^ kind.

PBLogEntry >> label
  ^ label.

PBLogEntry >> root
  ^ root.

PBLogEntry >> seq
  ^ seq.

PBLogEntry >> pred
  ^ pred.

"A fresh Array of fresh { segment bytes. offset. record bytes } triples, or nil."
PBLogEntry >> records
  ^ records isNil ifTrue: [nil] ifFalse: [records collect: [:t | { (t at: 1) copy. t at: 2. (t at: 3) copy }]].

"A fresh Array of fresh { segment bytes. start. end } triples, or nil."
PBLogEntry >> ranges
  ^ ranges isNil ifTrue: [nil] ifFalse: [ranges collect: [:t | { (t at: 1) copy. t at: 2. t at: 3 }]].

PBLogEntry >> flags
  ^ flags.

PBLogEntry >> printOn: aStream
  aStream nextPutAll: 'PBLogEntry(kind '; print: kind; nextPutAll: ', label '; print: label; nextPutAll: ', '; print: root; nextPut: $).

"=== PBLoggedRoots ==========================================================="

"What an acceptor log holds (proto_db LoggedRoots): accepted and committed (the greatest of
 each kind by root order, a PBLabeledRoot, or nil when none was logged), promise (the highest
 term promised, 0 when none), top (the highest label or term of the entries that are not
 rejoined markers and not kind-6 entries stored without acceptance, as proto_db _Best),
 isRejoined (a rejoined marker is logged: the node may act as an acceptor), dataEntryCount
 (entries of kinds 5 and 6) and entries (the PBLogEntry values in log order)."
Object subclass: #PBLoggedRoots instanceVariableNames: 'accepted committed promise top rejoined dataEntryCount entries'.

PBLoggedRoots class >> accepted: anAccepted committed: aCommitted promise: aPromise top: aTop rejoined: aBoolean dataEntryCount: aCount entries: anArray
  ^ self basicNew _setAccepted: anAccepted committed: aCommitted promise: aPromise top: aTop rejoined: aBoolean dataEntryCount: aCount entries: anArray.

PBLoggedRoots >> _setAccepted: anAccepted committed: aCommitted promise: aPromise top: aTop rejoined: aBoolean dataEntryCount: aCount entries: anArray
  "Runs once, on a fresh instance."
  entries isNil ifFalse: [^ PBUserError signal: 'PBLoggedRoots is immutable'].
  accepted := anAccepted.
  committed := aCommitted.
  promise := aPromise.
  top := aTop.
  rejoined := aBoolean.
  dataEntryCount := aCount.
  entries := anArray.
  ^ self.

PBLoggedRoots >> accepted
  ^ accepted.

PBLoggedRoots >> committed
  ^ committed.

PBLoggedRoots >> promise
  ^ promise.

PBLoggedRoots >> top
  ^ top.

PBLoggedRoots >> isRejoined
  ^ rejoined.

PBLoggedRoots >> dataEntryCount
  ^ dataEntryCount.

"A fresh Array of the PBLogEntry values, in log order."
PBLoggedRoots >> entries
  ^ entries copy.

"=== PBAcceptorLog ==========================================================="

Object subclass: #PBAcceptorLog instanceVariableNames: 'path lock log promised failed'.

"The kind of the log in its file header."
PBAcceptorLog class >> logKind
  ^ 'ROOT'.

"The suffix of the lock file held next to the log while it is open (proto_db LOCK_SUFFIX)."
PBAcceptorLog class >> lockSuffix
  ^ '.lock'.

"The framed log class the log is opened with. A seam: tests count and fail its syncs."
PBAcceptorLog class >> framedLogClass
  ^ PBFramedLog.

"The code of the entry kind aSymbol: #accepted 1, #committed 2, #promise 3, #rejoined 4."
PBAcceptorLog class >> _codeOf: aSymbol
  ^ #(#accepted #committed #promise #rejoined) indexOf: aSymbol
    ifAbsent: [PBValidationError signal: 'PBAcceptorLog: an entry kind is #accepted, #committed, #promise or #rejoined, not '
      , aSymbol printString].

"The 41-byte payload of an entry of aKind (#accepted, #committed, #promise or #rejoined) with
 the label (or term) anInteger, in [0, 2^64), and the root aPBRootRecordOrNil (nil: the empty
 space, written as epoch 0; a record of epoch 0 is refused, PBLabeledRoot label:record:). A
 promise and a rejoined marker carry no root."
PBAcceptorLog class >> encode: aKind label: anInteger root: aPBRootRecordOrNil
  | code limit w |
  code := self _codeOf: aKind.
  limit := 2 raisedTo: 64.
  (anInteger isInteger and: [anInteger >= 0 and: [anInteger < limit]]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorLog: a label is an Integer in [0, 2^64), not ' , anInteger printString].
  aPBRootRecordOrNil isNil ifFalse: [
    code >= 3 ifTrue: [^ PBValidationError signal: 'PBAcceptorLog: a ' , aKind , ' entry carries no root'].
    PBLabeledRoot label: anInteger record: aPBRootRecordOrNil.
    (aPBRootRecordOrNil epoch < limit and: [aPBRootRecordOrNil offset < limit]) ifFalse: [
      ^ PBValidationError signal: 'PBAcceptorLog: the epoch and offset of a root are below 2^64, not ' , aPBRootRecordOrNil printString]].
  w := WriteStream on: ByteArray new.
  w nextPutUnsigned: code width: 1 bigEndian: false.
  w nextPutUnsigned: anInteger width: 8 bigEndian: false.
  aPBRootRecordOrNil isNil
    ifTrue: [w nextPutUnsigned: 0 width: 8 bigEndian: false; nextPutAll: (ByteArray new: 16); nextPutUnsigned: 0 width: 8 bigEndian: false]
    ifFalse: [
      w nextPutUnsigned: aPBRootRecordOrNil epoch width: 8 bigEndian: false.
      w nextPutAll: aPBRootRecordOrNil segment.
      w nextPutUnsigned: aPBRootRecordOrNil offset width: 8 bigEndian: false].
  ^ w contents.

"The u64 (little-endian) at offset pos (from 0) of aByteArray."
PBAcceptorLog class >> _u64: aByteArray at: pos
  ^ aByteArray unsignedLong64At: pos + 1 bigEndian: false.

"The root written at offset pos of aByteArray as epoch (8 bytes), segment (16), offset (8): a
 PBRootRecord, nil for epoch 0 (proto_db _record_or_none)."
PBAcceptorLog class >> _rootIn: aByteArray at: pos
  | epoch |
  epoch := self _u64: aByteArray at: pos.
  epoch = 0 ifTrue: [^ nil].
  ^ PBRootRecord segment: (aByteArray copyFrom: pos + 9 to: pos + 24) offset: (self _u64: aByteArray at: pos + 24) epoch: epoch.

"The PBLogEntry of the kind-5 or kind-6 payload p (proto_db decode_records_entry);
 PBCorruptionError when it is malformed."
PBAcceptorLog class >> _decodeData: p path: aString
  | corrupt kind6 b flags predLabel predRoot nranges count pos ranges records |
  corrupt := [:what | ^ PBCorruptionError signal: 'The root log ' , aString , ' holds ' , what].
  kind6 := (p at: 1) = 6.
  kind6
    ifTrue: [
      p size < 98 ifTrue: [corrupt value: 'a short replica entry'].
      flags := p at: 2.
      (flags bitAnd: 254) = 0 ifFalse: [corrupt value: 'a replica entry with unknown flags ' , flags printString].
      b := 2]
    ifFalse: [
      p size < 93 ifTrue: [corrupt value: 'a short records entry'].
      b := 1].
  predLabel := self _u64: p at: b + 48.
  predRoot := self _rootIn: p at: b + 56.
  count := p unsignedLongAt: b + 88 + (kind6 ifTrue: [4] ifFalse: [0]) + 1 bigEndian: false.
  pos := b + 88 + (kind6 ifTrue: [8] ifFalse: [4]).
  kind6 ifTrue: [
    nranges := p unsignedLongAt: b + 88 + 1 bigEndian: false.
    ranges := OrderedCollection new.
    nranges timesRepeat: [
      | start end |
      pos + 32 > p size ifTrue: [corrupt value: 'a replica entry cut inside a range'].
      start := self _u64: p at: pos + 16.
      end := self _u64: p at: pos + 24.
      start > end ifTrue: [corrupt value: 'a replica entry with an inverted range'].
      ranges add: { p copyFrom: pos + 1 to: pos + 16. start. end }.
      pos := pos + 32].
    ranges := ranges asArray].
  records := OrderedCollection new.
  count timesRepeat: [
    | offset length |
    pos + 28 > p size ifTrue: [corrupt value: 'a records entry cut inside an item'].
    offset := self _u64: p at: pos + 16.
    length := p unsignedLongAt: pos + 25 bigEndian: false.
    pos + 28 + length > p size ifTrue: [corrupt value: 'a records entry cut inside a record'].
    records add: { p copyFrom: pos + 1 to: pos + 16. offset. p copyFrom: pos + 29 to: pos + 28 + length }.
    pos := pos + 28 + length].
  pos = p size ifFalse: [corrupt value: 'a records entry with trailing bytes'].
  ^ PBLogEntry kind: (p at: 1) label: (self _u64: p at: b) root: (self _rootIn: p at: b + 8)
    seq: (self _u64: p at: b + 40)
    pred: ((predLabel = 0 and: [predRoot isNil]) ifTrue: [nil] ifFalse: [PBLabeledRoot label: predLabel record: predRoot])
    records: records asArray ranges: ranges flags: flags.

"What the payloads anArrayOfPayloads (ByteArrays) of the log at aString hold: a PBLoggedRoots
 (proto_db _decode; pure). PBCorruptionError for an entry of kind 1 to 4 that is not 41 bytes,
 an unknown kind, a malformed kind-5 or kind-6 entry (short, cut inside an item, trailing bytes,
 other flag bits than ACCEPTED, a range with start > end) and two different roots of one kind
 with equal (label, epoch) (PBRootOrder)."
PBAcceptorLog class >> decode: anArrayOfPayloads path: aString
  | entries accepted committed promise top rejoined dataCount add |
  (anArrayOfPayloads isArray and: [anArrayOfPayloads allSatisfy: [:p | p isKindOf: ByteArray]]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorLog decode:path: takes an Array of ByteArrays, not ' , anArrayOfPayloads printString].
  entries := OrderedCollection new.
  promise := 0.
  top := 0.
  rejoined := false.
  dataCount := 0.
  "proto_db _Best add"
  add := [:kind :label :record |
    kind = 4
      ifTrue: [rejoined := true]
      ifFalse: [
        top := top max: label.
        kind = 3
          ifTrue: [promise := promise max: label]
          ifFalse: [
            | candidate |
            candidate := PBLabeledRoot label: label record: record.
            kind = 1
              ifTrue: [(PBRootOrder compare: candidate with: accepted) > 0 ifTrue: [accepted := candidate]]
              ifFalse: [(PBRootOrder compare: candidate with: committed) > 0 ifTrue: [committed := candidate]]]]].
  anArrayOfPayloads do: [:p |
    | entry |
    (p notEmpty and: [(p at: 1) = 5 or: [(p at: 1) = 6]])
      ifTrue: [
        entry := self _decodeData: p path: aString.
        dataCount := dataCount + 1.
        (entry kind = 5 or: [(entry flags bitAnd: 1) = 1]) ifTrue: [add value: 1 value: entry label value: entry root]]
      ifFalse: [
        p size = 41 ifFalse: [^ PBCorruptionError signal: 'The root log ' , aString , ' holds an entry of ' , p size printString , ' bytes'].
        ((p at: 1) between: 1 and: 4) ifFalse: [
          ^ PBCorruptionError signal: 'The root log ' , aString , ' holds an entry of unknown kind ' , (p at: 1) printString].
        entry := PBLogEntry kind: (p at: 1) label: (self _u64: p at: 1) root: (self _rootIn: p at: 9)
          seq: nil pred: nil records: nil ranges: nil flags: nil.
        add value: entry kind value: entry label value: entry root].
    entries add: entry].
  ^ PBLoggedRoots accepted: accepted committed: committed promise: promise top: top rejoined: rejoined
    dataEntryCount: dataCount entries: entries asArray.

"The text of anError, its class name when it has none."
PBAcceptorLog class >> _describe: anError
  ^ anError messageText isNil ifTrue: [anError class name] ifFalse: [anError messageText].

"Opens or creates the acceptor log at aPath (a String or FileReference) and its directory
 (proto_db RootsLog): resolves aPath to its real path (FileReference realPath; a symbolic link
 loop is PBUnexpectedError), which the log answers as its path, then takes the lock on that
 path , '.lock' first (a held lock is PBUserError naming
 the lock file), then opens the log (PBFramedLog openAppend:kind:, which refuses a file with more
 than one hard link and trims a torn tail), syncs the file, its directory and the directory's
 parent (whatever made the file, L10), and decodes its entries (PBCorruptionError). A failure to
 create, open or sync is PBUnexpectedError. On any refusal the file and the lock are released."
PBAcceptorLog class >> path: aPath
  | ref lockRef lock took log ok promised |
  "Resolved (proto_db: os.path.realpath before the lock file is named): a symbolic link to the
   log, or to a directory above it, names the same lock file as the real path."
  ref := [aPath asFileReference realPath] on: FileSystemError do: [:e |
    ^ PBUnexpectedError signal: 'Cannot resolve the path of the root log ' , aPath asFileReference pathString , ': ' , (self _describe: e)].
  [ref parent ensureCreateDirectory] on: FileSystemError do: [:e |
    ^ PBUnexpectedError signal: 'Cannot create the directory of the root log ' , ref pathString , ': ' , (self _describe: e)].
  lockRef := (ref pathString , self lockSuffix) asFileReference.
  lock := [BinaryFile open: lockRef options: #(#read #write #create)] on: FileSystemError do: [:e |
    ^ PBUnexpectedError signal: 'Cannot open the lock file ' , lockRef pathString , ': ' , (self _describe: e)].
  took := [lock tryLock] on: Error do: [:e |
    lock close.
    ^ PBUnexpectedError signal: 'Cannot lock ' , lockRef pathString , ': ' , (self _describe: e)].
  took ifFalse: [
    lock close.
    ^ PBUserError signal: 'The root log ' , ref pathString , ' is open elsewhere: its lock file ' , lockRef pathString
      , ' is held (another handle, or another process with the same node id)'].
  ok := false.
  [[log := self framedLogClass openAppend: ref kind: self logKind.
    log sync.
    FileSystem syncDirectory: ref parent.
    FileSystem syncDirectory: ref parent parent] on: FileSystemError do: [:e |
      ^ PBUnexpectedError signal: 'Cannot open the root log ' , ref pathString , ': ' , (self _describe: e)].
   promised := (self decode: log payloads path: ref pathString) promise.
   ok := true] ensure: [
     ok ifFalse: [[log isNil ifFalse: [log close]] ensure: [lock close]]].
  ^ self basicNew _setPath: ref lock: lock log: log promised: (Atom on: promised) failed: (Atom on: nil).

PBAcceptorLog >> _setPath: aFileReference lock: aBinaryFile log: aPBFramedLog promised: anAtom failed: anotherAtom
  "Runs once, on a fresh instance."
  path isNil ifFalse: [^ PBUserError signal: 'PBAcceptorLog is initialised once'].
  path := aFileReference.
  lock := aBinaryFile.
  log := aPBFramedLog.
  promised := anAtom.
  failed := anotherAtom.
  ^ self.

PBAcceptorLog >> path
  ^ path.

PBAcceptorLog >> isClosed
  ^ log isClosed.

"True once a write or a sync failed: the log refuses every later write until it is reopened."
PBAcceptorLog >> isFailed
  ^ failed value notNil.

"Refuses a write through a closed (PBClosedError) or failed (PBUnexpectedError) log."
PBAcceptorLog >> _checkWritable
  log isClosed ifTrue: [^ PBClosedError signal: 'The root log ' , path pathString , ' is closed'].
  failed value isNil ifFalse: [
    ^ PBUnexpectedError signal: 'The root log ' , path pathString , ' refuses writes: an earlier write failed ('
      , failed value , '); reopen it (close and reopen the space) to write again'].

"Appends aPayload, synced when aBoolean. Any failure poisons the log: the file may end in a
 torn entry, or hold what a sync could not confirm. A file system error is PBUnexpectedError;
 any other error is passed on."
PBAcceptorLog >> _append: aPayload sync: aBoolean
  [log append: aPayload sync: aBoolean] on: Error do: [:e |
    failed value: e class name , ': ' , (self class _describe: e) ifCurrent: nil.
    (e isKindOf: FileSystemError) ifFalse: [e pass].
    ^ PBUnexpectedError signal: 'Writing the root log ' , path pathString , ' failed: ' , (self class _describe: e)].

"Appends an #accepted root, synced before this answers, or a #committed root, durable with the
 next synced entry (R67). anInteger is the label, aPBRootRecordOrNil the root (nil: the empty
 space). PBValidationError for another kind or a bad argument, PBClosedError when closed,
 PBUnexpectedError when failed or when the write fails. As proto_db RootsLog.append, the kind and
 the entry are checked before the handle."
PBAcceptorLog >> append: aKind label: anInteger root: aPBRootRecordOrNil
  | payload |
  (aKind == #accepted or: [aKind == #committed]) ifFalse: [
    ^ PBValidationError signal: 'PBAcceptorLog append:label:root: takes #accepted or #committed, not ' , aKind printString].
  payload := self class encode: aKind label: anInteger root: aPBRootRecordOrNil.
  self _checkWritable.
  self _append: payload sync: aKind == #accepted.

"Makes the promise of aTerm durable (synced) before it is sent. A term not above the promise
 already durable writes nothing (proto_db RootsLog.promise). As proto_db, the handle is checked
 first (PBClosedError, PBUnexpectedError), then the term (PBValidationError)."
PBAcceptorLog >> promise: aTerm
  | payload current |
  self _checkWritable.
  payload := self class encode: #promise label: aTerm root: nil.
  current := promised value.
  aTerm <= current ifTrue: [^ self].
  self _append: payload sync: true.
  promised value: aTerm ifCurrent: current.

"Appends the rejoined marker, synced (written last by a rejoin, or at a cluster's first start)."
PBAcceptorLog >> markRejoined
  self _checkWritable.
  self _append: (self class encode: #rejoined label: 0 root: nil) sync: true.

"What the log file holds now: a PBLoggedRoots (read by path, as proto_db load; a torn tail is
 ignored, not trimmed). Works on a closed or failed log."
PBAcceptorLog >> load
  ^ self class decode: (self class framedLogClass read: path kind: self class logKind) payloads path: path pathString.

"Closes the file, then releases the lock, whatever the close signalled. Idempotent."
PBAcceptorLog >> close
  [log close] ensure: [lock close].

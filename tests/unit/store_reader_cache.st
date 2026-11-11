"EXPECT: ok 25"
"PBFileStorage's reader cache and file handles (Task 11 review I1, M5, M6). The
 interleavings that a race would produce are forced through the seams, with no
 timing and no actors:
   PBFileStorage >> _openReader:        opens the reader of a segment (cache miss)
   PBSegmentReader class >> _openFile:  opens the segment's BinaryFile
 race     while the outer load opens its reader, another load installs one first:
          the outer load answers the installed reader and closes its own
 close    the storage closes while a load is installing its reader: the load
          signals PBClosedError and the reader is closed, not cached
 handles  every refusal of a segment (foreign header, version, magic, truncated
          header) and of an open (a damaged root record) closes the file it opened
 eio      a file-system error while the header is read (a fake file from the
          _openFile: seam) is PBUnexpectedError naming the segment, and the
          file is closed"
Import from: 'protobase'.
Import from: '_check'.

PBSegmentReader subclass: #RecordingReader classVariableNames: 'Opened'.

RecordingReader class >> _openFile: aFileReference
  | file |
  file := super _openFile: aFileReference.
  Opened isNil ifTrue: [Opened := OrderedCollection new].
  Opened add: file.
  ^ file.

RecordingReader class >> openedFiles
  Opened isNil ifTrue: [Opened := OrderedCollection new].
  ^ Opened.

"A file whose every read fails as an I/O error would (EIO)."
Object subclass: #FailingFile instanceVariableNames: 'closed'.

FailingFile >> readAt: anOffset size: n
  ^ FileSystemError signal: 'read failed: Input/output error'.

FailingFile >> size
  ^ FileSystemError signal: 'fstat failed: Input/output error'.

FailingFile >> close
  closed := true.

FailingFile >> isClosed
  ^ closed == true.

PBSegmentReader subclass: #FailingReader classVariableNames: 'Last'.

FailingReader class >> _openFile: aFileReference
  Last := FailingFile new.
  ^ Last.

FailingReader class >> lastFile
  ^ Last.

PBFileStorage subclass: #RecordingStorage instanceVariableNames: 'opened mode'.

RecordingStorage >> mode: aSymbol
  mode := aSymbol.

RecordingStorage >> opened
  opened isNil ifTrue: [opened := OrderedCollection new].
  ^ opened.

RecordingStorage >> _openReader: aByteArray
  | mine |
  mine := (mode = #eio ifTrue: [FailingReader] ifFalse: [RecordingReader])
    segment: aByteArray file: (self _segmentFile: aByteArray).
  self opened add: mine.
  (mode = #race and: [self opened size = 1]) ifTrue: [self _readerFor: aByteArray].
  mode = #close ifTrue: [self close].
  ^ mine.

| c base seg other w good dir st ptr rec spaceAt files |
c := Check new.
base := FileSystem temp / ('pbst-store-cache-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
seg := ByteArray fromHex: '11111111111111111111111111111111'.
other := ByteArray fromHex: '33333333333333333333333333333333'.
w := WriteStream on: ByteArray new.
w nextPutAll: (PBSegmentHeader encodeSegment: seg).
w nextPutAll: (PBRecordHeader encodeKind: 2 payload: #[1 2 3]).
good := w contents.
ptr := PBAtomPointer segment: seg offset: 26.
spaceAt := [:aName :fileSeg :segBytes :rootBytes |
  dir := base / aName.
  dir ensureCreateDirectory.
  (dir / (fileSeg hex asLowercase , '.seg')) binaryContents: segBytes.
  rootBytes isNil ifFalse: [(dir / 'space.root') binaryContents: rootBytes].
  dir].

"--- race: a winner is installed while the outer load opens its own reader ---"
st := RecordingStorage path: (spaceAt value: 'race' value: seg value: good value: nil).
st mode: #race.
rec := st recordAt: ptr.
c that: 'race: the load answers the record' is: (rec at: 2) equals: #[1 2 3].
c that: 'race: two readers were opened' is: st opened size equals: 2.
c that: 'race: the loser closed its own reader' isTrue: (st opened at: 1) isClosed.
c that: 'race: the winner stays open' is: (st opened at: 2) isClosed equals: false.
c that: 'race: one reader cached' is: st openSegmentCount equals: 1.
rec := st recordAt: ptr.
c that: 'race: a later load uses the cached reader' is: st opened size equals: 2.
st close.
c that: 'race: close closes the winner' isTrue: (st opened at: 2) isClosed.
c that: 'race: close empties the cache' is: st openSegmentCount equals: 0.

"--- close while a load installs its reader ---"
st := RecordingStorage path: (spaceAt value: 'closing' value: seg value: good value: nil).
st mode: #close.
c that: 'close: the load signals PBClosedError' signals: PBClosedError during: [st recordAt: ptr].
c that: 'close: one reader was opened' is: st opened size equals: 1.
c that: 'close: it is closed' isTrue: (st opened at: 1) isClosed.
c that: 'close: nothing stays cached' is: st openSegmentCount equals: 0.
c that: 'close: the storage is closed' isTrue: st isClosed.

"--- a plain close empties the cache ---"
st := PBFileStorage path: (spaceAt value: 'plain' value: seg value: good value: nil).
st recordAt: ptr.
c that: 'plain: one reader' is: st openSegmentCount equals: 1.
st close.
c that: 'plain: close empties the cache' is: st openSegmentCount equals: 0.

"--- every refusal closes the file it opened ---"
files := RecordingReader openedFiles.
files removeAll: files copy.
st := RecordingStorage path: (spaceAt value: 'foreign' value: other value: good value: nil).
c that: 'handles: a foreign header' signals: PBCorruptionError during: [
  st recordAt: (PBAtomPointer segment: other offset: 26)].
st := RecordingStorage path: (spaceAt value: 'v5' value: seg
  value: (good copyReplaceFrom: 9 to: 10 with: #[5 0]) value: nil).
c that: 'handles: a version 5 header' signals: PBNotSupportedError during: [st recordAt: ptr].
st := RecordingStorage path: (spaceAt value: 'magic' value: seg
  value: (good copyReplaceFrom: 1 to: 1 with: #[0]) value: nil).
c that: 'handles: a bad magic' signals: PBCorruptionError during: [st recordAt: ptr].
st := RecordingStorage path: (spaceAt value: 'short' value: seg value: (good copyFrom: 1 to: 10) value: nil).
c that: 'handles: a truncated header' signals: PBCorruptionError during: [st recordAt: ptr].
c that: 'handles: a damaged root record at open' signals: PBCorruptionError during: [
  RecordingStorage path: (spaceAt value: 'damaged' value: seg value: (good copyFrom: 1 to: good size - 1)
    value: (PBRootRecord segment: seg offset: 26 epoch: 1) encode)].
c that: 'handles: five files were opened' is: files size equals: 5.
c that: 'handles: every one is closed' isTrue: (files allSatisfy: [:f | f isClosed]).

"--- eio: a file-system error while the header is read ---"
st := RecordingStorage path: (spaceAt value: 'eio' value: seg value: good value: nil).
st mode: #eio.
c that: 'eio: PBUnexpectedError naming the segment' signals: PBUnexpectedError containing: seg hex asLowercase
  during: [st recordAt: ptr].
c that: 'eio: the file is closed' isTrue: FailingReader lastFile isClosed.
c that: 'eio: nothing cached' is: st openSegmentCount equals: 0.
st close.

base deleteAll.
c report displayNl.

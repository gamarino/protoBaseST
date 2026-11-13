"-- cluster/log.st: framed append-only logs with the linear torn-tail search --

The log file format of ProtoBase proto_db/storage/logfile.py (format version 2), byte for
byte: the conformance vectors under tests/conformance/vectors/cluster and invalid/log-* are
the oracle. A cluster node keeps three of them (ROOT, RANG, SEGS).

  header  PDB2LOG 00 | version u16 LE (2) | kind (4 ASCII bytes)             14 bytes
  frame   C1 F7 | length u32 LE (> 0) | payload CRC32 | header CRC32 | payload
          (the header CRC covers the ten bytes before it, so a frame header validates
           itself without reading the payload; LE throughout, CRC-32 as zlib's)

Reading (PBFramedLog scan:kind:path:) walks the frames from the header. At the first position
that holds no valid frame it decides between a torn tail (an interrupted append: dropped) and
mid-log corruption (PBCorruptionError). It is a torn tail when fewer than 14 bytes remain,
when the frame header there is valid and its frame extends past the end, or when no valid
frame starts later: after the frame's extent when its header is valid, at any later offset
when it is not. The search visits each candidate C1 F7 once and is linear in the bytes
searched (ruling R14 removed the first port because its worst case was quadratic):
a candidate costs the CRC of its 10-byte header, and a candidate with a valid header whose
extent fits is checked directly up to 16384 payload bytes; a longer payload's CRC comes from
prefix CRCs of the searched region kept at 4096-byte checkpoints and CRC32 combine:with:length:,
so crafted header-valid candidates cost a bounded number of bytes each.

Every CRC is computed by PBFramedLog class >> crcOf:from:to: (offsets from 0, end excluded),
the one seam a test counts the CRC'd bytes through. Values answered here are immutable; a
PBFramedLog holds only the open file and the payloads read at open."

Import from: 'protobase/errors'.

"=== PBLogScan =============================================================="

"What scan:kind:path: found: the payloads of the valid frames in order (an Array of
 ByteArrays), the offset just past the last valid frame (0 when even the header is missing or
 torn) and whether the bytes past it form a torn tail to drop."
Object subclass: #PBLogScan instanceVariableNames: 'payloads validEnd torn'.

PBLogScan class >> payloads: anArray validEnd: anInteger torn: aBoolean
  ^ self basicNew _setPayloads: anArray validEnd: anInteger torn: aBoolean.

PBLogScan >> _setPayloads: anArray validEnd: anInteger torn: aBoolean
  "Runs once, on a fresh instance."
  payloads isNil ifFalse: [^ PBUserError signal: 'PBLogScan is immutable'].
  payloads := anArray.
  validEnd := anInteger.
  torn := aBoolean.
  ^ self.

PBLogScan >> payloads
  ^ payloads.

PBLogScan >> validEnd
  ^ validEnd.

PBLogScan >> isTorn
  ^ torn.

"=== PBFramedLog ============================================================"

Object subclass: #PBFramedLog instanceVariableNames: 'path file payloads'.

PBFramedLog class >> headerSize
  ^ 14.

PBFramedLog class >> frameOverhead
  ^ 14.

"The size of the payload CRC prefix checkpoints and the longest payload checked directly."
PBFramedLog class >> crcCheckpoint
  ^ 4096.

PBFramedLog class >> crcDirect
  ^ 16384.

"The 14 header bytes of a log of aKind (a String of 4 ASCII characters: 'ROOT', 'RANG' or 'SEGS')."
PBFramedLog class >> header: aKind
  | w kindBytes |
  kindBytes := (aKind isString and: [aKind allSatisfy: [:c | c value < 128]]) ifTrue: [aKind utf8Encoded] ifFalse: [nil].
  (kindBytes notNil and: [kindBytes size = 4]) ifFalse: [
    ^ PBValidationError signal: 'PBFramedLog: a log kind is a String of 4 ASCII characters, not ' , aKind printString].
  w := WriteStream on: ByteArray new.
  w nextPutAll: #[80 68 66 50 76 79 71 0].
  w nextPutUnsigned: 2 width: 2 bigEndian: false.
  w nextPutAll: kindBytes.
  ^ w contents.

"The CRC-32 of aByteArray from offset start up to offset end (end excluded, offsets from 0).
 The only place a CRC of this module is computed."
PBFramedLog class >> crcOf: aByteArray from: start to: end
  ^ end <= start ifTrue: [0] ifFalse: [(aByteArray copyFrom: start + 1 to: end) crc32].

"The bytes that append a frame holding aPayload (a non-empty ByteArray) to a log."
PBFramedLog class >> frame: aPayload
  | body w |
  ((aPayload isKindOf: ByteArray) and: [aPayload notEmpty]) ifFalse: [
    ^ PBValidationError signal: 'PBFramedLog: a payload is a non-empty ByteArray, not ' , aPayload printString].
  w := WriteStream on: ByteArray new.
  w nextPutAll: #[193 247].
  w nextPutUnsigned: aPayload size width: 4 bigEndian: false.
  w nextPutUnsigned: (self crcOf: aPayload from: 0 to: aPayload size) width: 4 bigEndian: false.
  body := w contents.
  w nextPutUnsigned: (self crcOf: body from: 0 to: 10) width: 4 bigEndian: false.
  w nextPutAll: aPayload.
  ^ w contents.

"(length payloadCrc) of the valid frame header at offset pos of data (size bytes), or nil
 (truncated or invalid header)."
PBFramedLog class >> _headerAt: pos in: data size: size
  | length |
  pos + 14 > size ifTrue: [^ nil].
  ((data at: pos + 1) = 193 and: [(data at: pos + 2) = 247]) ifFalse: [^ nil].
  length := data unsignedLongAt: pos + 3 bigEndian: false.
  length = 0 ifTrue: [^ nil].
  (self crcOf: data from: pos to: pos + 10) = (data unsignedLongAt: pos + 11 bigEndian: false) ifFalse: [^ nil].
  ^ { length. data unsignedLongAt: pos + 7 bigEndian: false }.

"The payload of the valid frame at offset pos of data, or nil."
PBFramedLog class >> _frameAt: pos in: data size: size
  | header end |
  header := self _headerAt: pos in: data size: size.
  header isNil ifTrue: [^ nil].
  end := pos + 14 + (header at: 1).
  end > size ifTrue: [^ nil].
  (self crcOf: data from: pos + 14 to: end) = (header at: 2) ifFalse: [^ nil].
  ^ data copyFrom: pos + 15 to: end.

"The offset of the first valid frame at or after offset start of data (size bytes), or nil.
 Exact (the answer of trying every offset) and linear in size - start."
PBFramedLog class >> _firstValidFrameIn: data from: start size: size
  | last points prefixAt payloadCrc |
  last := size - 14.
  start > last ifTrue: [^ nil].
  points := OrderedCollection with: 0.
  "The CRC of data from start to offset, from the checkpoints (one per crcCheckpoint bytes)."
  prefixAt := [:offset |
    | index base |
    index := (offset - start) // self crcCheckpoint.
    [points size <= index] whileTrue: [
      | from |
      from := start + ((points size - 1) * self crcCheckpoint).
      points add: (CRC32 combine: points last
        with: (self crcOf: data from: from to: from + self crcCheckpoint) length: self crcCheckpoint)].
    base := start + (index * self crcCheckpoint).
    CRC32 combine: (points at: index + 1)
      with: (self crcOf: data from: base to: offset) length: offset - base].
  "crc(data[from to end]) = crc(end) xor shift(crc(from), end - from), the shift being a
   combine with an empty tail."
  payloadCrc := [:from :to |
    (prefixAt value: to) bitXor: (CRC32 combine: (prefixAt value: from) with: 0 length: to - from)].
  start to: last do: [:pos |
    ((data at: pos + 1) = 193 and: [(data at: pos + 2) = 247]) ifTrue: [
      | header payloadStart payloadEnd actual |
      header := self _headerAt: pos in: data size: size.
      header isNil ifFalse: [
        payloadStart := pos + 14.
        payloadEnd := payloadStart + (header at: 1).
        payloadEnd > size ifFalse: [
          actual := (header at: 1) <= self crcDirect
            ifTrue: [self crcOf: data from: payloadStart to: payloadEnd]
            ifFalse: [payloadCrc value: payloadStart value: payloadEnd].
          actual = (header at: 2) ifTrue: [^ pos]]]]].
  ^ nil.

"True when every byte of data from index from (1-based) on is zero."
PBFramedLog class >> _isZeroFrom: from in: data
  from to: data size do: [:i | (data at: i) = 0 ifFalse: [^ false]].
  ^ true.

"Decodes the log aByteArray of aKind read from aPath (the name used in messages): a PBLogScan.
 A header that is a prefix of the expected one, followed by zero bytes only, is a new log (torn
 when any byte is there); another header is PBCorruptionError, another version
 PBNotSupportedError, mid-log corruption PBCorruptionError naming the offset."
PBFramedLog class >> scan: aByteArray kind: aKind path: aString
  | size expected frames pos keep version found |
  size := aByteArray size.
  expected := self header: aKind.
  (size < 14 or: [(aByteArray copyFrom: 1 to: 14) ~= expected]) ifTrue: [
    keep := 0.
    [keep < (size min: 14) and: [(aByteArray at: keep + 1) = (expected at: keep + 1)]] whileTrue: [keep := keep + 1].
    (self _isZeroFrom: keep + 1 in: aByteArray) ifTrue: [^ PBLogScan payloads: #() validEnd: 0 torn: size > 0].
    "Bytes are compared before anything is decoded: a foreign file is never an encoding error."
    (size >= 14 and: [(aByteArray copyFrom: 1 to: 8) = (expected copyFrom: 1 to: 8)]) ifTrue: [
      version := aByteArray unsignedShortAt: 9 bigEndian: false.
      version = 2 ifFalse: [
        ^ PBNotSupportedError signal: 'The log ' , aString , ' has format version ' , version printString
          , '; this version reads 2'].
      found := aByteArray copyFrom: 11 to: 14.
      found = (expected copyFrom: 11 to: 14) ifFalse: [
        ^ PBCorruptionError signal: 'The log ' , aString , ' is a log of kind (hex) ' , found hex
          , ', not a ' , aKind printString , ' log']].
    ^ PBCorruptionError signal: 'The log ' , aString , ' does not start with a valid ' , aKind printString
      , ' log header but holds other data'].
  frames := OrderedCollection new.
  pos := 14.
  [pos < size] whileTrue: [
    | payload |
    payload := self _frameAt: pos in: aByteArray size: size.
    payload isNil ifTrue: [
      | header later |
      header := self _headerAt: pos in: aByteArray size: size.
      later := header isNil
        ifTrue: [self _firstValidFrameIn: aByteArray from: pos + 1 size: size]
        ifFalse: [
          pos + 14 + (header at: 1) > size
            ifTrue: [nil]
            ifFalse: [self _firstValidFrameIn: aByteArray from: pos + 14 + (header at: 1) size: size]].
      later isNil ifFalse: [
        ^ PBCorruptionError signal: 'The log ' , aString , ' has mid-log corruption: the entry at offset '
          , pos printString , ' is invalid but a valid entry follows at offset ' , later printString
          , ' (not a torn tail; nothing was truncated)'].
      ^ PBLogScan payloads: frames asArray validEnd: pos torn: true].
    frames add: payload.
    pos := pos + 14 + payload size].
  ^ PBLogScan payloads: frames asArray validEnd: pos torn: false.

"The scan of the log at aPath (a String or FileReference) of aKind; a missing file is an empty
 log. Never writes: a torn tail is reported, not trimmed."
PBFramedLog class >> read: aPath kind: aKind
  | ref bytes |
  ref := aPath asFileReference.
  bytes := [ref binaryContents] on: FileSystemError do: [:e |
    (e isKindOf: FileDoesNotExist) ifTrue: [^ PBLogScan payloads: #() validEnd: 0 torn: false].
    ^ PBUnexpectedError signal: 'PBFramedLog: cannot read ' , ref pathString , ': ' , e messageText].
  ^ self scan: bytes kind: aKind path: ref pathString.

"aString on stderr; never signals (as PBFileStorage >> _log:, the convention for a recoverable
 event). A seam: tests capture it."
PBFramedLog class >> _warn: aString
  [Stdio stderr nextPutAll: 'PBFramedLog: ' , aString; lf; flush] on: Error do: [:e | nil].

"Opens the log at aPath of aKind for appends: creates the file (and its directory) with its
 header when absent, truncates a torn tail to the last valid frame, and syncs the file (and,
 for a new file, its directory and the parent directory) before answering, so an append never
 lands after torn bytes (a trimmed tail is reported on stderr: the byte count and the offset). The payloads found are those the log held at open. The file is closed
 on any refusal."
PBFramedLog class >> openAppend: aPath kind: aKind
  | ref directory createdDir existed handle ok scan |
  ref := aPath asFileReference.
  directory := ref parent.
  createdDir := directory exists not.
  existed := ref exists.
  directory ensureCreateDirectory.
  handle := BinaryFile open: ref options: #(#read #write #create).
  ok := false.
  [scan := self scan: (handle readAt: 0 size: handle size) kind: aKind path: ref pathString.
   scan isTorn ifTrue: [
     self _warn: 'The log ' , ref pathString , ' ends in a torn tail of ' , (handle size - scan validEnd) printString
       , ' bytes (an interrupted append); truncated to its last valid entry at offset ' , scan validEnd printString.
     handle truncateTo: scan validEnd.
     handle sync].
   scan validEnd = 0 ifTrue: [
     handle append: (self header: aKind).
     handle sync].
   existed ifFalse: [
     FileSystem syncDirectory: directory.
     createdDir ifTrue: [FileSystem syncDirectory: directory parent]].
   ok := true] ensure: [ok ifFalse: [handle close]].
  ^ self basicNew _setPath: ref file: handle payloads: scan payloads.

PBFramedLog >> _setPath: aFileReference file: aBinaryFile payloads: anArray
  "Runs once, on a fresh instance."
  path isNil ifFalse: [^ PBUserError signal: 'PBFramedLog is initialised once'].
  path := aFileReference.
  file := aBinaryFile.
  payloads := anArray.
  ^ self.

PBFramedLog >> path
  ^ path.

"The payloads the log held when it was opened."
PBFramedLog >> payloads
  ^ payloads.

PBFramedLog >> isClosed
  ^ file isClosed.

PBFramedLog >> close
  file close.

"Appends aPayload (a non-empty ByteArray) as one frame and answers the offset it starts at;
 aBoolean true syncs the file before answering."
PBFramedLog >> append: aPayload sync: aBoolean
  | offset |
  file isClosed ifTrue: [^ PBClosedError signal: 'PBFramedLog: the log ' , path pathString , ' is closed'].
  offset := file append: (self class frame: aPayload).
  aBoolean ifTrue: [file sync].
  ^ offset.

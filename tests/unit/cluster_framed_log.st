"EXPECT: ok 16"
"PBFramedLog (cluster/log.st): the framed log of proto_db's logfile.py, byte for byte, and its
 linear torn-tail search. The frame of a 3-byte payload is also checked against the bytes
 CPython's struct and zlib make (c1f7 | 03000000 | crc32 | crc32 of the ten bytes | payload)."
Import from: 'protobase'.
| failures tests check bigSize base header frame3 payloads file expectCorruption big w log scan blockHeader block blocks bodyLength fitting bound expectRefusal junk |
failures := OrderedCollection new.
tests := Set new.
check := [:name :ok | ok ifFalse: [failures add: name]].
expectRefusal := [:name :bytes :errorClass |
  check value: name value: ([PBFramedLog scan: bytes kind: 'ROOT' path: 'x.log'. false] on: Error do: [:e | e class == errorClass])].
expectCorruption := [:name :bytes :needle |
  | text |
  text := [PBFramedLog scan: bytes kind: 'ROOT' path: 'x.log'. nil] on: PBCorruptionError do: [:e | e messageText].
  check value: name value: (text notNil and: [text includesSubstring: needle])].
base := FileSystem temp / ('pbst-framed-log-' , Smalltalk pid printString).
base deleteAll.
header := PBFramedLog header: 'ROOT'.
frame3 := [:n | PBFramedLog frame: (ByteArray withAll: ((1 to: 3) collect: [:i | n * 10 + i]))].
payloads := (1 to: 3) collect: [:n | ByteArray withAll: ((1 to: 3) collect: [:i | n * 10 + i])].

tests add: 1.
"1. the header bytes"
check value: 'header bytes' value: header hex asLowercase = '504442324c4f47000200524f4f54'.

tests add: 2.
"2. the frame bytes, from the independent table"
check value: 'frame bytes' value: (PBFramedLog frame: (ByteArray withAll: #(1 2 3))) hex asLowercase = 'c1f7030000001d80bc555474d818010203'.

tests add: 3.
"3. header and three frames scan to the three payloads"
file := header , (frame3 value: 1) , (frame3 value: 2) , (frame3 value: 3).
scan := PBFramedLog scan: file kind: 'ROOT' path: 'x.log'.
check value: 'scan of three frames' value: (scan payloads asArray = payloads asArray and: [scan validEnd = file size and: [scan isTorn not]]).

tests add: 4.
"4. a file cut inside its last frame is torn at the end of frame 2"
scan := PBFramedLog scan: (file copyFrom: 1 to: file size - 4) kind: 'ROOT' path: 'x.log'.
check value: 'torn last frame' value: (scan isTorn and: [scan payloads size = 2 and: [scan validEnd = (14 + (2 * 17))]]).

tests add: 5.
"5. damaged frame 2 followed by valid frame 3 is mid-log corruption"
w := file copyReplaceFrom: 46 to: 46 with: (ByteArray withAll: #(255)).
expectCorruption value: 'mid-log corruption' value: w value: 'mid-log'.

tests add: 6.
"6. a header prefix is a new log with no payload"
scan := PBFramedLog scan: (header copyFrom: 1 to: 4) kind: 'ROOT' path: 'x.log'.
check value: 'header prefix is a new log' value: (scan payloads isEmpty and: [scan validEnd = 0 and: [scan isTorn]]).

tests add: 7.
"7. openAppend: truncates a torn tail; the next append lands at validEnd"
(base / 'a' / 'torn.log') parent ensureCreateDirectory.
(base / 'a' / 'torn.log') binaryContents: (file copyFrom: 1 to: file size - 4).
log := PBFramedLog openAppend: base / 'a' / 'torn.log' kind: 'ROOT'.
check value: 'openAppend torn payloads' value: log payloads size = 2.
check value: 'append lands at validEnd' value: ((log append: payloads last sync: true) = (14 + (2 * 17))
  and: [(base / 'a' / 'torn.log') binaryContents = (file copyFrom: 1 to: 14 + (3 * 17))]).
log close.

tests add: 8.
"8. a zero-length payload is refused"
check value: 'zero-length payload refused' value:
  ([PBFramedLog frame: ByteArray new. false] on: PBValidationError do: [:e | true]).

tests add: 9.
"9. linearity of the header-CRC cost: the random bytes never form a valid frame header (a header
 CRC matches by chance with probability 2^-32), so this case bounds only the 10-byte header CRC
 paid per candidate. Case 13 bounds the payload checks. One valid frame, then C1 F7 repeated with random bytes between, 1 MiB"
PBFramedLog subclass: #CountingFramedLog instanceVariableNames: '' classVariableNames: 'Counter'.
CountingFramedLog class >> _setCounter: anAtom
  Counter := anAtom.
CountingFramedLog class >> counter
  ^ Counter.
CountingFramedLog class >> crcOf: aByteArray from: start to: end
  | n |
  [n := Counter value. Counter value: n + (end - start) ifCurrent: n] whileFalse: [nil].
  ^ super crcOf: aByteArray from: start to: end.
CountingFramedLog _setCounter: (Atom on: 0).
PBFramedLog subclass: #WarnFramedLog instanceVariableNames: '' classVariableNames: 'Seen'.
WarnFramedLog class >> _setSeen: anAtom
  Seen := anAtom.
WarnFramedLog class >> seen
  ^ Seen.
WarnFramedLog class >> _warn: aString
  Seen value: aString ifCurrent: Seen value.
WarnFramedLog _setSeen: (Atom on: nil).
big := WriteStream on: ByteArray new.
bigSize := 31.
big nextPutAll: header; nextPutAll: (frame3 value: 1).
[bigSize < (1024 * 1024)] whileTrue: [big nextPutAll: (ByteArray withAll: #(193 247)); nextPutAll: (ByteArray randomBytes: 14). bigSize := bigSize + 16].
big := big contents.
scan := CountingFramedLog scan: big kind: 'ROOT' path: 'big.log'.
check value: 'linear torn tail search' value: (scan isTorn and: [scan payloads size = 1 and: [CountingFramedLog counter value <= (3 * big size)]]).

tests add: 10.
"10. a long header-valid payload after damage is found through the prefix CRCs"
w := WriteStream on: ByteArray new.
w nextPutAll: header; nextPutAll: (frame3 value: 1).
w nextPutAll: (frame3 value: 2).
(PBFramedLog frame: (ByteArray new: 50000)) do: [:b | w nextPut: b].
w := w contents.
w := w copyReplaceFrom: 46 to: 46 with: (ByteArray withAll: #(255)).
expectCorruption value: 'mid-log corruption through a long payload' value: w value: 'mid-log'.

tests add: 11.
"11. a new log is created with its header, and reopening reads what was appended"
log := PBFramedLog openAppend: base / 'b' / 'c' / 'new.log' kind: 'SEGS'.
log append: (ByteArray withAll: #(7 7)) sync: false.
log append: (ByteArray withAll: #(8)) sync: true.
check value: 'new log is empty' value: log payloads isEmpty.
log close.
check value: 'append after close' value: ([log append: (ByteArray withAll: #(1)) sync: true. false] on: PBClosedError do: [:e | true]).
log := PBFramedLog openAppend: base / 'b' / 'c' / 'new.log' kind: 'SEGS'.
check value: 'reopen reads payloads' value: (log payloads asArray = { (ByteArray withAll: #(7 7)). (ByteArray withAll: #(8)) } and: [log isClosed not]).
log close.
check value: 'read: never writes' value: ((PBFramedLog read: base / 'b' / 'c' / 'new.log' kind: 'SEGS') payloads size = 2).
tests add: 12.
"12. a foreign header is a classified refusal, never an encoding error (bytes are compared)"
expectRefusal value: 'non-UTF-8 kind' value: (ByteArray withAll: #(80 68 66 50 76 79 71 0 2 0 255 254 253 252)) value: PBCorruptionError.
expectRefusal value: 'foreign binary file' value: (ByteArray withAll: #(1 2 3 4 5 6 7 8 9 10 255 254 253 252 0 0)) value: PBCorruptionError.
expectRefusal value: 'another version with a non-UTF-8 kind' value: (ByteArray withAll: #(80 68 66 50 76 79 71 0 3 0 255 254 253 252)) value: PBNotSupportedError.
expectRefusal value: 'foreign magic, valid-looking kind' value: (ByteArray withAll: #(1 2 3 4 5 6 7 8 2 0 82 79 79 84 9)) value: PBCorruptionError.
expectRefusal value: 'short foreign header' value: (ByteArray withAll: #(255 1 2)) value: PBCorruptionError.

tests add: 13.
"13. linearity of the payload checks: after one invalid byte, 25,000 header-valid candidates (one
 every 16 bytes) each claim a 100,000-byte payload that fits for most of them. Direct CRCs would
 cost fitting x 100,000 bytes, quadratic in the file (R14); the prefix checksums cost at most two
 partial checkpoints (2 x 4096) per candidate, plus one pass over the file."
bodyLength := 100000.
blocks := 25000.
w := WriteStream on: ByteArray new.
w nextPutAll: (ByteArray withAll: #(193 247)).
w nextPutUnsigned: bodyLength width: 4 bigEndian: false.
w nextPutUnsigned: 12345 width: 4 bigEndian: false.
blockHeader := w contents.
w nextPutUnsigned: blockHeader crc32 width: 4 bigEndian: false.
w nextPutAll: (ByteArray withAll: #(0 0)).
block := w contents.
w := WriteStream on: ByteArray new.
w nextPutAll: header; nextPutAll: (frame3 value: 1); nextPutAll: (ByteArray withAll: #(0)).
1 to: blocks do: [:k | w nextPutAll: block].
big := w contents.
fitting := ((16 * blocks) - 14 - bodyLength) // 16 + 1.
bound := big size + (blocks * 10) + (fitting * 2 * 4096).
check value: 'the bound separates the prefix path from a direct CRC' value: bound * 5 < (fitting * bodyLength).
CountingFramedLog counter value: 0 ifCurrent: CountingFramedLog counter value.
scan := CountingFramedLog scan: big kind: 'ROOT' path: 'big.log'.
check value: 'linear payload checks' value: (scan isTorn and: [scan payloads size = 1 and: [CountingFramedLog counter value <= bound]]).

tests add: 14.
"14. a trimmed torn tail is reported, with its byte count and the offset it was cut at"
(base / 'd') ensureCreateDirectory.
(base / 'd' / 'torn.log') binaryContents: (file copyFrom: 1 to: file size - 4).
log := WarnFramedLog openAppend: base / 'd' / 'torn.log' kind: 'ROOT'.
log close.
check value: 'torn tail reported' value: (WarnFramedLog seen value notNil
  and: [(WarnFramedLog seen value includesSubstring: '13 bytes') and: [WarnFramedLog seen value includesSubstring: 'offset 48']]).

tests add: 15.
"15. a log kind is 4 ASCII bytes"
check value: 'kind of 3 characters' value: ([PBFramedLog header: 'ROO'. false] on: PBValidationError do: [:e | true]).
check value: 'non-ASCII kind' value: ([PBFramedLog header: 'RO' , (String with: (Character value: 233)) , 'T'. false] on: PBValidationError do: [:e | true]).
tests add: 16.
"16. a log file with two hard links is refused before it is read or repaired (proto_db open_log):
 PBLockingError naming the count, the torn tail left in place"
(base / 'e') ensureCreateDirectory.
(base / 'e' / 'torn.log') binaryContents: (file copyFrom: 1 to: file size - 4).
check value: 'hard link made' value: (OSProcess run: 'ln' arguments: { (base / 'e' / 'torn.log') pathString. (base / 'e' / 'alias.log') pathString }) exitCode = 0.
check value: 'two names refused' value: ([PBFramedLog openAppend: base / 'e' / 'alias.log' kind: 'ROOT'. nil]
  on: PBLockingError do: [:e | e messageText]) = ('The log ' , (base / 'e' / 'alias.log') pathString
  , ' has 2 hard links; a log must have exactly one name (remove the other links) because opening repairs the file and its lock is named after the path').
check value: 'nothing repaired' value: (base / 'e' / 'torn.log') binaryContents = (file copyFrom: 1 to: file size - 4).
base deleteAll.
failures isEmpty ifFalse: [failures do: [:f | ('FAIL ' , f) displayNl]. Smalltalk exit: 1].
'ok ' , tests size printString

"EXPECT: framed logs ok"
"The framed log files of the cluster section (README, 'Using the vectors', 8) and the invalid
 vectors of layer 'log', read with PBFramedLog:
   roots-torn.log  scans to the manifest's entry count with the manifest's valid_end, torn
   segments.log    one payload: the 16 bytes of the listed segment UUID
   ranges.log      one payload: the 44 bytes of the entry (root segment, offset, label, epoch,
                   range count) and the 32 bytes of each range (segment, start, end), all
                   little-endian u64 except the u32 count (CC16: the entry decoders are Phase D,
                   so the layout is rebuilt here from the manifest and compared byte for byte)
   invalid log-*   signal the manifest's error, with the listed kind"
Import from: 'protobase'.
Import from: '_vectors'.
| manifest cluster failures scan entry expected w classes |
manifest := Vectors manifest.
cluster := manifest at: 'cluster'.
failures := OrderedCollection new.

"roots-torn.log"
entry := cluster at: 'roots_log_torn'.
scan := PBFramedLog scan: (Vectors bytesOf: (entry at: 'file')) kind: (entry at: 'kind') path: (entry at: 'file').
(scan payloads size = (entry at: 'entries') and: [scan validEnd = (entry at: 'valid_end') and: [scan isTorn]])
  ifFalse: [failures add: 'roots-torn.log: ' , scan payloads size printString , ' payloads, validEnd ' , scan validEnd printString].

"roots.log, whole: not torn, ends at its size"
entry := cluster at: 'roots_log'.
scan := PBFramedLog scan: (Vectors bytesOf: (entry at: 'file')) kind: (entry at: 'kind') path: (entry at: 'file').
(scan isTorn not and: [scan payloads size = (entry at: 'entries') size and: [scan validEnd = (Vectors bytesOf: (entry at: 'file')) size]])
  ifFalse: [failures add: 'roots.log is not a whole log of the listed entries'].

"segments.log"
entry := cluster at: 'segments_log'.
scan := PBFramedLog scan: (Vectors bytesOf: (entry at: 'file')) kind: (entry at: 'kind') path: (entry at: 'file').
((scan payloads asArray = ((entry at: 'entries') collect: [:hex | ByteArray fromHex: hex])) and: [scan isTorn not])
  ifFalse: [failures add: 'segments.log payloads differ from the listed UUIDs'].

"ranges.log"
entry := cluster at: 'ranges_log'.
scan := PBFramedLog scan: (Vectors bytesOf: (entry at: 'file')) kind: (entry at: 'kind') path: (entry at: 'file').
expected := (entry at: 'entries') collect: [:e |
  | root |
  root := e at: 'root'.
  w := WriteStream on: ByteArray new.
  w nextPutAll: (ByteArray fromHex: (root at: 'segment')).
  w nextPutUnsigned: (root at: 'offset') width: 8 bigEndian: false.
  w nextPutUnsigned: (e at: 'label') width: 8 bigEndian: false.
  w nextPutUnsigned: (root at: 'epoch') width: 8 bigEndian: false.
  w nextPutUnsigned: (e at: 'ranges') size width: 4 bigEndian: false.
  (e at: 'ranges') do: [:r |
    w nextPutAll: (ByteArray fromHex: (r at: 1)).
    w nextPutUnsigned: (r at: 2) width: 8 bigEndian: false.
    w nextPutUnsigned: (r at: 3) width: 8 bigEndian: false].
  w contents].
((scan payloads asArray = expected asArray) and: [scan isTorn not])
  ifFalse: [failures add: 'ranges.log payloads differ from the bytes built from the manifest'].

"invalid vectors of layer log"
classes := Dictionary new.
classes at: 'corruption' put: PBCorruptionError; at: 'not_supported' put: PBNotSupportedError.
((manifest at: 'invalid') select: [:e | (e at: 'layer') = 'log']) do: [:e |
  | outcome cls |
  cls := classes at: (e at: 'error').
  outcome := [PBFramedLog scan: (Vectors bytesOf: (e at: 'file')) kind: (e at: 'kind') path: (e at: 'file'). nil]
    on: PBDBError do: [:x | (x isKindOf: cls) ifTrue: [#refused] ifFalse: [x class name , ': ' , x messageText]].
  outcome == #refused ifFalse: [failures add: (e at: 'id') , ': ' , outcome printString]].
failures isEmpty ifFalse: [failures do: [:f | ('FAIL ' , f) displayNl]. Smalltalk exit: 1].
'framed logs ok'

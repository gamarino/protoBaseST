"EXPECT: messages ok 24"
"The message frames of the cluster section (README, 'Using the vectors', 8) and the invalid
 vectors of layer 'message', read with PBClusterMessage:
   messages/*.frame  one frame of each of the 22 types, unknown-root (a commit_query whose
                     root is nil) and fetched-unknown (a fetched carrying the optional unknown,
                     protocol 14): all at v 14; the 4-byte big-endian length equals the body's
                     size; the body decodes (decode:) to the listed type and sender, and each
                     field of the type, and each optional field the manifest lists, describes
                     (PBNotation describeRaw:) as the manifest's typed value; a root,
                     ranges or after field read into its value (rootFrom:, rangesFrom:,
                     afterFrom:) and written back (rootValue:, rangesValue:) describes the same;
                     encode gives the body byte for byte
   invalid message-* each body (after its 4-byte length) is refused with
                     PBClusterProtocolError, except message-oversized: a length over 64 MiB is
                     the frame layer's refusal (PBClusterFrame), verified by cluster.st"
Import from: 'protobase'.
Import from: '_vectors'.
| manifest cluster failures passed body schema typed invalid optional |
manifest := Vectors manifest.
cluster := manifest at: 'cluster'.
failures := OrderedCollection new.
schema := PBClusterMessage schema.
"proto_db OPTIONAL_FIELDS at v2.0.0rc4."
optional := Dictionary new.
optional at: 'fetched' put: #('unknown'); at: 'commit_info' put: #('unknown').
passed := 0.

"The body of a frame: the bytes after its 4-byte big-endian length, which must be their size."
body := [:id :bytes |
  ((bytes size >= 4) and: [(bytes unsignedLongAt: 1 bigEndian: true) = (bytes size - 4)]) ifFalse: [
    failures add: id , ': the length prefix is not the size of the body'].
  bytes copyFrom: 5 to: bytes size].

"The wire value of a field read into its value and written back (the kinds with a reader)."
typed := Dictionary new.
typed at: #root put: [:v | PBClusterMessage rootValue: (PBClusterMessage rootFrom: v)];
  at: #ranges put: [:v | PBClusterMessage rangesValue: (PBClusterMessage rangesFrom: v)];
  at: #after put: [:v | PBClusterMessage afterFrom: v].

(cluster at: 'messages') size = 24 ifFalse: [failures add: 'the manifest lists ' , (cluster at: 'messages') size printString , ' frames, not 24'].
(cluster at: 'messages') do: [:entry |
  | id frame message listed problems |
  id := entry at: 'id'.
  problems := failures size.
  frame := body value: id value: (Vectors bytesOf: (entry at: 'file')).
  listed := Dictionary new.
  ((entry at: 'message') at: 'mpmap') do: [:pair | listed at: ((pair at: 1) at: 'str') put: (pair at: 2)].
  message := [PBClusterMessage decode: frame] on: PBDBError do: [:e | failures add: id , ': ' , e class name , ' ' , e messageText. nil].
  message isNil ifFalse: [
    (message type = (entry at: 'type') and: [message type = ((listed at: 'type') at: 'str')
        and: [message from = ((listed at: 'from') at: 'str') and: [((listed at: 'v') at: 'int') = PBClusterMessage protocolVersion printString]]])
      ifFalse: [failures add: id , ': type ' , message type printString , ' from ' , message from printString].
    (schema at: message type) do: [:field |
      | value expected |
      value := message at: field key.
      expected := listed at: field key ifAbsent: [nil].
      (PBNotation describeRaw: value) = expected ifFalse: [
        failures add: id , ': field ' , field key , ' is ' , (PBNotation describeRaw: value) printString , ', the manifest says ' , expected printString].
      (typed includesKey: field value) ifTrue: [
        | back |
        back := (typed at: field value) value: value.
        (PBNotation describeRaw: back) = expected ifFalse: [
          failures add: id , ': field ' , field key , ' read and written back is ' , (PBNotation describeRaw: back) printString]]].
    (optional at: message type ifAbsent: [#()]) do: [:name |
      (listed includesKey: name) = (message includesField: name) ifFalse: [
        failures add: id , ': the optional field ' , name , ' is carried: ' , (message includesField: name) printString].
      ((listed includesKey: name) and: [(PBNotation describeRaw: (message at: name)) ~= (listed at: name)]) ifTrue: [
        failures add: id , ': the optional field ' , name , ' is ' , (PBNotation describeRaw: (message at: name)) printString]].
    listed keys size = ((schema at: message type) size + 3
        + ((optional at: message type ifAbsent: [#()]) count: [:name | listed includesKey: name])) ifFalse: [
      failures add: id , ': the manifest lists other fields than the table'].
    message encode = frame ifFalse: [failures add: id , ': encode differs from the frame body']].
  failures size = problems ifTrue: [passed := passed + 1]].

"invalid vectors of layer message"
invalid := (manifest at: 'invalid') select: [:e | (e at: 'layer') = 'message'].
invalid size = 6 ifFalse: [failures add: 'the manifest lists ' , invalid size printString , ' invalid message vectors, not 6'].
(invalid reject: [:e | (e at: 'id') = 'message-oversized']) do: [:e |
  | outcome |
  (e at: 'error') = 'protocol' ifFalse: [failures add: (e at: 'id') , ': the listed error is ' , (e at: 'error')].
  outcome := [PBClusterMessage decode: (body value: (e at: 'id') value: (Vectors bytesOf: (e at: 'file'))). 'accepted']
    on: PBDBError do: [:x | (x isKindOf: PBClusterProtocolError) ifTrue: [nil] ifFalse: [x class name , ': ' , x messageText]].
  outcome isNil ifFalse: [failures add: (e at: 'id') , ': ' , outcome]].
failures isEmpty ifFalse: [failures do: [:f | ('FAIL ' , f) displayNl]. Smalltalk exit: 1].
'messages ok ' , passed printString

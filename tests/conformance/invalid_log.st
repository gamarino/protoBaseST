"EXPECT: invalid log-layer 3/3"
"Every invalid vector of the layer 'log' (README, 'Using the vectors', 3: a framed log of
 the entry's kind) is refused by the framed-log reader, PBFramedLog payloadsOf:kind:
 (ProtoBase proto_db/storage/logfile.py read_log), with the listed class (corruption:
 PBCorruptionError, not_supported: PBNotSupportedError): a log of another format version, a
 log of another kind, and a damaged frame followed by a valid one (mid-log corruption,
 never a torn tail). A refusal with another class is a FAIL, and so is a file that is
 accepted. N is the manifest's count of entries of the layer."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest entries run classes refused |
manifest := Vectors manifest.
entries := (manifest at: 'invalid') select: [:e | (e at: 'layer') = 'log'].
refused := Object new.  "a private marker (a Symbol is a String in protoST, D35)"
classes := Dictionary new.
classes at: 'corruption' put: PBCorruptionError; at: 'not_supported' put: PBNotSupportedError.
run := VectorRun section: 'invalid' ids: (entries collect: [:e | e at: 'id'])
  among: ((manifest at: 'invalid') collect: [:e | e at: 'id']).
entries do: [:entry |
  | id expectedClass |
  id := entry at: 'id'.
  expectedClass := classes at: (entry at: 'error') ifAbsent: [nil].
  run begin.
  run vector: id stage: 'refusal' do: [
    | outcome |
    expectedClass isNil ifTrue: [PBValidationError signal: 'the manifest lists the unknown error ' , (entry at: 'error') printString].
    outcome := [PBFramedLog payloadsOf: (Vectors bytesOf: (entry at: 'file')) kind: (entry at: 'kind'). nil]
      on: PBDBError do: [:e |
        (e isKindOf: expectedClass) ifTrue: [refused] ifFalse: [e class name , ': ' , e messageText]].
    outcome isNil
      ifTrue: [{ 'accepted'. 'accepted, but ' , (entry at: 'error') , ' was expected' }]
      ifFalse: [outcome == refused ifTrue: [nil] ifFalse: [{ 'refusal'. 'refused with ' , outcome , ', not ' , expectedClass name }]]].
  run end: id].
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' vector(s)') displayNl]
  ifFalse: [(run summaryAs: 'invalid log-layer') displayNl]

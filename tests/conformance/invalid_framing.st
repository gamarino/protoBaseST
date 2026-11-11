"EXPECT: invalid framing-layers 7/7"
"Every invalid vector of the layers 'record', 'segment' and 'root' (README, 'Using
 the vectors', 3) is refused with the listed class (corruption: PBCorruptionError,
 not_supported: PBNotSupportedError):
   record   PBRecordHeader decode: of the file, then the payload that follows the
            header (payloadOfRecord:), so a payload CRC mismatch is seen
   segment  PBSegmentHeader decode: of the file
   root     PBRootRecord decode: of the file
 A refusal with another class is a FAIL, and so is a file that is accepted. N is
 the manifest's count of entries of the three layers."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest layers entries run classes readers |
manifest := Vectors manifest.
layers := #('record' 'segment' 'root').
entries := (manifest at: 'invalid') select: [:e | layers includes: (e at: 'layer')].
classes := Dictionary new.
classes at: 'corruption' put: PBCorruptionError; at: 'not_supported' put: PBNotSupportedError.
readers := Dictionary new.
readers
  at: 'record' put: [:bytes | (PBRecordHeader decode: bytes) payloadOfRecord: bytes];
  at: 'segment' put: [:bytes | PBSegmentHeader decode: bytes];
  at: 'root' put: [:bytes | PBRootRecord decode: bytes].
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
    outcome := [(readers at: (entry at: 'layer')) value: (Vectors bytesOf: (entry at: 'file')). nil]
      on: PBDBError do: [:e |
        (e isKindOf: expectedClass) ifTrue: [#refused] ifFalse: [e class name , ': ' , e messageText]].
    outcome isNil
      ifTrue: [{ 'accepted'. 'accepted, but ' , (entry at: 'error') , ' was expected' }]
      ifFalse: [outcome == #refused ifTrue: [nil] ifFalse: [{ 'refusal'. 'refused with ' , outcome , ', not ' , expectedClass name }]]].
  run end: id].
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' vector(s)') displayNl]
  ifFalse: [(run summaryAs: 'invalid framing-layers') displayNl]

"EXPECT: invalid value-layer 35/36 expected 1"
"Every invalid vector of layer 'value' (value and map-key vectors): PBCodec decode: refuses
 the file with the listed class (corruption: PBCorruptionError, not_supported:
 PBNotSupportedError). A refusal with another class is a FAIL, and so is a file that is
 accepted, unless it is a listed expected difference (_expected_differences.st), which must
 be accepted. N is the count of layer = 'value' entries of the manifest."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest entries run classes |
manifest := Vectors manifest.
entries := (manifest at: 'invalid') select: [:e | (e at: 'layer') = 'value'].
classes := Dictionary new.
classes at: 'corruption' put: PBCorruptionError; at: 'not_supported' put: PBNotSupportedError.
"The expected differences name ids of the whole invalid section, not only of this layer."
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
    outcome := [PBCodec decode: (Vectors bytesOf: (entry at: 'file')). nil]
      on: PBDBError do: [:e |
        (e isKindOf: expectedClass) ifTrue: [#refused] ifFalse: [e class name , ': ' , e messageText]].
    outcome isNil
      ifTrue: [{ 'accepted'. 'accepted, but ' , (entry at: 'error') , ' was expected' }]
      ifFalse: [outcome == #refused ifTrue: [nil] ifFalse: [{ 'refusal'. 'refused with ' , outcome , ', not ' , expectedClass name }]]].
  run end: id].
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' vector(s)') displayNl]
  ifFalse: [(run summaryAs: 'invalid value-layer') displayNl]

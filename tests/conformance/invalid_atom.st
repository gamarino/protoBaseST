"EXPECT: invalid atom-layer 0/9 expected 9"
"Every invalid vector of the layer 'atom' (README, 'Using the vectors', 3): an
 atom record payload, loaded as a reference to the entry's type. The payloads are
 written as ATOM records into one segment of a temporary space; each is then
 loaded the way a reference loads it: PBTypeRegistry unloadedAtomFor: type at:
 pointer storage: (what PBFileStorage refTo:offset:tag: answers), then its state.
 The load must be refused with the listed class (corruption: PBCorruptionError).
 A refusal with another class is a FAIL, and so is a payload that is accepted,
 unless it is a listed expected difference (_expected_differences.st).
 Until Task 12 the built-in types have no class, so every entry is refused with
 PBNotSupportedError and is listed as an expected difference that Task 12 removes
 (plan Task 11: this runner passes at the end of Task 12)."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest entries run classes base seg w pointers storage |
manifest := Vectors manifest.
entries := (manifest at: 'invalid') select: [:e | (e at: 'layer') = 'atom'].
classes := Dictionary new.
classes at: 'corruption' put: PBCorruptionError; at: 'not_supported' put: PBNotSupportedError.
base := FileSystem temp / ('pbst-invalid-atom-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
seg := ByteArray fromHex: '5eed00000000400080000000000a7011'.
w := WriteStream on: ByteArray new.
w nextPutAll: (PBSegmentHeader encodeSegment: seg).
pointers := Dictionary new.
entries do: [:entry |
  pointers at: (entry at: 'id') put: (PBAtomPointer segment: seg offset: w contents size).
  w nextPutAll: (PBRecordHeader encodeKind: 1 payload: (Vectors bytesOf: (entry at: 'file')))].
(base / (seg hex asLowercase , '.seg')) binaryContents: w contents.
storage := PBFileStorage path: base.
run := VectorRun section: 'invalid' ids: (entries collect: [:e | e at: 'id'])
  among: ((manifest at: 'invalid') collect: [:e | e at: 'id']).
entries do: [:entry |
  | id expectedClass |
  id := entry at: 'id'.
  expectedClass := classes at: (entry at: 'error') ifAbsent: [nil].
  run begin.
  "A refusal of another PBDBError class leaves the block, so the run records the class."
  run vector: id stage: 'refusal' do: [
    | outcome |
    expectedClass isNil ifTrue: [PBValidationError signal: 'the manifest lists the unknown error ' , (entry at: 'error') printString].
    outcome := [(PBTypeRegistry unloadedAtomFor: (entry at: 'type') at: (pointers at: id) storage: storage) state. nil]
      on: expectedClass do: [:e | #refused].
    outcome isNil
      ifTrue: [{ 'accepted'. 'accepted, but ' , (entry at: 'error') , ' was expected' }]
      ifFalse: [nil]].
  run end: id].
storage close.
base deleteAll.
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' vector(s)') displayNl]
  ifFalse: [(run summaryAs: 'invalid atom-layer') displayNl]

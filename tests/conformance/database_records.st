"EXPECT: database records 126/127 expected 1"
"The record walk of the database section (README, 'Using the vectors', 7, first
 part): the space opens with PBFileStorage (its space.root is the manifest's
 root), and the segment, walked from offset 26 (recordsOfSegment:), holds
 exactly the listed records, in order, with nothing after the last one. Each
 record at its offset has the listed kind and size (header plus payload); its
 envelope (PBAtomEnvelope decode:expecting: the listed type, references left
 unresolved) has the listed tag, type, oid and state (attributes in the written
 order, described with describe:); and when canonical is true it re-encodes to
 the same record bytes. Reading the space as a database (contents) is Task 12.
 The segment and space.root are checked against vectors.sha256 before anything
 is read (Vectors manifest)."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest section records storage walk byOffset run mismatch segmentHex rootFields root segmentBytes |
manifest := Vectors manifest.
section := manifest at: 'database'.
records := section at: 'records'.
segmentHex := (section at: 'segment') copyReplaceAll: '.seg' with: ''.
run := VectorRun section: 'database' ids: (records collect: [:r | (r at: 'offset') printString]).
mismatch := [:what :actual :expected |
  actual = expected ifTrue: [nil] ifFalse: [
    what , ' is ' , actual printString , ', the manifest says ' , expected printString]].
segmentBytes := Vectors bytesOf: (section at: 'dir') , '/' , (section at: 'segment').
storage := PBFileStorage path: 'vectors/' , (section at: 'dir').
root := storage readRoot.
rootFields := section at: 'root'.
(root notNil and: [root version = (rootFields at: 'version') and: [root segmentHex = (rootFields at: 'segment')
    and: [root offset = (rootFields at: 'offset') and: [root epoch = (rootFields at: 'epoch')]]]])
  ifFalse: [('FAIL root: ' , root printString , ' is not the manifest root ' , rootFields printString) displayNl.
    Smalltalk exit: 1].
walk := storage recordsOfSegment: segmentHex.
byOffset := Dictionary new.
walk do: [:r | byOffset at: (r at: 1) put: r].
(walk collect: [:r | r at: 1]) = (records collect: [:r | r at: 'offset']) ifFalse: [
  ('FAIL walk: the segment holds the records at ' , (walk collect: [:r | r at: 1]) printString
    , ', the manifest lists ' , (records collect: [:r | r at: 'offset']) printString) displayNl.
  Smalltalk exit: 1].
records do: [:entry |
  | id record header payload envelope |
  id := (entry at: 'offset') printString.
  record := byOffset at: (entry at: 'offset') ifAbsent: [nil].
  run begin.
  run stage: 'decode' of: id do: [
    header := record at: 2.
    payload := record at: 3.
    envelope := PBAtomEnvelope decode: payload expecting: (entry at: 'type').
    (mismatch value: 'the kind' value: header kind value: (entry at: 'kind'))
      ifNil: [(mismatch value: 'the size' value: 15 + header length value: (entry at: 'size'))
        ifNil: [(mismatch value: 'the tag' value: envelope tag value: (entry at: 'tag'))
          ifNil: [(mismatch value: 'the type' value: (PBTypeRegistry nameOfTag: envelope tag) value: (entry at: 'type'))
            ifNil: [(mismatch value: 'the oid' value: envelope oid hex asLowercase value: (entry at: 'oid'))
              ifNil: [mismatch value: 'the state'
                value: (envelope state associations collect: [:each | { each key. PBNotation describe: each value }])
                value: (entry at: 'state')]]]]]].
  ((entry at: 'canonical') == true and: [envelope notNil]) ifTrue: [
    run stage: 'encode' of: id do: [
      mismatch value: 'the re-encoded record'
        value: (PBRecordHeader encodeKind: header kind payload: envelope encode) hex
        value: (segmentBytes copyFrom: (entry at: 'offset') + 1 to: (entry at: 'offset') + (entry at: 'size')) hex]].
  run end: id].
storage close.
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' vector(s)') displayNl]
  ifFalse: [(run summaryAs: 'database records') displayNl]

"EXPECT: framing 10/10"
"The framing section of the manifest (README, 'Using the vectors', 6): each
 header, record and root decodes to the listed fields and re-encodes to the
 same bytes.
   segment_header*   PBSegmentHeader decode: gives the version and segment; the
                     version-4 header re-encodes (encodeSegment:), the format-3 and
                     format-2 ones are decoded only (writers write 4)
   atom_record       PBRecordHeader decode: gives kind 1; the payload describes
                     (describeRaw:) as the listed payload; the record re-encodes
                     (encodeKind:payload:), and so does its envelope
                     (PBAtomEnvelope decode:expecting: then encode)
   blob_record       kind 2 and the listed payload bytes; the record re-encodes
   root*             PBRootRecord decode: gives the listed fields; the version-4
                     root re-encodes, the format-3 and format-2 ones are decoded only
   cloud_root, tiered_root   only their file-storage fields are checked: the file
                     decoder ignores the extra keys (recent, term), each storage
                     validates its own (format spec, Root records)
 Every id of the section is run, and an id the runner does not know is a FAIL."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest framing run known mismatch checkRoot checkHeader |
manifest := Vectors manifest.
framing := manifest at: 'framing'.
known := #('segment_header' 'segment_header_v3' 'segment_header_v2' 'atom_record' 'blob_record'
  'root' 'root_v2' 'root_v3' 'cloud_root' 'tiered_root').
run := VectorRun section: 'framing' ids: framing keys asArray.
mismatch := [:what :actual :expected |
  actual = expected ifTrue: [nil] ifFalse: [
    what , ' is ' , actual printString , ', the manifest says ' , expected printString]].
checkHeader := [:id :entry |
  | bytes header |
  bytes := Vectors bytesOf: (entry at: 'file').
  run stage: 'decode' of: id do: [
    header := PBSegmentHeader decode: bytes.
    (mismatch value: 'the version' value: header version value: (entry at: 'version'))
      ifNil: [mismatch value: 'the segment' value: header segmentHex value: (entry at: 'segment')]].
  header version = 4 ifTrue: [
    run stage: 'encode' of: id do: [
      mismatch value: 'the re-encoded header' value: (PBSegmentHeader encodeSegment: header segment) hex
        value: bytes hex]]].
checkRoot := [:id :entry :reencode |
  | bytes root fields |
  bytes := Vectors bytesOf: (entry at: 'file').
  fields := entry at: 'fields'.
  run stage: 'decode' of: id do: [
    root := PBRootRecord decode: bytes.
    (mismatch value: 'the version' value: root version value: (fields at: 'version'))
      ifNil: [(mismatch value: 'the segment' value: root segmentHex value: (fields at: 'segment'))
        ifNil: [(mismatch value: 'the offset' value: root offset value: (fields at: 'offset'))
          ifNil: [mismatch value: 'the epoch' value: root epoch value: (fields at: 'epoch')]]]].
  reencode ifTrue: [
    run stage: 'encode' of: id do: [
      mismatch value: 'the re-encoded root' value: root encode hex value: bytes hex]]].
framing keys asArray do: [:id |
  | entry |
  entry := framing at: id.
  run begin.
  (known includes: id) ifFalse: [
    run stage: 'decode' of: id do: ['an entry this runner does not know']].
  (id beginsWith: 'segment_header') ifTrue: [checkHeader value: id value: entry].
  id = 'root' ifTrue: [checkRoot value: id value: entry value: true].
  (#('root_v2' 'root_v3' 'cloud_root' 'tiered_root') includes: id) ifTrue: [
    checkRoot value: id value: entry value: false].
  (id = 'atom_record' or: [id = 'blob_record']) ifTrue: [
    | bytes header payload |
    bytes := Vectors bytesOf: (entry at: 'file').
    run stage: 'decode' of: id do: [
      header := PBRecordHeader decode: bytes.
      payload := header payloadOfRecord: bytes.
      (mismatch value: 'the kind' value: header kind value: (entry at: 'kind'))
        ifNil: [(mismatch value: 'the record size' value: bytes size value: 15 + header length)
          ifNil: [id = 'atom_record'
            ifTrue: [mismatch value: 'the payload' value: (PBNotation describeRaw: (MessagePack decodeOrdered: payload strictKeys: false))
              value: (entry at: 'payload')]
            ifFalse: [mismatch value: 'the payload' value: payload hex value: (entry at: 'payload_hex')]]]].
    run stage: 'encode' of: id do: [
      mismatch value: 'the re-encoded record' value: (PBRecordHeader encodeKind: header kind payload: payload) hex
        value: bytes hex].
    id = 'atom_record' ifTrue: [
      run stage: 'envelope' of: id do: [
        | envelope |
        envelope := PBAtomEnvelope decode: payload expecting: 'proto_db.core.dbobject.DBObject'.
        mismatch value: 'the re-encoded envelope' value: envelope encode hex value: payload hex]]].
  run end: id].
(framing includesKey: 'cloud_root') | (framing includesKey: 'tiered_root') ifTrue: [
  'NOTE: cloud/tiered extra keys ignored' displayNl].
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' vector(s)') displayNl]
  ifFalse: [(run summaryAs: 'framing') displayNl]

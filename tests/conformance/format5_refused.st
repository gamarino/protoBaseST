"EXPECT: format5 0/3 expected 3, root refused 2/2, version-5 records refused 28/28, version-4 records read 33/33"
"The format-5 vectors of proto_db 2.0.0rc4 (format spec, 'Format stability', R151, R242):
 protoBaseST reads formats 2 to 4 and log format 2, and refuses format 5 with
 PBNotSupportedError, never misreading it (docs/deviations.md, 'Reading').
   format5           section 'format5' of _expected_differences.st: parents_database and
                     registry_database (opened with PBFileStorage path: and PBObjectSpace
                     storage:, then every database listed) and cluster.roots_log_v5 (an
                     acceptor log of log format 3, read with PBFramedLog then
                     PBAcceptorLog) each fail their stage open with exactly
                     PBNotSupportedError, until the runtime-registry plan (D62) reads them
   root refused      each space.root of the two databases (version 5) is refused by
                     PBRootRecord decode: with PBNotSupportedError
   records refused   the F4 check (rc4 delta, risk 4): on a copy of the segments with no
                     space.root, every record of a version-5 segment is refused by
                     PBFileStorage loadAt:expecting: with PBNotSupportedError, from its
                     segment header, before any record is decoded: a four-key envelope
                     (key p, feature parents) never reaches PBAtomEnvelope decode:, which
                     would call it corruption
   records read      every record of a version-4 segment of the same databases still loads
                     (loadAt:expecting: answers its envelope), so the refusal is the
                     segment's version and nothing else
 The counts are the manifest's: 2 databases with a version-4 and a version-5 segment each."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest run databases log refusedRoots refused read v5 v4 failures |
manifest := Vectors manifest.
failures := OrderedCollection new.
databases := #('parents_database' 'registry_database').
run := VectorRun section: 'format5' ids: (databases copyWith: 'roots_log_v5').

databases do: [:name |
  run begin.
  run stage: 'open' of: name do: [
    | dir storage space |
    dir := Vectors copySpace: name.
    [storage := PBFileStorage path: dir pathString.
     space := PBObjectSpace storage: storage.
     space listDatabases do: [:db | space openDatabase: db].
     'opened: reading a format-5 space is not implemented, so its contents are not compared']
      ensure: [space isNil ifFalse: [space close] ifTrue: [storage isNil ifFalse: [storage close]]. dir deleteAll]].
  run end: name].

log := (manifest at: 'cluster') at: 'roots_log_v5'.
run begin.
run stage: 'open' of: 'roots_log_v5' do: [
  PBAcceptorLog decode: (PBFramedLog scan: (Vectors bytesOf: (log at: 'file')) kind: (log at: 'kind') path: (log at: 'file')) payloads
    path: (log at: 'file').
  'decoded: reading log format 3 is not implemented, so its entries are not compared'].
run end: 'roots_log_v5'.

"The root records of version 5."
refusedRoots := 0.
databases do: [:name |
  | outcome |
  outcome := [PBRootRecord decode: (Vectors bytesOf: ((manifest at: name) at: 'dir') , '/space.root'). 'accepted']
    on: PBDBError do: [:e | (e isKindOf: PBNotSupportedError) ifTrue: [nil] ifFalse: [e class name , ': ' , e messageText]].
  outcome isNil
    ifTrue: [refusedRoots := refusedRoots + 1]
    ifFalse: [failures add: name , ' space.root: ' , outcome]].

"The F4 check, and the version-4 records beside it."
refused := 0. read := 0. v5 := 0. v4 := 0.
databases do: [:name |
  | dir storage |
  dir := Vectors copySegments: name.
  storage := PBFileStorage path: dir pathString.
  [(Vectors segmentsOf: name) do: [:segment |
    | bytes |
    bytes := ByteArray fromHex: ((segment at: 'segment') copyFrom: 1 to: 32).
    (segment at: 'records') do: [:record |
      | pointer outcome |
      pointer := PBAtomPointer segment: bytes offset: (record at: 'offset').
      outcome := [storage loadAt: pointer expecting: (record at: 'tag'). #loaded]
        on: PBDBError do: [:e | (e isKindOf: PBNotSupportedError) ifTrue: [#refused] ifFalse: [e class name , ': ' , e messageText]].
      (segment at: 'format') = 5
        ifTrue: [
          v5 := v5 + 1.
          outcome == #refused
            ifTrue: [refused := refused + 1]
            ifFalse: [failures add: name , ' ' , (segment at: 'segment') , ':' , (record at: 'offset') printString
              , ' (version 5): ' , outcome printString , ', not PBNotSupportedError']]
        ifFalse: [
          v4 := v4 + 1.
          outcome == #loaded
            ifTrue: [read := read + 1]
            ifFalse: [failures add: name , ' ' , (segment at: 'segment') , ':' , (record at: 'offset') printString
              , ' (version 4): ' , outcome printString]]]]]
    ensure: [storage close. dir deleteAll]].

failures do: [:f | ('FAIL ' , f) displayNl].
(run failures = 0 and: [failures isEmpty]) ifFalse: [Smalltalk exit: 1].
(run summaryAs: 'format5') , ', root refused ' , refusedRoots printString , '/' , databases size printString
  , ', version-5 records refused ' , refused printString , '/' , v5 printString
  , ', version-4 records read ' , read printString , '/' , v4 printString

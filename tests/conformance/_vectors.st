"_vectors.st: the vendored conformance vectors and the runner's bookkeeping (a helper).

  Vectors manifest            loads manifest.json after checking the vectors
  Vectors bytesOf: aPath      the bytes of a vector file (path relative to vectors/)
  VectorRun section: s ids: a one run over a manifest section, with its expected
                              differences (_expected_differences.st)

Vectors checks, before anything is read: the SHA-256 of vectors.sha256 is the
digest pinned in the format spec (and in fetch_vectors.sh), every file the
list names has the listed SHA-256 (manifest.json included, as ../manifest.json),
the manifest's built-in alias list is the table of PBTypeRegistry, and every
file the manifest names is listed: a 'file' or 'canonical' path, and the
segments and space.root of each database-type section ('dir' with 'segment', or,
since proto_db 2.0.0rc4, with 'segments', a list of { segment. format. records }). A mismatch
signals Error: a vector is never edited, so no run goes on over a changed one.
The listing is not walked for unlisted files: fetch_vectors.sh checks that at
vendoring time.

It also imports _model.st, which defines and registers ConformanceInvoice, the
application type of the vectors (conformance.Invoice), as every implementation
that reads them must.

  Vectors copySpace: aSection  a copy of the space of a database-type section
                              (its segments and space.root, verified first) in a
                              fresh temporary directory, answered as a FileReference:
                              runners open copies, never the vendored files
  Vectors copySegments: aSection  the same copy without space.root (a space with
                              no root, whose segments a runner reads by pointer)
  Vectors segmentsOf: aSection  the section's segments as listed: an Array of
                              Dictionaries { segment. format. records } (a section
                              with one 'segment' answers it, with its records)"

Import from: 'protobase'.
Import from: '_expected_differences'.
Import from: '_model'.

Object subclass: #Vectors classVariableNames: 'Manifest JSONModule'.

Vectors class >> _setJSON: aModule
  JSONModule := aModule.

Vectors _setJSON: (Import from: 'json').

"The JSON class of protoST's json module (to print a mismatch)."
Vectors class >> json
  ^ JSONModule JSON.

Vectors class >> pinnedDigest
  ^ '37b286fd97df098769aee26c222f76d295bf747b1a02f9441e52bd54e1ca1695'.

Vectors class >> bytesOf: aPath
  ^ ('vectors/' , aPath) asFileReference binaryContents.

"The space of the manifest section aSection ('database', 'legacy_database',
 'polyglot_database', 'parents_database', 'registry_database'), copied into
 FileSystem temp / pbst-copy-<pid>-<dir>, emptied first. The files are those the
 manifest names, checked by manifest."
Vectors class >> copySpace: aSection
  ^ self _copy: aSection root: true.

"As copySpace:, without space.root."
Vectors class >> copySegments: aSection
  ^ self _copy: aSection root: false.

Vectors class >> _copy: aSection root: aBoolean
  | section dir names |
  section := self manifest at: aSection.
  dir := FileSystem temp / ('pbst-copy-' , Smalltalk pid printString , '-' , (section at: 'dir')).
  dir deleteAll.
  dir ensureCreateDirectory.
  names := (self segmentsOf: aSection) collect: [:each | each at: 'segment'].
  aBoolean ifTrue: [names := names copyWith: 'space.root'].
  names do: [:name |
    (dir / name) binaryContents: (self bytesOf: (section at: 'dir') , '/' , name)].
  ^ dir.

"The segments of the database-type section aSection: its 'segments' list, or a one-item
 Array of { segment. records } for a section with one 'segment'."
Vectors class >> segmentsOf: aSection
  | section |
  section := self manifest at: aSection.
  (section includesKey: 'segments') ifTrue: [^ (section at: 'segments') asArray].
  ^ { Dictionary new at: 'segment' put: (section at: 'segment'); at: 'records' put: (section at: 'records' ifAbsent: [#()]); yourself }.

Vectors class >> manifest
  Manifest isNil ifTrue: [Manifest := self _load].
  ^ Manifest.

Vectors class >> _fail: aString
  ^ Error signal: 'Vectors: ' , aString.

Vectors class >> _load
  | listing manifest listed |
  listing := 'vectors.sha256' asFileReference binaryContents.
  listing sha256 hex asLowercase = self pinnedDigest ifFalse: [
    ^ self _fail: 'vectors.sha256 digest is ' , listing sha256 hex , ', not the pinned ' , self pinnedDigest].
  listed := Set new.
  (listing utf8Decoded lines select: [:line | line notEmpty]) do: [:line |
    | digest path actual |
    digest := line copyFrom: 1 to: 64.
    path := line copyFrom: 67 to: line size.
    listed add: path.
    actual := (path = '../manifest.json'
      ifTrue: ['manifest.json' asFileReference binaryContents]
      ifFalse: [self bytesOf: path]) sha256 hex asLowercase.
    actual = digest ifFalse: [^ self _fail: path , ' does not match vectors.sha256']].
  manifest := JSONModule JSON parse: 'manifest.json' asFileReference contents.
  (manifest at: 'builtin_type_aliases') asArray = PBTypeRegistry builtinNames asArray ifFalse: [
    ^ self _fail: 'builtin_type_aliases differ from the table of PBTypeRegistry'].
  (self _referencedFiles: manifest) do: [:path |
    (listed includes: path) ifFalse: [
      ^ self _fail: 'the manifest refers to ' , path , ', which vectors.sha256 does not list (it would be read unverified)']].
  ^ manifest.

"Every path the manifest names, relative to vectors/: the strings of the 'file' and
 'canonical' keys (in the cluster section 'canonical' is a flag), and, for each
 top-level section with a 'dir' and a 'segment' (database, legacy_database,
 polyglot_database), the files <dir>/<segment> and <dir>/space.root; with a 'dir' and
 'segments' (parents_database, registry_database: a non-empty list of Dictionaries,
 each with a string 'segment'), each <dir>/<segment> and <dir>/space.root. A section
 whose 'segment' is a Dictionary (cluster) is skipped here: its file is collected
 through its nested 'file' key. Any other section with a 'dir', a 'segment' or
 'segments' must have them in one of those forms, or the load fails."
Vectors class >> _referencedFiles: aNode
  | paths |
  paths := Set new.
  self _collectFiles: aNode into: paths.
  aNode associations do: [:section |
    | v |
    v := section value.
    ((v isKindOf: Dictionary) and: [(v includesKey: 'dir') or: [(v includesKey: 'segment') or: [v includesKey: 'segments']]]) ifTrue: [
      | dir segment segments |
      dir := v at: 'dir' ifAbsent: [nil].
      segment := v at: 'segment' ifAbsent: [nil].
      segments := v at: 'segments' ifAbsent: [nil].
      (segments isNil and: [segment isKindOf: Dictionary]) ifFalse: [
        segments isNil
          ifTrue: [
            (dir isString and: [segment isString]) ifFalse: [
              ^ self _fail: 'the section ' , section key , ' has no string dir and segment'].
            paths add: dir , '/' , segment]
          ifFalse: [
            (dir isString and: [segment isNil and: [(segments isKindOf: Array) and: [segments isString not
                and: [segments notEmpty and: [segments allSatisfy: [:each |
                  (each isKindOf: Dictionary) and: [(each at: 'segment' ifAbsent: [nil]) isString]]]]]]]) ifFalse: [
              ^ self _fail: 'the section ' , section key , ' has no string dir and list of segments'].
            segments do: [:each | paths add: dir , '/' , (each at: 'segment')]].
        paths add: dir , '/space.root']]].
  ^ paths.

Vectors class >> _collectFiles: aNode into: aSet
  (aNode isKindOf: Dictionary) ifTrue: [
    aNode associations do: [:each |
      ((each key = 'file' or: [each key = 'canonical']) and: [each value isString])
        ifTrue: [aSet add: each value].
      self _collectFiles: each value into: aSet]].
  ((aNode isKindOf: Array) and: [aNode isString not]) ifTrue: [
    aNode do: [:each | self _collectFiles: each into: aSet]].

"=== one run over a manifest section ==========================================="

Object subclass: #VectorRun instanceVariableNames: 'section expected failedStages hard passes expectedCount failures total'.

"anIdArray: the ids of the manifest section; a listed id that is missing is a FAIL."
VectorRun class >> section: aSection ids: anIdArray
  ^ self section: aSection ids: anIdArray among: anIdArray.

"A runner of one layer of a section: anIdArray are its ids, allIds those of the whole section
 (a listed id of another layer is that layer's runner's business)."
VectorRun class >> section: aSection ids: anIdArray among: allIds
  ^ self basicNew setSection: aSection ids: anIdArray among: allIds.

VectorRun >> setSection: aSection ids: anIdArray among: allIds
  section := aSection.
  expected := Dictionary new.
  failedStages := nil.
  passes := 0. expectedCount := 0. failures := 0. total := anIdArray size.
  (ExpectedDifferences forSection: aSection) do: [:entry |
    expected at: (entry at: 2) put: entry.
    ((anIdArray includes: (entry at: 2)) or: [allIds includes: (entry at: 2)]) ifFalse: [
      failures := failures + 1.
      ('FAIL ' , (entry at: 2) , ': listed as an expected difference but missing from the manifest section '
        , aSection) displayNl]].
  ^ self.

"Starts the checks of one vector."
VectorRun >> begin
  failedStages := OrderedCollection new.
  hard := false.

"Runs aBlock for the stage aStage of the current vector: it answers nil when the
 check holds, or the reason it does not (a mismatch: no error class). A PBDBError the
 block lets out is a failed stage with its class; any other Error is a defect of the
 implementation, never an expected difference."
VectorRun >> stage: aStage of: anId do: aBlock
  ^ self vector: anId stage: aStage do: [
    | why |
    why := aBlock value.
    why isNil ifTrue: [nil] ifFalse: [{ aStage. why }]].

"As stage:of:do:, for a block that names the failed stage itself: it answers nil or
 { stage. reason }. aStage names a stage that dies with an internal error."
VectorRun >> vector: anId stage: aStage do: aBlock
  | failed |
  failed := [aBlock value] on: Error do: [:e |
    (e isKindOf: PBDBError)
      ifTrue: [{ aStage. e messageText. e class name }]
      ifFalse: [hard := true. { aStage. 'INTERNAL ' , e class name , ': ' , e messageText printString }]].
  failed isNil ifFalse: [
    | why |
    why := failed at: 2.
    failedStages add: { failed at: 1. failed size > 2 ifTrue: [failed at: 3] ifFalse: [nil] }.
    (expected includesKey: anId) ifFalse: [
      ('FAIL ' , anId , ' (' , (failed at: 1) , '): '
        , (failed size > 2 ifTrue: [(failed at: 3) , ': '] ifFalse: ['']) , (why size > 300 ifTrue: [(why copyFrom: 1 to: 300) , '...'] ifFalse: [why]))
        displayNl]].

"Closes the vector: counts it as passed, as an expected difference, or as a failure."
VectorRun >> end: anId
  | entry |
  entry := expected at: anId ifAbsent: [nil].
  entry isNil ifTrue: [
    failedStages isEmpty ifTrue: [passes := passes + 1] ifFalse: [failures := failures + 1].
    ^ self].
  failedStages isEmpty ifTrue: [
    failures := failures + 1.
    ('FAIL ' , anId , ': listed as an expected difference (' , (entry at: 4) , ') but it now matches the manifest')
      displayNl.
    ^ self].
  (hard or: [failedStages asArray ~= (entry at: 3)]) ifTrue: [
    failures := failures + 1.
    ('FAIL ' , anId , ': the expected difference is (stage, error class) ' , (entry at: 3) printString
      , ', the vector fails ' , failedStages asArray printString , (hard ifTrue: [' with an internal error'] ifFalse: [''])) displayNl.
    ^ self].
  expectedCount := expectedCount + 1.
  ('EXPECTED ' , anId , ': ' , (entry at: 4) , ' [' , (entry at: 5) , ']') displayNl.

VectorRun >> failures
  ^ failures.

"'values 72/73 expected 1': passes over the vectors, then the expected ones
 ('framing 10/10' when there are none)."
VectorRun >> summaryAs: aLabel
  ^ aLabel , ' ' , passes printString , '/' , total printString
    , (expectedCount = 0 ifTrue: [''] ifFalse: [' expected ' , expectedCount printString]).

"_vectors.st: the vendored conformance vectors and the runner's bookkeeping (a helper).

  Vectors manifest            loads manifest.json after checking the vectors
  Vectors bytesOf: aPath      the bytes of a vector file (path relative to vectors/)
  VectorRun section: s ids: a one run over a manifest section, with its expected
                              differences (_expected_differences.st)

Vectors checks, before anything is read: the SHA-256 of vectors.sha256 is the
digest pinned in the format spec (and in fetch_vectors.sh), every file the
list names has the listed SHA-256 (manifest.json included, as ../manifest.json),
and the manifest's built-in alias list is the table of PBNotation. A mismatch
signals Error: a vector is never edited, so no run goes on over a changed one.
The listing is not walked for unlisted files: fetch_vectors.sh checks that at
vendoring time."

Import from: 'protobase'.
Import from: '_expected_differences'.

Object subclass: #Vectors classVariableNames: 'Manifest JSONModule'.

Vectors class >> _setJSON: aModule
  JSONModule := aModule.

Vectors _setJSON: (Import from: 'json').

Vectors class >> pinnedDigest
  ^ '5f86eb09ed1683aa9f048051c64cca68d23b9fb753e87416cb1ecf11ed406df0'.

Vectors class >> bytesOf: aPath
  ^ ('vectors/' , aPath) asFileReference binaryContents.

Vectors class >> manifest
  Manifest isNil ifTrue: [Manifest := self _load].
  ^ Manifest.

Vectors class >> _fail: aString
  ^ Error signal: 'Vectors: ' , aString.

Vectors class >> _load
  | listing manifest |
  listing := 'vectors.sha256' asFileReference binaryContents.
  listing sha256 hex asLowercase = self pinnedDigest ifFalse: [
    ^ self _fail: 'vectors.sha256 digest is ' , listing sha256 hex , ', not the pinned ' , self pinnedDigest].
  (listing utf8Decoded lines select: [:line | line notEmpty]) do: [:line |
    | digest path actual |
    digest := line copyFrom: 1 to: 64.
    path := line copyFrom: 67 to: line size.
    actual := (path = '../manifest.json'
      ifTrue: ['manifest.json' asFileReference binaryContents]
      ifFalse: [self bytesOf: path]) sha256 hex asLowercase.
    actual = digest ifFalse: [^ self _fail: path , ' does not match vectors.sha256']].
  manifest := JSONModule JSON parse: 'manifest.json' asFileReference contents.
  (manifest at: 'builtin_type_aliases') asArray = PBNotation builtinAliasNames asArray ifFalse: [
    ^ self _fail: 'builtin_type_aliases differ from the table of PBNotation'].
  ^ manifest.

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
 check holds, or the reason it does not. A PBDBError the block lets out is a
 failed stage; any other Error is a defect of the implementation, never an expected
 difference."
VectorRun >> stage: aStage of: anId do: aBlock
  | why |
  why := [aBlock value] on: Error do: [:e |
    (e isKindOf: PBDBError)
      ifTrue: [e class name , ': ' , e messageText]
      ifFalse: [hard := true. 'INTERNAL ' , e class name , ': ' , e messageText printString]].
  why isNil ifFalse: [
    failedStages add: aStage.
    (expected includesKey: anId) ifFalse: [
      ('FAIL ' , anId , ' (' , aStage , '): ' , (why size > 300 ifTrue: [(why copyFrom: 1 to: 300) , '...'] ifFalse: [why]))
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
    ('FAIL ' , anId , ': the expected difference is in the stages ' , (entry at: 3) printString
      , ', the vector fails ' , failedStages asArray printString , (hard ifTrue: [' with an internal error'] ifFalse: [''])) displayNl.
    ^ self].
  expectedCount := expectedCount + 1.
  ('EXPECTED ' , anId , ': ' , (entry at: 4) , ' [' , (entry at: 5) , ']') displayNl.

VectorRun >> failures
  ^ failures.

"'values 72/73 expected 1': passes over the vectors, then the expected ones."
VectorRun >> summaryAs: aLabel
  ^ aLabel , ' ' , passes printString , '/' , total printString , ' expected ' , expectedCount printString.

"_case_ops.st: protoST's side of the concurrency table, shared by tests/interop/_st_case.st and
 tests/unit/concurrency_actors.st (design spec 10.4, plan Task 21; a helper module, imported as
 '../tests/interop/_case_ops', which resolves against $STPATH = <repo>/src from any working
 directory). The cases, their steps and the dump notation are
 in concurrency_cases.json; py_case.py is the same interpreter in ProtoBase. The JSON and the
 database vector are found from the repository's root ($STPATH, see repo), not from the working
 directory.

  CaseTable load                    the cases (protoST Dictionaries parsed from the JSON)
  CaseTable case: anId              one case
  CaseTable recordedFor: aCase variant: aString
                                    the outcome and dump the JSON records for the variant
                                    ('st_as_a', 'py_as_a' or 'actors'): the case's
                                    'protobasest' entry, allowed only on the indexed-root case
                                    with PBNotSupportedError in its outcome, else the reference
  CaseTable databaseOf: aCase       'db' for a case on the database vector, 'cc' otherwise
  CaseTable setup: aCase in: aDir   creates the case's space in protoST (the vector is copied)
  CaseTable dump: aCase in: aDb     the dump lines (an Array of Strings), read in a new
                                    transaction
  CaseSide new start: steps in: aDb runs the steps that come before the transaction ('reuse
                                    committed'), starts it and runs the steps; answers self
  aSide commit                      commits, unless a step failed; answers the outcome:
                                    'committed' or the class name of the PBDBError signalled

A CaseSide is also driven as an actor (concurrency_actors.st): start:in: and commit wait only on
the publisher's Futures, never on another side."
Import from: 'protobase'.

Object subclass: #CaseTable.

"The repository's root: the parent of the $STPATH directory that holds protobase.st (every
 run of protoBaseST sets STPATH to <repo>/src). The files below are found from it, whatever
 the working directory."
CaseTable class >> repo
  | stpath |
  stpath := (Smalltalk getenv: 'STPATH') ifNil: [''].
  (stpath subStrings: ':') do: [:each |
    (each asFileReference / 'protobase.st') exists ifTrue: [^ each asFileReference parent]].
  ^ Error signal: 'CaseTable: no directory of STPATH (' , stpath printString , ') holds protobase.st'.

CaseTable class >> path
  ^ self repo / 'tests' / 'interop' / 'concurrency_cases.json'.

CaseTable class >> vector
  ^ self repo / 'tests' / 'conformance' / 'vectors' / 'database'.

CaseTable class >> load
  ^ (((Import from: 'json') JSON parse: self path contents) at: 'cases').

CaseTable class >> case: anId
  ^ self load detect: [:each | (each at: 'id') = anId]
    ifNone: [Error signal: 'CaseTable: no case ' , anId printString].

"The ids that may record protoBaseST's documented refusal in place of ProtoBase's outcome
 (design spec 7.4)."
CaseTable class >> refusalIds
  ^ #('indexed-root').

CaseTable class >> recordedFor: aCase variant: aString
  | entry |
  (#('st_as_a' 'py_as_a' 'actors') includes: aString) ifFalse: [
    ^ Error signal: 'CaseTable: unknown variant ' , aString printString].
  (aCase includesKey: 'protobasest') ifFalse: [^ aCase at: 'expected'].
  (self refusalIds includes: (aCase at: 'id')) ifFalse: [
    ^ Error signal: 'CaseTable: only ' , self refusalIds printString , ' may record protoBaseST''s refusal, not '
      , (aCase at: 'id') printString].
  entry := (aCase at: 'protobasest') at: aString.
  ((entry at: 'outcome') includesSubstring: 'PBNotSupportedError') ifFalse: [
    ^ Error signal: 'CaseTable: the refusal recorded for ' , (aCase at: 'id') printString , ' ' , aString
      , ' is not PBNotSupportedError: ' , (entry at: 'outcome')].
  ^ entry.

CaseTable class >> usesVector: aCase
  ^ (aCase at: 'setup') anySatisfy: [:step | step first = 'vector database'].

CaseTable class >> databaseOf: aCase
  ^ (self usesVector: aCase) ifTrue: ['db'] ifFalse: ['cc'].

"A setup value: {'dict': {k: v}}, {'list': [v]}, {'set': [e]} or {'counted set': [e]} build a
 collection; any other value is itself."
CaseTable class >> setupValue: aValue
  | kind content result |
  (aValue isKindOf: Dictionary) ifFalse: [^ aValue].
  kind := aValue keys asArray first.
  content := aValue at: kind.
  kind = 'dict' ifTrue: [
    result := PBDictionary new.
    content keysAndValuesDo: [:k :v | result := result setAt: k value: v].
    ^ result].
  kind = 'list' ifTrue: [
    result := PBList new.
    content do: [:v | result := result appendLast: v].
    ^ result].
  kind = 'set' ifTrue: [
    result := PBSet new.
    content do: [:e | result := result add: e].
    ^ result].
  kind = 'counted set' ifTrue: [
    result := PBCountedSet new.
    content do: [:e | result := result add: e].
    ^ result].
  ^ Error signal: 'CaseTable: unknown setup value ' , aValue printString.

CaseTable class >> setup: aCase in: aDirectory
  | dir space |
  dir := aDirectory asFileReference.
  (self usesVector: aCase) ifTrue: [
    dir ensureCreateDirectory.
    self vector files do: [:f | f copyTo: dir / f basename].
    ^ self].
  space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
  [(space newDatabase: 'cc') newTransactionDo: [:t |
     (aCase at: 'setup') do: [:step |
       step first = 'set root'
         ifTrue: [t setRootObject: (step at: 2) value: (self setupValue: (step at: 3))]
         ifFalse: [CaseSide apply: step to: t committed: Dictionary new]]]]
    ensure: [space close].

"The dump notation of py_case.py's render."
CaseTable class >> render: aValue
  | parts |
  aValue isNil ifTrue: [^ 'absent'].
  aValue == true ifTrue: [^ 'true'].
  aValue == false ifTrue: [^ 'false'].
  aValue isInteger ifTrue: [^ aValue printString].
  aValue isString ifTrue: [^ '''' , aValue , ''''].
  (aValue isKindOf: PBDictionary) ifTrue: [
    parts := (aValue keys asArray asSortedCollection: [:x :y | x <= y]) asArray
      collect: [:k | (self render: k) , ': ' , (self render: (aValue getAt: k))].
    ^ '{' , (self join: parts) , '}'].
  (aValue isKindOf: PBList) ifTrue: [^ '[' , (self join: (aValue elements collect: [:v | self render: v])) , ']'].
  (aValue isKindOf: PBSet) ifTrue: [
    parts := (aValue elements collect: [:e | self render: e]) asSortedCollection: [:x :y | x <= y].
    ^ '#{' , (self join: parts asArray) , '}'].
  (aValue isKindOf: PBCountedSet) ifTrue: [
    parts := (aValue items collect: [:each | (self render: each key) , ': ' , each value printString])
      asSortedCollection: [:x :y | x <= y].
    ^ '#{' , (self join: parts asArray) , '}'].
  (aValue isKindOf: PBObject) ifTrue: [^ '<object>'].
  ^ Error signal: 'CaseTable: no dump notation for ' , aValue class name.

CaseTable class >> join: anArray
  | out |
  out := WriteStream on: String new.
  anArray doWithIndex: [:each :i |
    i > 1 ifTrue: [out nextPutAll: ', '].
    out nextPutAll: each].
  ^ out contents.

CaseTable class >> dump: aCase in: aDatabase
  | t lines |
  t := aDatabase newTransaction.
  lines := OrderedCollection new.
  (aCase at: 'roots') do: [:name |
    lines addLast: 'root ' , name , ' = ' , (self render: (t getRootObject: name))].
  (aCase at: 'mutables') do: [:name |
    lines addLast: 'mutable ' , name , ' = ' , (self render: (t getMutable: name))].
  t abort.
  ^ lines asArray.

Object subclass: #CaseSide instanceVariableNames: 'transaction outcome'.

"Runs one step of a case on aTransaction; aCommitted maps a root to the value a 'reuse
 committed' step committed before the transaction started."
CaseSide class >> apply: aStep to: t committed: aCommitted
  | op |
  op := aStep first.
  op = 'read root' ifTrue: [^ t getRootObject: (aStep at: 2)].
  op = 'set root' ifTrue: [^ t setRootObject: (aStep at: 2) value: (aStep at: 3)].
  op = 'blind dict set root' ifTrue: [
    ^ t setRootObject: (aStep at: 2) value: (t newDictionary setAt: (aStep at: 3) value: (aStep at: 4))].
  op = 'replace' ifTrue: [
    ^ t setRootObject: (aStep at: 2) value: (t newDictionary setAt: (aStep at: 3) value: (aStep at: 4)) replace: true].
  op = 'list set' ifTrue: [^ t setRootObject: (aStep at: 2) value: (t newList appendLast: (aStep at: 3))].
  op = 'set add' ifTrue: [^ t setRootObject: (aStep at: 2) value: (t newSet add: (aStep at: 3))].
  op = 'set remove' ifTrue: [^ t setRootObject: (aStep at: 2) value: (t newSet remove: (aStep at: 3))].
  op = 'counted set ops' ifTrue: [ | mode written |
    mode := aStep at: 3.
    (#('blind' 'read' 'replace') includes: mode) ifFalse: [
      ^ Error signal: 'CaseSide: unknown counted set mode ' , mode printString].
    written := mode = 'read' ifTrue: [t getRootObject: (aStep at: 2)] ifFalse: [t newCountedSet].
    4 to: aStep size by: 2 do: [:i | | kind |
      kind := aStep at: i.
      kind = 'add'
        ifTrue: [written := written add: (aStep at: i + 1)]
        ifFalse: [
          kind = 'remove'
            ifTrue: [written := written remove: (aStep at: i + 1)]
            ifFalse: [^ Error signal: 'CaseSide: unknown counted set op ' , kind printString]]].
    ^ t setRootObject: (aStep at: 2) value: written replace: mode = 'replace'].
  op = 'new mutable' ifTrue: [^ t newMutable: (aStep at: 2) value: (aStep at: 3)].
  op = 'set mutable' ifTrue: [^ t setMutable: (aStep at: 2) value: (aStep at: 3)].
  op = 'remove mutable' ifTrue: [^ t removeMutable: (aStep at: 2)].
  op = 'reuse committed' ifTrue: [
    ^ t setRootObject: (aStep at: 2) value: ((aCommitted at: (aStep at: 2)) setAt: (aStep at: 5) value: (aStep at: 6))].
  ^ Error signal: 'CaseSide: unknown step ' , aStep printString.

"The steps that run before the side's transaction starts: a 'reuse committed' step commits its
 root as a new Dictionary {k1: v1}, blindly. Answers root -> the committed value."
CaseSide class >> prepare: aSteps in: aDatabase
  | committed |
  committed := Dictionary new.
  aSteps do: [:step |
    step first = 'reuse committed' ifTrue: [ | written |
      aDatabase newTransactionDo: [:t |
        written := t newDictionary setAt: (step at: 3) value: (step at: 4).
        t setRootObject: (step at: 2) value: written].
      committed at: (step at: 2) put: written]].
  ^ committed.

CaseSide >> start: aSteps in: aDatabase
  | committed |
  committed := CaseSide prepare: aSteps in: aDatabase.
  transaction := aDatabase newTransaction.
  [aSteps do: [:step | CaseSide apply: step to: transaction committed: committed]]
    on: PBDBError do: [:e |
      outcome := e class name asString.
      transaction isActive ifTrue: [transaction abort]].
  ^ self.

CaseSide >> commit
  outcome isNil ifTrue: [
    outcome := [transaction commit. 'committed'] on: PBDBError do: [:e | e class name asString]].
  ^ outcome.

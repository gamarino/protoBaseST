"EXPECT: hashes 34/36 expected 2 atom_hashes 3/3"
"The manifest's hashes and atom_hashes sections (FS 'Hash keys'): PBKeys hashKey: of each
 value, and of an atom with each oid, is the listed signed 64-bit integer. Ids are
 'kind body' and 'oid <hex>' (_keyvectors.st); a listed expected difference prints
 EXPECTED <id>."
Import from: 'protobase'.
Import from: '_vectors'.
Import from: '_keyvectors'.
| manifest entries run lines failures |
manifest := Vectors manifest.
lines := OrderedCollection new.
failures := 0.
entries := manifest at: 'hashes'.
run := VectorRun section: 'hashes' ids: (entries collect: [:e | KeyVectors idOf: (e at: 'value')]).
entries do: [:entry |
  | id |
  id := KeyVectors idOf: (entry at: 'value').
  run begin.
  run stage: 'hash' of: id do: [
    | h |
    h := (PBKeys hashKey: (PBNotation build: (entry at: 'value'))) printString.
    h = (entry at: 'hash_key') ifTrue: [nil] ifFalse: ['hashed to ' , h , ', the manifest says ' , (entry at: 'hash_key')]].
  run end: id].
failures := failures + run failures.
lines add: (run summaryAs: 'hashes').
entries := manifest at: 'atom_hashes'.
run := VectorRun section: 'atom_hashes' ids: (entries collect: [:e | 'oid ' , (e at: 'oid')]).
entries do: [:entry |
  | id |
  id := 'oid ' , (entry at: 'oid').
  run begin.
  run stage: 'hash' of: id do: [
    | h |
    h := (PBKeys hashKey: (KeyVectors atomWithOid: (entry at: 'oid'))) printString.
    h = (entry at: 'hash_key') ifTrue: [nil] ifFalse: ['hashed to ' , h , ', the manifest says ' , (entry at: 'hash_key')]].
  run end: id].
failures := failures + run failures.
lines add: (run summaryAs: 'atom_hashes').
failures > 0
  ifTrue: [('FAILED ' , failures printString , ' vector(s)') displayNl]
  ifFalse: [(' ' join: lines) displayNl]

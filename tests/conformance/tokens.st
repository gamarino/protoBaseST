"EXPECT: exact_tokens 33/34 expected 1 atom_tokens 3/3"
"The manifest's exact_tokens and atom_tokens sections (FS 'Exact tokens'): PBKeys
 exactToken: of each value is the listed bytes. The atom_tokens entries describe their
 value in words; this runner builds the three values they name, with an atom of the
 vectors' application type (no record is needed: every atom is {'@ref': nil})."
Import from: 'protobase'.
Import from: '_vectors'.
Import from: '_keyvectors'.
| manifest entries run lines failures atom atomValues |
manifest := Vectors manifest.
lines := OrderedCollection new.
failures := 0.
entries := manifest at: 'exact_tokens'.
run := VectorRun section: 'exact_tokens' ids: (entries collect: [:e | KeyVectors idOf: (e at: 'value')]).
entries do: [:entry |
  | id |
  id := KeyVectors idOf: (entry at: 'value').
  run begin.
  run stage: 'token' of: id do: [
    | t |
    t := (PBKeys exactToken: (PBNotation build: (entry at: 'value'))) hex asLowercase.
    t = (entry at: 'token') ifTrue: [nil] ifFalse: ['tokenized to ' , t , ', the manifest says ' , (entry at: 'token')]].
  run end: id].
failures := failures + run failures.
lines add: (run summaryAs: 'exact_tokens').
atom := KeyVectors atomWithOid: '12345678123456781234567812345678'.
atomValues := Dictionary new.
atomValues
  at: 'any atom' put: atom;
  at: 'the tuple (atom, 1)' put: (PBTuple withAll: { atom. 1 });
  at: 'the list [1, atom] holding a map {"k": atom}' put: (PBFrozenList withAll: { 1. PBFrozenDict withAssociations: { 'k' -> atom } }).
entries := manifest at: 'atom_tokens'.
run := VectorRun section: 'atom_tokens' ids: (entries collect: [:e | e at: 'value']).
entries do: [:entry |
  | id |
  id := entry at: 'value'.
  run begin.
  run stage: 'token' of: id do: [
    | v t |
    v := atomValues at: id ifAbsent: [nil].
    v isNil
      ifTrue: ['the runner does not know the value ' , id printString]
      ifFalse: [
        t := (PBKeys exactToken: v) hex asLowercase.
        t = (entry at: 'token') ifTrue: [nil] ifFalse: ['tokenized to ' , t , ', the manifest says ' , (entry at: 'token')]]].
  run end: id].
failures := failures + run failures.
lines add: (run summaryAs: 'atom_tokens').
failures > 0
  ifTrue: [('FAILED ' , failures printString , ' vector(s)') displayNl]
  ifFalse: [(' ' join: lines) displayNl]

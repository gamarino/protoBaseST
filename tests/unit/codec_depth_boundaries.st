"EXPECT: ok 9"
"Wire depth at the boundaries msgpack-python packs: empty containers open no
 level for their items, and a value inside an atom record sits 2 levels deep
 (plan Task 13). Kept apart from codec_refusals.st: several 510-deep
 recursions after that file's allocations crash protoST 0.9.0 intermittently
 (a runtime issue, reported in the Task 7 report)."
Import from: 'protobase'.
Import from: '_check'.
| c around |
c := Check new.
"Empty containers open no level for their items (msgpack-python's count)."
around := [:n :seed | | v | v := seed. n timesRepeat: [v := Array with: v]. v].
c that: 'an empty list in 511 lists' is: (PBCodec decode: (PBCodec encode: (around value: 511 value: #()))) class equals: PBFrozenList.
c that: 'an empty list in 512 lists' signals: PBValidationError containing: '511' during: [PBCodec encode: (around value: 512 value: #())].
c that: 'an empty tuple in 510 lists' is: (PBCodec decode: (PBCodec encode: (around value: 510 value: (PBTuple withAll: #())))) class equals: PBFrozenList.
c that: 'an empty tuple in 511 lists' signals: PBValidationError containing: '511' during: [
  PBCodec encode: (around value: 511 value: (PBTuple withAll: #()))].
c that: 'an empty map in 510 lists' is: (PBCodec decode: (PBCodec encode: (around value: 510 value: (PBFrozenDict withAssociations: #())))) class equals: PBFrozenList.
c that: 'an empty map in 511 lists' signals: PBValidationError containing: '511' during: [
  PBCodec encode: (around value: 511 value: (PBFrozenDict withAssociations: #()))].
"Inside an atom record a value sits 2 levels deep: 509 containers at most there."
c that: '509 lists inside an atom' is: (PBCodec canonical: (around value: 509 value: 1) enclosingDepth: 2) class equals: PBFrozenList.
c that: '510 lists inside an atom' signals: PBValidationError containing: '511' during: [
  PBCodec canonical: (around value: 510 value: 1) enclosingDepth: 2].
c that: '510 lists inside an atom (toWire:)' signals: PBValidationError containing: '511' during: [
  PBCodec toWire: (around value: 510 value: 1) atomRef: PBCodec pointerRef enclosingDepth: 2].
c report displayNl.

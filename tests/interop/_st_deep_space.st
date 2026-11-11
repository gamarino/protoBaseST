"_st_deep_space.st <directory>: writes a space whose database 'db' has the root 'deep', a
 DBObject whose attribute 'v' is 509 nested lists around 1, the deepest attribute value
 an atom record can hold (plan Task 13). A helper of st_deep_to_py.sh, never run as a
 test; the records are written with tests/unit/_spaces.st (on STPATH). Prints 'written'."
Import from: 'protobase'.
Import from: '_spaces'.

| args b deep ref |
args := Smalltalk arguments.
args size = 1 ifFalse: ['usage: _st_deep_space.st <directory>' displayNl. Smalltalk exit: 2].
deep := 1.
509 timesRepeat: [deep := Array with: deep].
b := SpaceBuilder segment: (ByteArray fromHex: '3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d').
ref := b add: 19 oid: 1 state: { 'v' -> deep }.
b writeTo: (args at: 1) asFileReference
  root: (b spaceWithDatabase: 'db' roots: { 'deep' -> ref } mutables: #() oids: 10).
'written' displayNl.

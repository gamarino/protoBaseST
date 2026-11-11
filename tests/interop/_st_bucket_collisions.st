"protoBaseST's side of bucket_collisions_identical.sh (a helper: the runner never runs files
 whose name starts with _). Runs the operation sequences of py_bucket_collisions.py on a
 PBHashDictionary and a PBSet whose _bucketHash: files every key under 7 and prints the same
 line after each operation: '<kind> <op> <args> => count <n> node <hash or none> bucket <hex
 or none>', the bucket as PBCodec encode: of the bucket tuple. Arguments print as Python's
 repr ('a', 1, f1.0)."
Import from: 'protobase'.

PBHashDictionary subclass: #CollidingHashDictionary.
CollidingHashDictionary >> _bucketHash: aCanonical
  ^ 7.
PBSet subclass: #CollidingSet.
CollidingSet >> _bucketHash: aCanonical
  ^ 7.

| arg show d s dictOps setOps |
arg := [:v | v isString ifTrue: ['''' , v , ''''] ifFalse: [v isFloat ifTrue: ['f' , v printString] ifFalse: [v printString]]].
show := [:kind :op :coll |
  | root line |
  root := coll stateAt: 'root'.
  line := kind , ' ' , (op at: 1).
  2 to: op size do: [:i | line := line , ' ' , (arg value: (op at: i))].
  line := line , ' => count ' , coll count printString , ' node '
    , (root isNil ifTrue: ['none'] ifFalse: [root key printString]) , ' bucket '
    , (root isNil ifTrue: ['none'] ifFalse: [(PBCodec encode: root value) hex asLowercase]).
  line displayNl].
dictOps := { #('set' 'a' 1). #('set' 'b' 2). #('set' 'c' 3). #('set' 'b' 20). #('set' 1 'x').
  { 'set'. 1.0. 'y' }. #('remove' 'b'). #('remove' 'zz'). #('remove' 'c'). #('remove' 'a'). #('remove' 1) }.
setOps := { #('add' 'a'). #('add' 'b'). #('add' 'c'). #('add' 1). { 'add'. 1.0 }. #('remove' 'b').
  #('remove' 'zz'). #('remove' 'a'). #('remove' 'c'). #('remove' 1) }.
d := CollidingHashDictionary new.
dictOps do: [:op |
  d := (op at: 1) = 'set' ifTrue: [d setAt: (op at: 2) value: (op at: 3)] ifFalse: [d removeAt: (op at: 2)].
  show value: 'dict' value: op value: d].
s := CollidingSet new.
setOps do: [:op |
  s := (op at: 1) = 'add' ifTrue: [s add: (op at: 2)] ifFalse: [s remove: (op at: 2)].
  show value: 'set' value: op value: s].

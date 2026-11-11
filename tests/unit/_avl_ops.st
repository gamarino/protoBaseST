"_avl_ops.st: the seeded operation sequences of the AVL tests (plan Task 14), and the node
 dump the interop test compares with ProtoBase's (a helper: the runner never runs files
 whose name starts with _).

  ops := AvlOps new.                 a generator over Random seed: AvlOps seed (20261110)
  ops nextPosOpFor: n                the next operation on a positional tree of n elements
  ops nextKeyOp / nextCountedOp      the next operation on a keyed / weighted keyed tree
  AvlOps valueOf: aToken             the value a token stands for
  AvlOps dump: aRoot                 the lines that describe aRoot, node by node

An operation is an Array: { #insert. index. token }, { #append. index. token },
{ #set. index. token }, { #remove. index } on positional trees; { #put. keyToken.
token } and { #delete. keyToken } on keyed trees. A token is a String that names a value
the same way in protoST and in Python (tests/interop/py_avl_replay.py):

  i:<n>     the Integer n             g:<n>    the Float n           h:<n>   the Float n + 0.5
  s:<text>  the ASCII String text     E:<n>    n code points U+00E9  B:<n>   n bytes 0xAB
  t:<p>:<c> the tuple (p, c) of Integers, a weighted node value

The sequence a generator draws depends only on the seed and on the sizes it is given, so
the unit tests and the interop program draw the same operations."
Import from: 'random'.
Import from: 'protobase'.

Object subclass: #AvlOps instanceVariableNames: 'random'.

AvlOps class >> seed
  ^ 20261110.

AvlOps class >> new
  ^ self basicNew setRandom: (Random seed: self seed).

AvlOps >> setRandom: aRandom
  random := aRandom.

"An Integer in lo..hi drawn from the high bits of the generator (Random next): the low
 bits of its linear congruential state have short periods (Random between:and: takes the
 state modulo the range), which would correlate successive draws."
AvlOps >> between: lo and: hi
  ^ lo + (random next * (hi - lo + 1)) truncated.

"A positional operation on a tree of anInteger elements: below 64 elements insert 40 %,
 append 10 %, set 20 %, remove 30 %; from 64 on, remove 50 % and insert 20 %, so the
 tree grows to about 64 elements (height 7 or 8) and stays there: every rotation and
 successor removal occurs many times, and a check after each operation stays affordable
 (insert only on an empty tree)."
AvlOps >> nextPosOpFor: anInteger
  | k inserts |
  k := anInteger = 0 ifTrue: [1] ifFalse: [self between: 1 and: 10].
  inserts := anInteger < 64 ifTrue: [4] ifFalse: [2].
  k <= inserts ifTrue: [^ { #insert. self between: 0 and: anInteger. self valueToken }].
  k = 5 ifTrue: [^ { #append. anInteger. self valueToken }].
  (k between: 6 and: 7) ifTrue: [^ { #set. self between: 0 and: anInteger - 1. self valueToken }].
  ^ { #remove. self between: 0 and: anInteger - 1 }.

"A keyed operation: put 50 %, delete 50 % (of a key that may be absent). Over the 120
 keys of keyToken the tree holds about 60 keys (height 6 to 8)."
AvlOps >> nextKeyOp
  (self between: 1 and: 10) <= 5 ifTrue: [^ { #put. self keyToken. self valueToken }].
  ^ { #delete. self keyToken }.

"A keyed operation on Number keys within lo..hi: put 50 %, delete 50 %, of an Integer
 (i:n) or of n + 0.5 (h:n)."
AvlOps >> nextKeyOpFrom: lo to: hi
  | n key |
  n := self between: lo and: hi.
  key := ((self between: 1 and: 2) = 1 ifTrue: ['i:'] ifFalse: ['h:']) , n printString.
  (self between: 1 and: 10) <= 5 ifTrue: [^ { #put. key. self valueToken }].
  ^ { #delete. key }.

"A weighted keyed operation: put 60 % of a (payload, count) pair, delete 40 %."
AvlOps >> nextCountedOp
  | key |
  key := 'i:' , (self between: 0 and: 99) printString.
  (self between: 1 and: 10) <= 6 ifTrue: [
    ^ { #put. key. 't:' , (self between: 0 and: 999) printString , ':' , (self between: 0 and: 5) printString }].
  ^ { #delete. key }.

"Keys of four kinds over 0..29: an Integer, the Float of the same number (one key with
 it), the Float n + 0.5, and a String (120 distinct keys); so the keys of a tree mix
 three ranks."
AvlOps >> keyToken
  | n kind |
  n := self between: 0 and: 29.
  kind := self between: 1 and: 4.
  kind = 1 ifTrue: [^ 'i:' , n printString].
  kind = 2 ifTrue: [^ 'g:' , n printString].
  kind = 3 ifTrue: [^ 'h:' , n printString].
  ^ 's:k' , n printString.

"Mostly Integers; one value in 20 is a String or bytes around the boxing threshold (254
 to 258 code points or bytes)."
AvlOps >> valueToken
  | k |
  k := self between: 1 and: 40.
  k = 1 ifTrue: [^ 'E:' , (self between: 254 and: 258) printString].
  k = 2 ifTrue: [^ 'B:' , (self between: 254 and: 258) printString].
  ^ 'i:' , (self between: 0 and: 999999) printString.

AvlOps class >> valueOf: aToken
  | kind body parts |
  kind := aToken first.
  body := aToken copyFrom: 3 to: aToken size.
  kind = $i ifTrue: [^ body asNumber].
  kind = $g ifTrue: [^ body asNumber asFloat].
  kind = $h ifTrue: [^ body asNumber asFloat + 0.5].
  kind = $s ifTrue: [^ body].
  kind = $E ifTrue: [^ String new: body asNumber withAll: (Character value: 233)].
  kind = $B ifTrue: [^ ByteArray withAll: (Array new: body asNumber withAll: 171)].
  kind = $t ifTrue: [
    parts := body subStrings: ':'.
    ^ PBTuple withAll: { (parts at: 1) asNumber. (parts at: 2) asNumber }].
  ^ Error signal: 'AvlOps: unknown token ' , aToken printString.

"The text of an operation: its words separated by spaces."
AvlOps class >> textOf: anOp
  | out |
  out := WriteStream on: String new.
  anOp doWithIndex: [:each :i |
    i > 1 ifTrue: [out nextPut: $ ].
    each isString ifTrue: [out nextPutAll: each] ifFalse: [out print: each]].
  ^ out contents.

"=== the dump ================================================================"

"The segment of the pointers the dump gives to the atoms of a tree."
AvlOps class >> dumpSegment
  ^ ByteArray fromHex: '0123456789abcdef0123456789abcdef'.

"The lines that describe the tree aRoot: one per atom (node or value box), in pre-order,
 a node before its box. An atom is numbered by its position in that order; a line is
 '<number> <type name> <hex of the msgpack of the encoded state>', where a reference to an
 atom is the pointer (dumpSegment, its number, its type tag). So two trees dump alike when
 they have the same shape and every node the same fields and encoded bytes."
AvlOps class >> dump: aRoot
  | lines |
  lines := Dictionary new.
  aRoot isNil ifFalse: [self dump: aRoot from: 0 into: lines].
  ^ (0 to: lines size - 1) asArray collect: [:i | lines at: i].

"Dumps the subtree aNode numbered from anInteger; answers the next free number."
AvlOps class >> dump: aNode from: anInteger into: aDictionary
  | box leftStart rightStart next numbers |
  box := (aNode storedValue isKindOf: PBValueBox) ifTrue: [aNode storedValue] ifFalse: [nil].
  leftStart := anInteger + 1 + (box isNil ifTrue: [0] ifFalse: [1]).
  rightStart := aNode left isNil
    ifTrue: [leftStart]
    ifFalse: [self dump: aNode left from: leftStart into: aDictionary].
  next := aNode right isNil
    ifTrue: [rightStart]
    ifFalse: [self dump: aNode right from: rightStart into: aDictionary].
  numbers := { aNode left -> leftStart. aNode right -> rightStart. box -> (anInteger + 1) }.
  aDictionary at: anInteger put: (self line: aNode number: anInteger numbers: numbers).
  box isNil ifFalse: [
    aDictionary at: anInteger + 1 put: (self line: box number: anInteger + 1 numbers: #())].
  ^ next.

AvlOps class >> line: anAtom number: anInteger numbers: anArray
  | ref map |
  ref := [:atom |
    | found |
    found := anArray detect: [:each | each key == atom] ifNone: [nil].
    found isNil ifTrue: [^ Error signal: 'AvlOps dump: an unexpected reference'].
    PBCodec _tagged: '@ref' body: { self dumpSegment. found value. PBTypeRegistry writerTag: atom tag }].
  map := MessagePackMap withAll: (anAtom state associations collect: [:each |
    each key -> (PBCodec toWire: each value atomRef: ref)]).
  ^ anInteger printString , ' ' , anAtom class typeName , ' ' , (MessagePack encode: map) hex.

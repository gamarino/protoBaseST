"_st_read_deep.st <directory>: protoST's side of py_deep_to_st.sh (a helper, never run as a
 test). Reads the space py_write_deep.py wrote through a transaction: 'deep' and 'keyed' hold
 values exactly 1022 containers deep (PBCodec valueDepth:, format spec v2.0.0rc2, 'Value
 nesting depth'), 'deep' is 1022 lists around 1, the List element and the Dictionary key and
 value are 1022 deep, the Set element 1020 and the HashDictionary key and value 1018, the
 bucket node values of the Set and the HashDictionary exactly 1022; and the record of each
 root, and of each collection's root node, decodes and encodes back to the bytes ProtoBase
 wrote. Prints 'st read deep ok', or each failed check and exits 1."
Import from: 'protobase'.

| args failures check space st tx nest lists sameBytes deep keyed list dict set hash |
args := Smalltalk arguments.
args size = 1 ifFalse: ['usage: _st_read_deep.st <directory>' displayNl. Smalltalk exit: 2].
failures := OrderedCollection new.
check := [:label :actual :expected |
  actual = expected ifFalse: [
    failures add: label , ': expected ' , expected printString , ', got ' , actual printString]].
nest := [:n :seed :wrap | | v | v := seed. n timesRepeat: [v := wrap value: v]. v].
lists := [:n | nest value: n value: 1 value: [:v | Array with: v]].
space := PBObjectSpace storage: (PBFileStorage path: (args at: 1)).
st := space storage.
"Whether the record of anAtom decodes and encodes back to its bytes."
sameBytes := [:anAtom | | payload |
  payload := (st recordAt: anAtom pointer) at: 2.
  (PBAtomEnvelope decode: payload expecting: anAtom tag) encode = payload].
tx := (space openDatabase: 'db') newTransaction.
deep := tx getRootObject: 'deep'.
keyed := tx getRootObject: 'keyed'.
check value: 'deep: the depth of v' value: (PBCodec valueDepth: (deep at: 'v')) value: 1022.
check value: 'deep: 1022 lists around 1' value: (PBCodec encode: (deep at: 'v')) value: (PBCodec encode: (lists value: 1022)).
check value: 'keyed: the depth of v' value: (PBCodec valueDepth: (keyed at: 'v')) value: 1022.
list := tx getRootObject: 'list'.
check value: 'the List element' value: (PBCodec valueDepth: (list getAt: 0)) value: 1022.
dict := tx getRootObject: 'dict'.
check value: 'the Dictionary key and value' value: { PBCodec valueDepth: dict keys first. PBCodec valueDepth: dict values first }
  value: #(1022 1022).
set := tx getRootObject: 'set'.
check value: 'the Set element' value: (PBCodec valueDepth: set elements first) value: 1020.
check value: 'the Set''s bucket node value' value: (PBCodec valueDepth: (set stateAt: 'root') value) value: 1022.
hash := tx getRootObject: 'hash'.
check value: 'the HashDictionary key and value' value: { PBCodec valueDepth: hash keys first. PBCodec valueDepth: hash values first }
  value: #(1018 1018).
check value: 'the HashDictionary''s bucket node value' value: (PBCodec valueDepth: (hash stateAt: 'root') value) value: 1022.
{ 'deep' -> deep. 'keyed' -> keyed. 'list' -> list. 'dict' -> dict. 'set' -> set. 'hash' -> hash } do: [:each |
  check value: each key , ': its record re-encodes to ProtoBase''s bytes' value: (sameBytes value: each value) value: true].
{ 'list' -> list. 'dict' -> dict. 'set' -> set. 'hash' -> hash } do: [:each |
  check value: each key , ': its root node re-encodes to ProtoBase''s bytes'
    value: (sameBytes value: (each value stateAt: 'root')) value: true].
tx abort.
space close.
failures isEmpty ifFalse: [
  failures do: [:each | ('FAIL: ' , each) displayNl].
  Smalltalk exit: 1].
'st read deep ok' displayNl.

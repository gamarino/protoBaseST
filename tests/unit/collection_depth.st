"EXPECT: ok 21"
"The nesting limit binds every attribute value a structure stores (format spec v2.0.0rc2,
 'Value nesting depth', informative table; ProtoBase D60; plan Task 17b): a List element,
 a Dictionary key or value is stored as it is (1022 at most); a Set element sits in its
 bucket tuple (2 more: 1020 at most); a HashDictionary key or value in the (key, value)
 entry of its bucket tuple (4 more: 1018 at most). A mutator refuses a value past its
 limit when it is called, with PBValidationError naming the collection's element, key or
 value (and the wrapping and the effective limit), never later at commit. A value at the
 limit is accepted and its stored node attribute is exactly 1022 containers deep."
Import from: 'protobase'.
Import from: '_check'.

| c nest lists tuples deep1023 limitMsg list dict set hash node |
c := Check new.
nest := [:n :seed :wrap | | v | v := seed. n timesRepeat: [v := wrap value: v]. v].
lists := [:n | nest value: n value: 1 value: [:v | Array with: v]].
tuples := [:n | nest value: n value: 1 value: [:v | PBTuple withAll: { v }]].
limitMsg := 'The value nests deeper than MAX_VALUE_DEPTH = 1022'.

"PBList: an element is a node's value, unwrapped."
list := PBList new appendLast: (lists value: 1022).
c that: 'a List element of 1022' is: (PBCodec valueDepth: (list getAt: 0)) equals: 1022.
c that: 'appendLast: of 1023' signals: PBValidationError containing: 'PBList element: ' , limitMsg during: [
  PBList new appendLast: (lists value: 1023)].
c that: 'insertAt: of 1023' signals: PBValidationError containing: 'PBList element: ' , limitMsg during: [
  list insertAt: 0 value: (lists value: 1023)].
c that: 'setAt: of 1023' signals: PBValidationError containing: 'PBList element: ' , limitMsg during: [
  list setAt: 0 value: (lists value: 1023)].
c that: 'extend: with one of 1023' signals: PBValidationError containing: 'PBList element: ' , limitMsg during: [
  PBList new extend: { 1. lists value: 1023 }].

"PBDictionary: a key (orderable: tuples) and a value, each unwrapped."
dict := PBDictionary new setAt: (tuples value: 511) value: (lists value: 1022).
c that: 'a Dictionary key of 511 tuples' is: (PBCodec valueDepth: dict keys first) equals: 1022.
c that: 'a Dictionary value of 1022' is: (PBCodec valueDepth: dict values first) equals: 1022.
c that: 'a key of 512 tuples' signals: PBValidationError containing: 'PBDictionary key: ' , limitMsg during: [
  PBDictionary new setAt: (tuples value: 512) value: 1].
c that: 'a value of 1023' signals: PBValidationError containing: 'PBDictionary value: ' , limitMsg during: [
  PBDictionary new setAt: 1 value: (lists value: 1023)].

"PBSet: an element in its bucket tuple (2): 510 tuples (1020) at most."
set := PBSet new add: (tuples value: 510).
c that: 'a Set of an element of 510 tuples' is: set count equals: 1.
c that: 'its bucket node value is 1022 deep' is: (PBCodec valueDepth: (set stateAt: 'root') value) equals: 1022.
c that: 'an element of 511 tuples (1022, its bucket would make 1024)' signals: PBValidationError
  containing: 'PBSet element nests 1022 MessagePack containers deep, and its bucket tuple adds 2 around it, so it may nest at most 1020 (MAX_VALUE_DEPTH = 1022, format spec "Value nesting depth")'
  during: [PBSet new add: (tuples value: 511)].
c that: 'an element past the limit itself' signals: PBValidationError containing: 'PBSet element: ' , limitMsg during: [
  PBSet new add: (tuples value: 512)].
c that: 'union: refuses it as add: does' signals: PBValidationError containing: 'PBSet element nests 1022' during: [
  PBSet new union: { tuples value: 511 }].
c that: 'intersection: refuses it as ProtoBase''s from_iterable does' signals: PBValidationError
  containing: 'PBSet element nests 1022' during: [set intersection: { tuples value: 511 }].

"PBHashDictionary: a key and a value in a (key, value) entry of a bucket tuple (4): 1018."
hash := PBHashDictionary new setAt: (tuples value: 509) value: (lists value: 1018).
c that: 'a HashDictionary of a 1018 key and value' is: hash count equals: 1.
node := (hash stateAt: 'root') value.
c that: 'its bucket node value is 1022 deep' is: (PBCodec valueDepth: node) equals: 1022.
c that: 'a key of 510 tuples (1020)' signals: PBValidationError
  containing: 'PBHashDictionary key nests 1020 MessagePack containers deep, and its bucket entry (key, value) in its bucket tuple adds 4 around it, so it may nest at most 1018'
  during: [PBHashDictionary new setAt: (tuples value: 510) value: 1].
c that: 'a value of 1019' signals: PBValidationError
  containing: 'PBHashDictionary value nests 1019 MessagePack containers deep' during: [
    PBHashDictionary new setAt: 1 value: (lists value: 1019)].
c that: 'a value of 1018' is: (PBHashDictionary new setAt: 1 value: (lists value: 1018)) count equals: 1.

"A collection's record holds what its nodes reference: the node records encode, a value at
 the limit included, and decode back to the same bytes."
c that: 'a List node record of 1022 encodes and decodes' is: ((PBAtomEnvelope decode:
    (PBAtomEnvelope tag: 0 oid: (ByteArray new: 16) state: (PBFrozenDict withAssociations: { 'value' -> (list getAt: 0) })) encode
    expecting: 0) state at: 'value') equals: (list getAt: 0).
c report displayNl.

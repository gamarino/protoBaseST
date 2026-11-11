"EXPECT: ok 34"
"FS 'Map keys': 1, 1.0, Decimal 1.00 and true conflict pairwise; bools in a map
 without the numbers 0 and 1 are valid keys; two NaNs with one encoding
 conflict when written (a reader keeps them as two keys, format 3); a map is
 never collapsed. PBFrozenDict lookups follow the same rule (FS 'Order keys':
 equal keys), and PBCodec refuses conflicting keys when it writes."
Import from: 'protobase'.
Import from: '_check'.
| c map nanMap dec nan |
c := Check new.
dec := Decimal fromString: '1.00'.
c that: '{true -> 1. 1 -> 2} is refused' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { true -> 1. 1 -> 2 }].
c that: '{1 -> 2. true -> 1} is refused' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { 1 -> 2. true -> 1 }].
c that: '{false -> 1. 0.0 -> 2} is refused' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { false -> 1. 0.0 -> 2 }].
c that: '{true -> 1. 2 -> 2} is accepted' is: (PBFrozenDict withAssociations: { true -> 1. 2 -> 2 }) size equals: 2.
c that: '{false -> 1. true -> 2} is accepted' is: (PBFrozenDict withAssociations: { false -> 1. true -> 2 }) size equals: 2.
c that: '{1 -> a. 1.0 -> b} is refused' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { 1 -> 'a'. 1.0 -> 'b' }].
c that: '{1 -> a. Decimal 1.00 -> b} is refused' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { 1 -> 'a'. dec -> 'b' }].
c that: '{1.0 -> a. Decimal 1.00 -> b} is refused' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { 1.0 -> 'a'. dec -> 'b' }].
c that: '{(1, true) -> a. (1.0, 1) -> b} is refused' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { (PBTuple withAll: { 1. true }) -> 'a'. (PBTuple withAll: { 1.0. 1 }) -> 'b' }].
c that: '{0.1 -> a. Decimal 0.1 -> b} is accepted' is: (PBFrozenDict withAssociations: {
  0.1 -> 'a'. (Decimal fromString: '0.1') -> 'b' }) size equals: 2.
c that: '{2^53 -> a. 2^53 + 1 -> b} is accepted' is: (PBFrozenDict withAssociations: {
  (2 raisedTo: 53) -> 'a'. (2 raisedTo: 53) + 1 -> 'b' }) size equals: 2.
c that: '{1 -> a. "1" -> b} is accepted' is: (PBFrozenDict withAssociations: { 1 -> 'a'. '1' -> 'b' }) size equals: 2.
"Two NaNs with one encoding: two keys when read, refused when written."
nanMap := PBFrozenDict withAssociations: { Float nan -> 1. Float nan -> 2 }.
c that: 'two NaN objects are two keys' is: nanMap size equals: 2.
c that: 'NaN twice is refused when written' signals: PBValidationError containing: 'conflict' during: [
  PBCodec encode: nanMap].
c that: 'decimal NaN twice is refused when written' signals: PBValidationError containing: 'conflict' during: [
  PBCodec encode: (PBFrozenDict withAssociations: { (Decimal fromString: 'NaN') -> 1. (Decimal fromString: 'NaN') -> 2 })].
c that: 'NaNs of two payloads are two keys when written' is: (PBCodec decode: (PBCodec encode: (PBFrozenDict withAssociations: {
  (Decimal fromString: 'NaN') -> 1. (Decimal fromString: 'NaN5') -> 2 }))) size equals: 2.
c that: 'a float NaN and a decimal NaN are two keys when written' is: (PBCodec decode: (PBCodec encode: (PBFrozenDict withAssociations: {
  Float nan -> 1. (Decimal fromString: 'NaN') -> 2 }))) size equals: 2.
c that: 'one NaN object twice is refused (never collapsed)' signals: PBValidationError containing: 'twice' during: [
  | nan | nan := Float nan. PBFrozenDict withAssociations: { nan -> 1. nan -> 2 }].
"Lookups compare by the map-key rule."
map := PBFrozenDict withAssociations: { 1 -> 'one'. 'k' -> 'str'. (PBTuple withAll: { 2. 'x' }) -> 'tuple'. false -> 'false' }.
c that: 'at: 1' is: (map at: 1) equals: 'one'.
c that: 'at: 1.0' is: (map at: 1.0) equals: 'one'.
c that: 'at: Decimal 1.00' is: (map at: dec) equals: 'one'.
c that: 'at: true (Python: True == 1)' is: (map at: true) equals: 'one'.
c that: 'at: 0 (Python: 0 == False)' is: (map at: 0) equals: 'false'.
c that: 'at: (2.0, x)' is: (map at: (PBTuple withAll: { 2.0. 'x' })) equals: 'tuple'.
c that: 'at: 1.5 is absent' is: (map at: 1.5 ifAbsent: ['absent']) equals: 'absent'.
c that: 'includesKey: Decimal 1E+0' is: (map includesKey: (Decimal fromString: '1E+0')) equals: true.
c that: 'a NaN finds itself only' is: ((nanMap at: nanMap keys first) = 1 and: [(nanMap at: Float nan ifAbsent: [0]) = 0]) equals: true.
c that: 'a decoded vector map: true conflicts with 1' signals: PBCorruptionError during: [
  PBCodec decode: ('../conformance/vectors/invalid/map-key-bool-and-int.bin' asFileReference binaryContents)].
c that: 'a decoded vector map: equal numbers conflict' signals: PBCorruptionError during: [
  PBCodec decode: ('../conformance/vectors/invalid/map-key-equal-numbers.bin' asFileReference binaryContents)].
"A tuple holding a NaN finds itself through another tuple holding the same NaN
 object (Python compares tuple items by identity first)."
nan := Float nan.
c that: 'a tuple key holding a NaN, looked up by an equal tuple' is: ((PBFrozenDict withAssociations: {
  (PBTuple withAll: { nan. 1 }) -> 'x' }) at: (PBTuple withAll: { nan. 1 }) ifAbsent: ['absent']) equals: 'x'.
c that: 'two tuples holding one NaN object are one key' signals: PBValidationError containing: 'twice' during: [
  PBFrozenDict withAssociations: { (PBTuple withAll: { nan }) -> 1. (PBTuple withAll: { nan }) -> 2 }].
"Keys that can never be map keys are refused when the map is built, as the decoder does."
c that: 'a PBFrozenList key' signals: PBValidationError containing: 'list' during: [
  PBFrozenDict withAssociations: { (PBFrozenList withAll: #(1)) -> 1 }].
c that: 'an Array key' signals: PBValidationError containing: 'list' during: [
  PBFrozenDict withAssociations: { #(1 2) -> 1 }].
c that: 'a map key' signals: PBValidationError containing: 'map' during: [
  PBFrozenDict withAssociations: { (PBFrozenDict withAssociations: #()) -> 1 }].
c report displayNl.

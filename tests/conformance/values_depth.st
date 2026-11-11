"EXPECT: values_depth 6/6"
"The values_depth section of the manifest (README, 'Using the vectors', 10; format spec
 v2.0.0rc2, 'Value nesting depth'): max_value_depth is PBCodec maxValueDepth (1022) and each
 entry's containers; the file's msgpack data nests exactly that many containers; the value
 built from levels (kind, count pairs from the outside in) around leaf encodes to the file's
 bytes; the file decodes and encodes back to the same bytes; one more list around the value
 is refused by canonical: and by encode: (PBValidationError naming MAX_VALUE_DEPTH). The
 runs never compare deep values by printing them: the bytes are the check. A vector's
 failure prints FAIL <id>; the last line is the count."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest section entries run nest max |
manifest := Vectors manifest.
section := manifest at: 'values_depth'.
entries := section at: 'values'.
max := section at: 'max_value_depth'.
"leaf inside levels, built with loops (ProtoBase generate.nest)."
nest := [:levels :leaf |
  | value |
  value := leaf.
  levels reverse do: [:pair |
    | kind |
    kind := pair at: 1.
    (pair at: 2) timesRepeat: [
      value := kind = 'list' ifTrue: [Array with: value] ifFalse: [
        kind = 'tuple' ifTrue: [PBTuple withAll: { value }] ifFalse: [
          kind = 'keymap' ifTrue: [PBFrozenDict withAssociations: { value -> 'v' }] ifFalse: [
            kind = 'map' ifTrue: [PBFrozenDict withAssociations: { 'k' -> value }] ifFalse: [
              PBValidationError signal: 'values_depth: unknown level kind ' , kind printString]]]]]].
  value].
run := VectorRun section: 'values_depth' ids: (entries collect: [:e | e at: 'id']).
entries do: [:entry |
  | id bytes value |
  id := entry at: 'id'.
  run begin.
  run stage: 'limit' of: id do: [
    ({ max. entry at: 'containers' } allSatisfy: [:n | n = PBCodec maxValueDepth])
      ifTrue: [nil]
      ifFalse: ['max_value_depth ' , max printString , ' and containers ' , (entry at: 'containers') printString
        , ', PBCodec maxValueDepth ' , PBCodec maxValueDepth printString]].
  bytes := Vectors bytesOf: (entry at: 'file').
  run stage: 'wire' of: id do: [
    | depth |
    depth := PBCodec _wireTreeDepth: (MessagePack decodeOrdered: bytes strictKeys: false).
    depth = PBCodec maxValueDepth ifTrue: [nil] ifFalse: ['the file nests ' , depth printString , ' containers']].
  run stage: 'encode' of: id do: [
    | encoded |
    value := nest value: (entry at: 'levels') value: (PBNotation build: (entry at: 'leaf')).
    encoded := PBCodec encode: value.
    encoded = bytes ifTrue: [nil] ifFalse: ['the value encodes to ' , encoded size printString , ' other bytes']].
  run stage: 'reencode' of: id do: [
    | encoded |
    encoded := PBCodec encode: (PBCodec decode: bytes).
    encoded = bytes ifTrue: [nil] ifFalse: ['the decoded value re-encodes to ' , encoded size printString , ' other bytes']].
  run stage: 'deeper' of: id do: [
    | outcomes |
    outcomes := { [PBCodec canonical: (Array with: value). 'canonical: accepted it']
        on: PBValidationError do: [:e | (e messageText includesSubstring: 'MAX_VALUE_DEPTH') ifTrue: [nil] ifFalse: [e messageText]].
      [PBCodec encode: (Array with: value). 'encode: accepted it']
        on: PBValidationError do: [:e | (e messageText includesSubstring: 'MAX_VALUE_DEPTH') ifTrue: [nil] ifFalse: [e messageText]] }.
    (outcomes detect: [:each | each notNil] ifNone: [nil]) isNil
      ifTrue: [nil]
      ifFalse: ['one more list: ' , (outcomes detect: [:each | each notNil])]].
  run end: id].
run failures > 0
  ifTrue: [('FAILED ' , run failures printString , ' vector(s)') displayNl]
  ifFalse: [(run summaryAs: 'values_depth') displayNl]

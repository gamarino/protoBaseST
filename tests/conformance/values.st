"EXPECT: values 72/73 expected 1 decode-only 5/6 expected 1 read-not-rewritten 2/3 expected 1"
"The value vectors of the manifest, three sections (README, 'Using the vectors', 1 and 2):
   values                     decoding the file describes as the entry's value, and the
                              encoding of the value built from that description is the file's bytes
   values_decode_only         the decode describes as the value; re-encoding it gives the
                              bytes of the canonical file
   values_read_not_rewritten  the decode describes as the value; re-encoding it is refused
                              with PBValidationError
 A vector's failure prints FAIL <id>; a listed expected difference prints EXPECTED <id>
 (_expected_differences.st); the run goes on. The last line is the counts."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest lines failures clip decodeStage |
manifest := Vectors manifest.
lines := OrderedCollection new.
failures := 0.
clip := [:x | | t | t := x printString. t size > 240 ifTrue: [(t copyFrom: 1 to: 240) , '...'] ifFalse: [t]].
"The decode stage: the file decodes, and describes as the entry's value."
decodeStage := [:entry |
  | actual |
  actual := PBNotation describe: (PBCodec decode: (Vectors bytesOf: (entry at: 'file'))).
  actual = (entry at: 'value') ifTrue: [nil] ifFalse: [
    'decoded to ' , (clip value: actual) , ', the manifest says ' , (clip value: (entry at: 'value'))]].
#( #('values' 'values') #('values_decode_only' 'decode-only') #('values_read_not_rewritten' 'read-not-rewritten') ) do: [:pair |
  | name label entries run |
  name := pair at: 1. label := pair at: 2.
  entries := manifest at: name.
  run := VectorRun section: name ids: (entries collect: [:e | e at: 'id']).
  entries do: [:entry |
    | id file |
    id := entry at: 'id'. file := entry at: 'file'.
    run begin.
    run stage: 'decode' of: id do: [decodeStage value: entry].
    name = 'values' ifTrue: [
      run stage: 'encode' of: id do: [
        | bytes |
        bytes := PBCodec encode: (PBNotation build: (entry at: 'value')).
        bytes = (Vectors bytesOf: file) ifTrue: [nil] ifFalse: [
          'encoded to ' , bytes hex , ', the file is ' , (Vectors bytesOf: file) hex]]].
    name = 'values_decode_only' ifTrue: [
      run stage: 'reencode' of: id do: [
        | bytes canonical |
        bytes := PBCodec encode: (PBCodec decode: (Vectors bytesOf: file)).
        canonical := Vectors bytesOf: (entry at: 'canonical').
        bytes = canonical ifTrue: [nil] ifFalse: [
          're-encoded to ' , bytes hex , ', the canonical file is ' , canonical hex]]].
    name = 'values_read_not_rewritten' ifTrue: [
      run stage: 'refuse' of: id do: [
        | bytes |
        bytes := [PBCodec encode: (PBCodec decode: (Vectors bytesOf: file))]
          on: PBValidationError do: [:e | nil].
        bytes isNil ifTrue: [nil] ifFalse: ['re-encoded to ' , bytes hex , ' instead of PBValidationError']]].
    run end: id].
  failures := failures + run failures.
  lines add: (run summaryAs: label)].
failures > 0
  ifTrue: [('FAILED ' , failures printString , ' vector(s)') displayNl]
  ifFalse: [(' ' join: lines) displayNl]

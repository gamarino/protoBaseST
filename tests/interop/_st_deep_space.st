"_st_deep_space.st <directory>: protoST's side of st_deep_to_py.sh (a helper, never run as a
 test). Values at the nesting limit (format spec v2.0.0rc2, 'Value nesting depth':
 MAX_VALUE_DEPTH = 1022 containers per attribute value), written two ways:

  <directory>/space  through PBFileStorage's write side (plan Task 17): database 'db' whose
                     roots are 'deep' (a DBObject whose 'v' is 1022 lists around 1), 'keyed'
                     (a DBObject whose 'v' is a list around a map whose key is 509 tuples
                     around 1: 1022 through the key), 'list' (a List whose element is 1022
                     lists), 'dict' (a Dictionary from 511 tuples to 1022 lists), 'set' (a
                     Set of 510 tuples: 1022 in its bucket) and 'hash' (a HashDictionary from
                     509 tuples to 1018 lists: 1022 in its bucket)
  <directory>/over   built record by record (tests/unit/_spaces.st, on STPATH): database
                     'db' whose root 'over' is an ATOM record whose 'v' is 1023 lists, raw
                     bytes no writer produces (protoST's own writer refuses the value)

Before writing, it checks that protoST's writer refuses each value one container deeper
(PBValidationError). Prints 'written', or the failed check and exits 1."
Import from: 'protobase'.
Import from: '_spaces'.

| args dir nest lists tuples st objects dbRoot databases spaceRoot ptr b over payload refusals |
args := Smalltalk arguments.
args size = 1 ifFalse: ['usage: _st_deep_space.st <directory>' displayNl. Smalltalk exit: 2].
dir := args at: 1.
nest := [:n :seed :wrap | | v | v := seed. n timesRepeat: [v := wrap value: v]. v].
lists := [:n | nest value: n value: 1 value: [:v | Array with: v]].
tuples := [:n | nest value: n value: 1 value: [:v | PBTuple withAll: { v }]].

"protoST's writer refuses one container more, wherever the value goes."
refusals := {
  'a DBObject field of 1023' -> [PBObject withAll: { 'v' -> (lists value: 1023) }].
  'a List element of 1023' -> [PBList new appendLast: (lists value: 1023)].
  'a Dictionary value of 1023' -> [PBDictionary new setAt: 1 value: (lists value: 1023)].
  'a Set element of 511 tuples' -> [PBSet new add: (tuples value: 511)].
  'a HashDictionary key of 510 tuples' -> [PBHashDictionary new setAt: (tuples value: 510) value: 1] }.
refusals do: [:each |
  | outcome |
  outcome := [each value value. 'accepted'] on: PBValidationError do: [:e | nil].
  outcome isNil ifFalse: [('FAIL: protoST''s writer accepted ' , each key) displayNl. Smalltalk exit: 1]].

st := PBFileStorage path: (dir , '/space').
objects := PBDictionary new.
objects := objects setAt: 'deep' value: (PBObject withAll: { 'v' -> (lists value: 1022) }).
objects := objects setAt: 'keyed' value: (PBObject withAll: { 'v' -> (Array with:
  (PBFrozenDict withAssociations: { (tuples value: 509) -> 'v' })) }).
objects := objects setAt: 'list' value: (PBList new appendLast: (lists value: 1022)).
objects := objects setAt: 'dict' value: (PBDictionary new setAt: (tuples value: 511) value: (lists value: 1022)).
objects := objects setAt: 'set' value: (PBSet new add: (tuples value: 510)).
objects := objects setAt: 'hash' value: (PBHashDictionary new setAt: (tuples value: 509) value: (lists value: 1018)).
dbRoot := PBDatabaseRoot _unsavedWithState: (PBFrozenDict withAssociations: {
  'objects' -> objects. 'mutables' -> PBDictionary new. 'version' -> 0.
  'committed_at' -> (DateTime year: 2026 month: 11 day: 11 hour: 12 minute: 0 second: 0 microsecond: 0 fold: 0
    zone: ZoneOffset utc).
  'origin' -> (ByteArray fromHex: '0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d').
  'previous' -> nil }).
databases := PBDictionary new setAt: 'db' value: dbRoot.
spaceRoot := PBSpaceRoot _unsavedWithState: (PBFrozenDict withAssociations: { 'databases' -> databases }).
ptr := st save: spaceRoot.
st flushSegment.
st tryLockRoot ifFalse: [Error signal: 'the root lock is held by another process'].
[st replaceRoot: (PBRootRecord segment: ptr segmentBytes offset: ptr offset epoch: 1)] ensure: [st unlockRoot].
st close.

"{t: 19, oid: 16 x 0e, s: {v: 1023 lists around 1}}: a record 1025 containers deep."
b := SpaceBuilder segment: (ByteArray fromHex: '3e3e3e3e3e3e3e3e3e3e3e3e3e3e3e3e').
payload := (ByteArray fromHex: '83a17413a36f6964c410' , ((1 to: 16) inject: '' into: [:s :i | s , '0e']) , 'a17381a176')
  , (ByteArray withAll: ((1 to: 1023) asArray collect: [:i | 16r91])) , (ByteArray fromHex: '01').
over := b addPayload: payload tag: 19.
b writeTo: (dir , '/over') asFileReference
  root: (b spaceWithDatabase: 'db' roots: { 'over' -> over } mutables: #() oids: 20).
'written' displayNl.

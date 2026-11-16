"EXPECT: ok 4"
"The message types a node never sends at DEPTH 0 over shared storage (cluster plan CC7):
 records, warm, store, propose, fetch, fetched, commit_query and commit_info are decoded and
 validated like every type, then ignored by the dispatcher and counted 'ignored_messages'
 (PBCoordinatorCore class >> ignoredTypes, dispatchReceived:in:now:). The core called directly:
 (1) each of the eight, valid and from another member (store with this node's voter set),
 leaves the state as it was and answers exactly one PBCount 'ignored_messages'. (2) The same
 warm from a sender that is not a member is dropped by the core uncounted (the shell's
 dispatcher counts it 'messages_ignored', cluster_coordinator_attach.st (2)). (3) A store of
 another voter set counts 'config_mismatches' only: the fingerprint is checked first, as
 proto_db's _route does. (4) A handled type (want) is not counted 'ignored_messages'."
Import from: 'protobase'.
Import from: '_check'.

| c core peers config s vs seg msg step counted fields |
c := Check new.
core := PBCoordinatorCore new.
peers := #('n0' 'n1' 'n2') collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7000 + (#('n0' 'n1' 'n2') indexOf: id)].
config := PBClusterConfig nodeId: 'n1' peers: peers options: (Dictionary new at: #startupGrace put: 0; yourself).
s := PBNodeState config: config inc: 5.
vs := config membership fingerprint.
seg := Check bytes: '5eed0000000040008000000000001004'.
msg := [:type :from :someFields | PBReceived message: (PBClusterMessage type: type from: from fields: someFields)].
"The stats a step counts, in order: { class name. stat } per effect."
counted := [:aStep | aStep effects collect: [:e | { e class name. (e isKindOf: PBCount) ifTrue: [e stat] ifFalse: [nil] }]].
"A valid message of each ignored type (store with this node's voter set)."
fields := Dictionary new.
fields at: 'records' put: { 'term' -> 4096. 'rid' -> 1. 'inc' -> 1. 'index' -> 0. 'records' -> #() };
  at: 'warm' put: { 'term' -> 4096. 'records' -> #() };
  at: 'store' put: { 'term' -> 4096. 'rid' -> 1. 'inc' -> 1. 'root' -> nil. 'records' -> #(). 'chunks' -> 0.
    'ranges' -> nil. 'copies' -> #('n0'). 'vs' -> vs };
  at: 'propose' put: { 'term' -> 4096. 'seq' -> 1. 'inc' -> 1. 'root' -> nil. 'pred' -> nil };
  at: 'fetch' put: { 'rid' -> 1. 'inc' -> 1. 'segment' -> seg. 'offset' -> 26 };
  at: 'fetched' put: { 'rid' -> 1. 'inc' -> 1. 'segment' -> seg. 'offset' -> 26. 'data' -> nil };
  at: 'commit_query' put: { 'rid' -> 1. 'inc' -> 1. 'root' -> nil };
  at: 'commit_info' put: { 'rid' -> 1. 'inc' -> 1. 'persisted' -> false. 'ranges' -> nil }.

"(1)"
c that: 'each of the eight types from another member leaves the state and counts ignored_messages once'
  is: (#('records' 'warm' 'store' 'propose' 'fetch' 'fetched' 'commit_query' 'commit_info') collect: [:type |
    step := core dispatch: (msg value: type value: 'n0' value: (fields at: type)) in: s now: 1000.
    { type. step state == s. counted value: step }])
  equals: (#('records' 'warm' 'store' 'propose' 'fetch' 'fetched' 'commit_query' 'commit_info') collect: [:type |
    { type. true. #(#(#PBCount 'ignored_messages')) }]).

"(2)"
step := core dispatch: (msg value: 'warm' value: 'zz' value: (fields at: 'warm')) in: s now: 1000.
c that: 'a warm from a sender that is not a member is dropped by the core, uncounted'
  is: { step state == s. counted value: step }
  equals: { true. #() }.

"(3)"
step := core dispatch: (msg value: 'store' value: 'n0' value: ((fields at: 'store') collect: [:a |
    a key = 'vs' ifTrue: ['vs' -> (vs + 1)] ifFalse: [a]])) in: s now: 1000.
c that: 'a store of another voter set counts config_mismatches only'
  is: (counted value: step)
  equals: #(#(#PBCount 'config_mismatches')).

"(4)"
step := core dispatch: (msg value: 'want' value: 'n0' value: #()) in: s now: 1000.
c that: 'a handled type is not counted ignored_messages'
  is: ((counted value: step) anySatisfy: [:pair | pair last = 'ignored_messages'])
  equals: false.

c report displayNl.

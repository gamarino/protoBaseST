"EXPECT: ok 15"
"Fix round 1 of plan Task 14 (review M2, M3): the keyed writes answer ProtoBase's shapes,
 key_put's (new_root, replaced, old_value) and key_remove's (new_root, removed,
 old_value), as { root. Boolean. old value or nil }, the old value unboxed. The walks
 follow ProtoBase too: posDo:over: evaluates a block with each value (pos_iter),
 keysAndValuesDo:over: with each key and value (key_iter), both unboxed;
 nodesDo:over: with each node (_inorder)."
Import from: 'protobase'.
Import from: '_check'.
| c r root big values pairs nodes |
c := Check new.
big := String new: 300 withAll: $x.
r := PBAvl keyPut: nil key: 1 value: big nodeClass: PBKeyNode.
c that: 'a new key: three items' is: r size equals: 3.
c that: 'not replaced' is: (r at: 2) equals: false.
c that: 'no old value' is: (r at: 3) equals: nil.
root := r first.
r := PBAvl keyPut: root key: 1.0 value: 'small' nodeClass: PBKeyNode.
c that: 'replaced' is: (r at: 2) equals: true.
c that: 'the old value, unboxed' is: (r at: 3) equals: big.
c that: 'the stored key object is kept' isTrue: (PBAvl keyAt: r first key: 1) key == 1.
root := r first.
root := (PBAvl keyPut: root key: 2 value: 'two' nodeClass: PBKeyNode) first.
r := PBAvl keyRemove: root key: 3.
c that: 'an absent key: the same root' isTrue: r first == root.
c that: 'not removed' is: (r at: 2) equals: false.
c that: 'no old value when absent' is: (r at: 3) equals: nil.
r := PBAvl keyRemove: root key: 2.
c that: 'removed' is: (r at: 2) equals: true.
c that: 'the removed value' is: (r at: 3) equals: 'two'.
c that: 'the key is gone' is: (PBAvl keyAt: r first key: 2) equals: nil.
pairs := OrderedCollection new.
PBAvl keysAndValuesDo: [:k :v | pairs add: k -> v] over: root.
c that: 'keysAndValuesDo:over:' is: pairs asArray equals: { 1 -> 'small'. 2 -> 'two' }.
root := (PBAvl posAppend: (PBAvl posAppend: nil value: 'a') value: big).
values := OrderedCollection new.
PBAvl posDo: [:v | values add: v] over: root.
c that: 'posDo:over: answers values, unboxed' is: values asArray equals: { 'a'. big }.
nodes := OrderedCollection new.
PBAvl nodesDo: [:n | nodes add: n] over: root.
c that: 'nodesDo:over: answers the nodes' isTrue: ((nodes collect: [:n | n class]) asArray = { PBPosNode. PBPosNode }).
c report displayNl.

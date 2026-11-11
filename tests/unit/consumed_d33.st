"EXPECT: ok 13"
"D33 consumed marks (plan Task 16, design spec 7.2): after a commit ProtoBase marks each
 written value's log incomplete (object.__setattr__ of _log_complete), so a value reused in a
 later transaction replaces instead of replaying the same operations again. protoBaseST gives
 each version a consumed cell (an Atom holding false) that markConsumed sets; a version
 derived later reads its parent's cell at derivation time. ProtoBase v2.0.0rc1 answers, for
 v := Dictionary().set_at('a', 1), sib := v.set_at('b', 2) and then the mark on v:
 v.set_at('c', 3).log_is_complete False, sib.log_is_complete True, v.log_is_complete False,
 sib.set_at('d', 4).log_is_complete True."
Import from: 'protobase'.
Import from: '_check'.

| c v sib s ssib h |
c := Check new.
v := PBDictionary new setAt: 'a' value: 1.
sib := v setAt: 'b' value: 2.
c that: 'every version carries a consumed cell holding false' is: v consumed value equals: false.
c that: 'mergeable before the mark' isTrue: v isMergeable.
c that: 'markConsumed answers the receiver' isTrue: v markConsumed == v.
c that: 'the cell holds true' is: v consumed value equals: true.
c that: 'a version derived after the mark is not mergeable' is: (v setAt: 'c' value: 3) isMergeable equals: false.
c that: 'the sibling derived before the mark keeps true' isTrue: sib isMergeable.
c that: 'the marked version itself is no longer mergeable' is: v isMergeable equals: false.
c that: 'versions derived from the sibling stay mergeable' isTrue: (sib setAt: 'd' value: 4) isMergeable.
c that: 'marking twice changes nothing' is: v markConsumed isMergeable equals: false.
s := PBSet new add: 1.
ssib := s add: 2.
s markConsumed.
c that: 'a PBSet: derived after the mark' is: (s add: 3) isMergeable equals: false.
c that: 'a PBSet: its sibling derived before' isTrue: ssib isMergeable.
h := PBHashDictionary new setAt: 1 value: 1.
h markConsumed.
c that: 'a PBHashDictionary: derived after the mark' is: (h removeAt: 1) isMergeable equals: false.
c that: 'a set operation derived after the mark' is: (s union: #(7)) isMergeable equals: false.
c report displayNl.

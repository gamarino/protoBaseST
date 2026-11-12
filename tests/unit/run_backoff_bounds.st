"EXPECT: ok 4"
"PBDatabase class >> backoffFor:low:high:random: (plan Task 19; ProtoBase Database.run): the wait of attempt a is
 uniform(d/2, d) with d = min(high, low * 2^a), here as a whole number of milliseconds. Seeded, so deterministic."
Import from: 'protobase'.
Import from: '_check'.

| c r inRange values limit |
c := Check new.
r := Random seed: 7.
inRange := true.
values := OrderedCollection new.
0 to: 10 do: [:a | | d w |
  d := 200 min: 1 * (2 raisedTo: a).
  w := PBDatabase backoffFor: a low: 1 high: 200 random: r.
  values add: w.
  (w isKindOf: SmallInteger) ifFalse: [inRange := false].
  (w >= (d / 2) and: [w <= d]) ifFalse: [inRange := false]].
c that: 'attempts 0 to 10 are whole milliseconds within [d/2, d]' is: inRange equals: true.
c that: 'never above the high bound' is: (values allSatisfy: [:w | w <= 200]) equals: true.
"Many draws at the capped attempt cover the interval's both halves, none outside it."
limit := (1 to: 200) collect: [:i | PBDatabase backoffFor: 20 low: 1 high: 200 random: r].
c that: 'a capped attempt stays within [100, 200] and varies' is:
  ((limit allSatisfy: [:w | w >= 100 and: [w <= 200]]) and: [limit asSet size > 10]) equals: true.
c that: 'a fractional high bound is never exceeded by rounding' is:
  (((1 to: 100) collect: [:i | PBDatabase backoffFor: 5 low: 1 high: 2.5 random: r]) allSatisfy: [:w | w <= 2 and: [w isKindOf: SmallInteger]]) equals: true.
'ok 4' displayNl.

"EXPECT: ok 9"
"Lookups in a map of format-3 zone keys (design 4.3) check only the probe key,
 against what the map kept when it was built: a probe without an aware or
 format-3 datetime needs no check, and a zoned probe is placed by binary
 search. So = over a map of 3000 format-3 keys completes (it re-checked every
 key on each lookup before). The decidability cases themselves are in
 codec_tagged.st."
Import from: 'protobase'.
Import from: '_check'.
| c fmt3 utc big mixed n |
c := Check new.
fmt3 := [:y :mo :d :h :zone | PBCodec fromWire: (MessagePackMap withAll: { '@dt' -> { y. mo. d. h. 0. 0. 0. 0. { 'zone'. zone } } }) resolver: nil].
utc := [:y :mo :d :h | DateTime year: y month: mo day: d hour: h minute: 0 second: 0 microsecond: 0 fold: 0 zone: ZoneOffset utc].
n := 3000.
big := PBFrozenDict withAssociations: ((0 to: n - 1) asArray collect: [:i |
  (fmt3 value: 2000 + (i // 24 // 28) value: 1 + (i // 24 \\ 28 // 28) value: 1 + (i // 24 \\ 28) value: i \\ 24 value: 'America/New_York') -> i]).
c that: 'a map of 3000 format-3 keys' is: big size equals: n.
c that: 'it equals itself' is: big = big equals: true.
c that: 'a lookup by one of its keys' is: (big at: (big keys at: 77)) equals: 76.
c that: 'a lookup by a string' is: (big at: 'k' ifAbsent: ['absent']) equals: 'absent'.
c that: 'a lookup by an aware key within a day' signals: PBNotSupportedError containing: 'America/New_York' during: [
  big at: (utc value: 2000 value: 1 value: 1 value: 5)].
c that: 'a lookup by an aware key years away' is: (big at: (utc value: 1990 value: 1 value: 1 value: 5) ifAbsent: ['absent']) equals: 'absent'.
c that: 'a lookup by a format-3 key of another zone within 48 h' signals: PBNotSupportedError containing: 'Europe/Paris' during: [
  big at: (fmt3 value: 2000 value: 1 value: 2 value: 5 value: 'Europe/Paris')].
"A map with aware keys only, looked up by a format-3 probe."
mixed := PBFrozenDict withAssociations: { (utc value: 2026 value: 3 value: 8 value: 16) -> 1. 'k' -> 2 }.
c that: 'a format-3 probe next to an aware key' signals: PBNotSupportedError containing: 'America/New_York' during: [
  mixed at: (fmt3 value: 2026 value: 3 value: 8 value: 12 value: 'America/New_York')].
c that: 'a format-3 probe far from every aware key' is: (mixed at: (fmt3 value: 2020 value: 3 value: 8 value: 12 value: 'America/New_York') ifAbsent: ['absent']) equals: 'absent'.
c report displayNl.

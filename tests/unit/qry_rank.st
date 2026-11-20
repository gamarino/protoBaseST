"EXPECT: ok 5"
"Indexed queries, plan Task 6: rank access (proto_db D56; tests/property/test_index_rank.py at
 v2.0.0rc4). For every operator an index answers and for its ordered scans, windowFrom:to: equals
 the slice of execute (the windows of proto_db's test and 30 random ones per plan) and exactRows the
 number of rows, on indexes reached by the bulk build and by additions, removals and replacements,
 whose weights are recounted after each path; window bounds are validated; an index written without
 weights offers no rank access and still answers; a Sort by the index's key over its plan and a
 Filter of one term over its ordered scan window by rank, as do the scans of a PBList and a
 PBDictionary and a Limit over any of them, while a sort by another key or by two keys and a filter
 the index cannot answer do not. The elements are maps {'k' -> key. 'tag' -> t} (no 'k' for
 PBMissing) with keys drawn as proto_db's KEYS strategy draws them (-6..6, nil, absent, 'a' 'b'
 'c', a list, NaN), up to 40 per case, over QData seeds: 10 seeds (PBST_PROP_SEEDS, plan call
 IP16). Mapped in tests/unit/queries_checklist.tsv."
Import from: 'random'.
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.

"One seeded case: its random draws and the checks of a plan."
Object subclass: #RankCase instanceVariableNames: 'random fails'.

"QData random: discards the first draw, which neighbouring seeds share (seeds 2001 .. 2010 all
 draw about 0.01 first)."
RankCase class >> seed: anInteger fails: anOrderedCollection
  ^ self basicNew setRandom: (QData random: anInteger) fails: anOrderedCollection.

RankCase >> setRandom: aRandom fails: anOrderedCollection
  random := aRandom.
  fails := anOrderedCollection.

RankCase >> between: lo and: hi
  ^ lo + (random next * (hi - lo + 1)) truncated.

RankCase >> pick: anArray
  ^ anArray at: (self between: 1 and: anArray size).

"A key of proto_db's KEYS strategy; PBMissing default stands for an absent 'k'."
RankCase >> key
  ^ self pick: { self between: -6 and: 6. nil. PBMissing default. 'a'. 'b'. 'c'. PBFrozenList withAll: #(1 2). Float nan }.

RankCase >> element: aKey tag: aTag
  aKey == PBMissing default ifTrue: [^ PBFrozenDict withAssociations: { 'tag' -> aTag }].
  ^ PBFrozenDict withAssociations: { 'k' -> aKey. 'tag' -> aTag }.

RankCase >> elements
  ^ (1 to: (self between: 0 and: 40)) asArray collect: [:i | self element: self key tag: (self between: 0 and: 3)].

RankCase >> operand
  ^ (self between: 0 and: 1) = 0 ifTrue: [self between: -7 and: 7] ifFalse: [self pick: #('a' 'b' 'z')].

"proto_db's _terms: every comparison of one operand v, the between variants over v and a second
 operand w of v's type, 'in' (v, w, v), '?N', '?!N' and '== nil'."
RankCase >> terms
  | v w lo hi out |
  v := self operand.
  [w := self operand. w isString = v isString] whileFalse.
  lo := v. hi := w.
  hi < lo ifTrue: [lo := w. hi := v].
  out := OrderedCollection new.
  #('==' '!=' '<' '<=' '>' '>=') do: [:op | out add: (PBTerm path: 'k' op: op value: v)].
  PBTerm betweenOperators do: [:op | out add: (PBTerm path: 'k' op: op value: { lo. hi })].
  out add: (PBTerm path: 'k' op: 'in' value: { v. w. v }); add: (PBTerm path: 'k' op: '?N');
    add: (PBTerm path: 'k' op: '?!N'); add: (PBTerm path: 'k' op: '==' value: nil).
  ^ out asArray.

"anArray's rows aStart .. aStop - 1 (aStop nil: to the end), as Python slices them."
RankCase >> slice: anArray from: aStart to: aStop
  | stop |
  stop := aStop isNil ifTrue: [anArray size] ifFalse: [aStop min: anArray size].
  aStart >= stop ifTrue: [^ #()].
  ^ anArray copyFrom: aStart + 1 to: stop.

"proto_db's _check_plan, plus 30 random windows: exactRows is the row count, every window the
 slice of execute, by rank."
RankCase >> checkPlan: aPlan label: aLabel
  | rows n starts |
  rows := aPlan execute.
  n := rows size.
  aPlan byRank ifFalse: [^ fails add: aLabel , ': no rank access'].
  aPlan exactRows = n ifFalse: [^ fails add: aLabel , ': exactRows ' , aPlan exactRows printString , ' for ' , n printString].
  starts := { 0. 1. n // 2. (n - 1) max: 0. n. self between: 0 and: n + 2 } asSet asArray.
  starts do: [:a |
    { 0. 1. 3. n + 5 } do: [:size |
      (aPlan windowFrom: a to: a + size) = (self slice: rows from: a to: a + size) ifFalse: [
        ^ fails add: aLabel , ': window ' , a printString , ' size ' , size printString]]].
  30 timesRepeat: [ | a b |
    a := self between: 0 and: n + 2.
    b := (self between: 0 and: 4) = 0 ifTrue: [nil] ifFalse: [a + (self between: 0 and: n + 3)].
    (aPlan windowFrom: a to: b) = (self slice: rows from: a to: b) ifFalse: [
      ^ fails add: aLabel , ': random window ' , { a. b } printString]].
  (aPlan windowFrom: 0 to: nil) = rows ifFalse: [^ fails add: aLabel , ': the whole window'].

"Every supported term's plan and, for a range index, both ordered scans."
RankCase >> checkIndex: anIndex label: aLabel
  | problem |
  problem := RankCase weightsOf: anIndex.
  problem isNil ifFalse: [^ fails add: aLabel , ': ' , problem].
  self terms do: [:term |
    (anIndex supports: term) ifTrue: [self checkPlan: (anIndex plan: term) label: aLabel , ' ' , term printString]].
  (anIndex isKindOf: PBRangeIndex) ifTrue: [
    #(false true) do: [:d |
      self checkPlan: (anIndex orderedPlan: (PBKeySpec path: 'k') descending: d) label: aLabel , ' ordered ' , d printString]].

"nil when anIndex's weights are exact (proto_db tests/support/index_weights.py
 assert_exact_weights): every group's total is its members' recount and its members tree's weight,
 the groups tree's weight their sum, and with the side group the index's total; otherwise what
 differs."
RankCase class >> weightsOf: anIndex
  | recount side sideN |
  recount := 0.
  PBAvl keysAndValuesDo: [:key :group | | n |
    n := 0.
    PBKeyGroups group: group do: [:e :k | n := n + k].
    (n = (group at: 2) and: [n = (PBAvl keyWeight: (group at: 1))]) ifFalse: [^ 'group ' , key printString].
    recount := recount + n] over: anIndex groups.
  (PBAvl keyWeight: anIndex groups) = recount ifFalse: [^ 'groups weight'].
  side := anIndex side.
  sideN := 0.
  PBKeyGroups group: side do: [:e :k | sideN := sideN + k].
  (sideN = (side at: 2) and: [sideN = (PBAvl keyWeight: (side at: 1))]) ifFalse: [^ 'side group'].
  recount + sideN = anIndex count ifFalse: [^ 'total'].
  ^ nil.

| c seeds fails case elements index held refused sortKey plan unweighted old groups rows |
c := Check new.
seeds := QData seeds: 10.

"test_built_index_windows_equal_execution"
fails := OrderedCollection new.
1 to: seeds do: [:s |
  case := RankCase seed: s fails: fails.
  elements := case elements.
  case checkIndex: ((PBRangeIndex name: 'i' path: 'k') build: elements) label: 'built range ' , s printString.
  case checkIndex: ((PBEqualityIndex name: 'i' path: 'k') build: elements) label: 'built equality ' , s printString].
c that: 'windows equal the slices of execute on built indexes, for every operator and ordered scan'
  is: fails asArray equals: #().

"test_incremental_writes_keep_weights_exact"
fails := OrderedCollection new.
1 to: seeds do: [:s | | problems |
  case := RankCase seed: 1000 + s fails: fails.
  index := PBRangeIndex name: 'i' path: 'k'.
  held := OrderedCollection new.
  case elements do: [:e | index := index withAdded: e. held addLast: e].
  problems := OrderedCollection new.
  problems add: (RankCase weightsOf: index).
  (case between: 0 and: 15) timesRepeat: [
    held notEmpty ifTrue: [index := index withRemoved: (held removeAt: (case between: 1 and: held size))]].
  problems add: (RankCase weightsOf: index).
  (case between: 0 and: 10) timesRepeat: [
    held notEmpty ifTrue: [ | j new |
      j := case between: 1 and: held size.
      new := case element: case key tag: 9.
      index := index withReplaced: (held at: j) with: new.
      held at: j put: new]].
  (problems allSatisfy: [:p | p isNil]) ifFalse: [fails add: 'weights ' , s printString , ': ' , problems printString].
  case checkIndex: index label: 'incremental ' , s printString.
  index validate: held asArray].
c that: 'additions, removals and replacements keep the weights exact and the windows equal execution'
  is: fails asArray equals: #().

"test_window_bounds_are_validated"
plan := ((PBRangeIndex name: 'i' path: 'k') build: { PBFrozenDict withAssociations: { 'k' -> 1 }. PBFrozenDict withAssociations: { 'k' -> 2 } })
  orderedPlan: (PBKeySpec path: 'k') descending: false.
refused := [:aBlock | [aBlock value. nil] on: Error do: [:e | e return: e class]].
c that: 'window bounds are validated'
  is: { plan windowFrom: 5 to: 9. refused value: [plan windowFrom: -1 to: 2]. refused value: [plan windowFrom: 0 to: -1].
    refused value: [plan windowFrom: 1.5 to: 2]. refused value: [plan windowFrom: true to: 2]. refused value: [plan windowFrom: 0 to: 'x'].
    refused value: [(PBCollectionScan on: PBSet new) windowFrom: -1 to: nil] }
  equals: { #(). PBValidationError. PBValidationError. PBValidationError. PBValidationError. PBValidationError. PBValidationError }.

"test_an_unweighted_index_offers_no_window_and_still_answers"
index := (PBRangeIndex name: 'i' path: 'k') build: ((0 to: 19) asArray collect: [:j | PBFrozenDict withAssociations: { 'k' -> (j \\ 4). 'n' -> j }]).
groups := OrderedCollection new.
PBAvl keysAndValuesDo: [:key :group | | members |
  members := OrderedCollection new.
  PBAvl keysAndValuesDo: [:mk :entry | members add: { mk. entry }] over: (group at: 1).
  groups add: { key. PBTuple withAll: { PBAvl keyFromSorted: members asArray nodeClass: PBKeyNode. group at: 2 } }] over: index groups.
groups := PBAvl keyFromSorted: groups asArray nodeClass: PBKeyNode.
old := index _with: { 'groups' -> groups }.
plan := old plan: (PBTerm path: 'k' op: '>=' value: 2).
rows := plan execute.
unweighted := (old withAdded: (PBFrozenDict withAssociations: { 'k' -> 9 })) groups.
c that: 'an index written without weights offers no rank access and still answers'
  is: { groups class. plan byRank. plan exactRows. (plan windowFrom: 0 to: 3) = (rows copyFrom: 1 to: 3).
    rows = (index plan: (PBTerm path: 'k' op: '>=' value: 2)) execute.
    unweighted class. RankCase weightsOf: (old empty build: (old orderedPlan: (PBKeySpec path: 'k') descending: false) execute) }
  equals: { PBKeyNode. false. nil. true. true. PBKeyNode. nil }.

"test_sorted_and_filtered_index_plans_window_by_rank, and the scans, Limits and Filters that
 window by rank"
fails := OrderedCollection new.
1 to: seeds do: [:s | | list dict |
  case := RankCase seed: 2000 + s fails: fails.
  elements := case elements.
  index := (PBRangeIndex name: 'i' path: 'k') build: elements.
  case terms do: [:term |
    #(false true) do: [:d | | sorted filtered |
      sortKey := PBSortKey key: 'k' descending: d.
      sorted := PBSort source: (index plan: term) keys: { sortKey }.
      case checkPlan: sorted label: 'sort ' , term printString , ' ' , d printString.
      filtered := PBFilter source: (index orderedPlan: (PBKeySpec path: 'k') descending: d) terms: { term }.
      case checkPlan: filtered label: 'filter ' , term printString , ' ' , d printString.
      case checkPlan: (PBLimit source: filtered limit: (case between: 0 and: 6) offset: (case between: 0 and: 6))
        label: 'limit over filter ' , term printString]].
  "An 'in' sorted by the index key sorts its operands' groups, none for no operand (Task 10 soak,
   seed 25)."
  #(#() #(3 1)) do: [:operands | #(false true) do: [:d |
    case checkPlan: (PBSort source: (index plan: (PBTerm path: 'k' op: 'in' value: operands)) keys: { PBSortKey key: 'k' descending: d })
      label: 'sort in ' , operands printString , ' ' , d printString]].
  plan := index plan: (PBTerm path: 'k' op: '>' value: 0).
  ({ PBSort source: plan keys: { PBSortKey key: 'tag' descending: false }.
     PBSort source: plan keys: { PBSortKey key: 'k' descending: false. PBSortKey key: 'tag' descending: false }.
     PBSort source: plan keys: { PBSortKey key: [:e | e at: 'k' ifAbsent: [nil]] descending: false }.
     PBFilter source: (index orderedPlan: (PBKeySpec path: 'k') descending: false) terms: { PBTerm path: 'tag' op: '==' value: 1 }.
     PBFilter source: (index orderedPlan: (PBKeySpec path: 'k') descending: false) terms: { PBTerm path: 'k' op: '>' value: 0. PBTerm path: 'k' op: '<' value: 3 } }
    anySatisfy: [:p | p byRank]) ifTrue: [fails add: 'rank offered where proto_db offers none'].
  list := PBList new extend: elements.
  dict := PBDictionary new.
  elements doWithIndex: [:e :j | dict := dict setAt: (case between: 0 and: 60) value: e].
  case checkPlan: list asQueryPlan label: 'list scan'.
  case checkPlan: dict asQueryPlan label: 'dictionary scan'.
  case checkPlan: (PBLimit source: list asQueryPlan limit: (case between: 0 and: 10) offset: (case between: 0 and: 10)) label: 'limit over a list'.
  case checkPlan: (PBLimit source: dict asQueryPlan limit: nil offset: (case between: 0 and: 10)) label: 'limit over a dictionary'.
  case checkPlan: (PBLimit source: (index orderedPlan: (PBKeySpec path: 'k') descending: true) limit: (case between: 0 and: 10)
    offset: (case between: 0 and: 10)) label: 'limit over an ordered scan'.
  ({ PBSet new. PBHashDictionary new. PBCountedSet new } anySatisfy: [:each | each asQueryPlan byRank]) ifTrue: [
    fails add: 'a hash scan offers rank access']].
c that: 'sorts by the index key, one-term filters over its ordered scan, list and dictionary scans and Limits window by rank'
  is: fails asArray equals: #().

c report displayNl.

"EXPECT: 17 indexes ok (24 checks)"
"Lesson 17: indexes.
 Tutorial chapter: docs/tutorial/17-indexes.md

 What it teaches:
 - a walk visits every element, whatever the answer;
 - a hand-kept lookup collection (chapter 4) is only as good as every writer's memory: a writer
   that does not know it leaves it stale, and nothing says so;
 - an index is part of the collection version: addIndex: answers a new version, and every
   mutator, merges included, answers content and indexes computed in one step;
 - a snapshot taken before a change keeps its own indexes;
 - key specs: a path step through an absent attribute is MISSING, an explicit nil stays nil,
   and the presence tests (isNone, notNone) and ne: tell them apart as a scan does;
 - extractors: a named, registered, pure block; a name keeps its meaning; an extractor that
   fails during a merge fails only that commit, with the block's own exception passed through
   unchanged (ruling IQ1 as corrected, plan call IP2: exactly as proto_db).

 Run it (from examples/tutorial): STPATH=<repository>/src protost 17_indexes.st"
Import from: 'protobase'.
Import from: '_lesson'.

"The extractor's own error class: a commit that fails during a merge signals exactly this class,
 neither wrapped nor replaced (IQ1, IP2)."
Error subclass: #NamelessPerson.

| lesson dir space db cities walk tr people oslo before after inCity mine theirs contacts zip spec count nameless named |
lesson := Lesson named: '17 indexes'.
dir := FileSystem temp / ('pbst-tutorial-17-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'people'.

"600 people: four cities in turn, ages 18 to 77, fifty zip codes."
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
db newTransactionDo: [:t |
    | ps |
    ps := t newDictionary.
    0 to: 599 do: [:i |
        ps := ps setAt: i value: (t newObject: {
            'name' -> ('person' , i printString).
            'city' -> (cities at: i \\ 4 + 1).
            'age' -> (18 + (i \\ 60)).
            'address' -> (PBFrozenDict withAssociations: { 'zip' -> (1000 + (i \\ 50)) printString }) })].
    t setRootObject: 'people' value: ps].

"The walk: every element visited, whatever the answer."
walk := [:ps :city | | found |
    found := 0.
    ps do: [:p | (p at: 'city') = city ifTrue: [found := found + 1]].
    found].
lesson check: 'a walk finds the people in Oslo' is: (walk value: (db newTransaction getRootObject: 'people') value: 'Oslo') equals: 150.

"The hand-kept index of chapter 4, built once, in the same transaction as nothing else."
db newTransactionDo: [:t |
    | byCity |
    byCity := t newDictionary.
    (t getRootObject: 'people') keysAndValuesDo: [:id :p |
        byCity := byCity setAt: (p at: 'city') value: ((byCity getAt: (p at: 'city') default: PBSet new) add: id)].
    t setRootObject: 'byCity' value: byCity].
"A writer that knows nothing of byCity: a program written later, or the Python side."
db run: [:t |
    t setRootObject: 'people' value: ((t getRootObject: 'people')
        setAt: 600 value: (t newObject: { 'name' -> 'person600'. 'city' -> 'Oslo'. 'age' -> 40 }))].
tr := db newTransaction.
lesson check: 'the walk sees the new person' is: (walk value: (tr getRootObject: 'people') value: 'Oslo') equals: 151.
lesson check: 'the hand-kept index does not, and nothing said so'
    is: ((tr getRootObject: 'byCity') getAt: 'Oslo') count equals: 150.

"An index is part of the collection version."
db run: [:t |
    t setRootObject: 'people' value: (((t getRootObject: 'people')
        addIndex: (PBEqualityIndex name: 'by_city' path: 'city'))
        addIndex: (PBRangeIndex name: 'by_age' path: 'age'))].
people := db newTransaction getRootObject: 'people'.
lesson check: 'two indexes, part of the version' is: people indexNames equals: #('by_age' 'by_city').
oslo := (PBQuery from: people) where: ((PBField path: 'city') eq: 'Oslo').
lesson check: 'the index answers what the walk answered' is: oslo count equals: 151.
lesson check: 'and the planner used it' is: (oslo explain at: 'plan') equals: 'IndexLookup'.

"Every change keeps the indexes: there is no path that answers a stale one."
inCity := [:ps :city | ((PBQuery from: ps) where: ((PBField path: 'city') eq: city)) count].
before := db newTransaction.
db run: [:t | | ps |
    ps := t getRootObject: 'people'.
    ps := ps setAt: 0 value: ((ps getAt: 0) with: 'city' value: 'Oslo').
    ps := ps removeAt: 1.
    t setRootObject: 'people' value: ps].
after := db newTransaction getRootObject: 'people'.
lesson check: 'person 0 left Lima' is: (inCity value: after value: 'Lima') equals: 149.
lesson check: 'person 0 came to Oslo, person 1 left it' is: (inCity value: after value: 'Oslo') equals: 151.
lesson check: 'the snapshot taken before keeps its own index' is: (inCity value: (before getRootObject: 'people') value: 'Lima') equals: 150.
lesson check: 'validate: every index equals a scan'
    is: ([after validate. 'clean'] on: PBCorruptionError do: [:e | e messageText]) equals: 'clean'.

"Blind writes still merge onto an indexed root: the merge replays them through its mutators."
mine := db newTransaction.
theirs := db newTransaction.
mine setRootObject: 'people' value: (mine newDictionary
    setAt: 700 value: (mine newObject: { 'name' -> 'person700'. 'city' -> 'Oslo'. 'age' -> 30 })).
theirs setRootObject: 'people' value: (theirs newDictionary
    setAt: 701 value: (theirs newObject: { 'name' -> 'person701'. 'city' -> 'Oslo'. 'age' -> 31 })).
mine commit.
theirs commit.
after := db newTransaction getRootObject: 'people'.
lesson check: 'both blind writes merged, the index counts them' is: (inCity value: after value: 'Oslo') equals: 153.
lesson check: 'and the merged version keeps its indexes' is: after indexNames equals: #('by_age' 'by_city').

"Key specs: MISSING is not nil."
db run: [:t |
    t setRootObject: 'contacts' value: (((((t newList
        appendLast: (t newObject: { 'name' -> 'Ada'. 'address' -> (PBFrozenDict withAssociations: { 'zip' -> '1010' }) }))
        appendLast: (t newObject: { 'name' -> 'Bob'. 'address' -> (PBFrozenDict withAssociations: { 'zip' -> nil }) }))
        appendLast: (t newObject: { 'name' -> 'Cy'. 'address' -> (PBFrozenDict withAssociations: {}) }))
        appendLast: (t newObject: { 'name' -> 'Di' }))
        addIndex: (PBEqualityIndex name: 'by_zip' path: 'address.zip'))].
contacts := db newTransaction getRootObject: 'contacts'.
spec := PBKeySpec path: 'address.zip'.
lesson check: 'an explicit nil stays nil' is: (spec extract: (contacts getAt: 1)) equals: nil.
lesson check: 'an absent zip is MISSING' is: (spec extract: (contacts getAt: 2)) equals: PBMissing default.
lesson check: 'no address at all is MISSING too' is: (spec extract: (contacts getAt: 3)) equals: PBMissing default.
zip := PBField path: 'address.zip'.
count := [:predicate | ((PBQuery from: contacts) where: predicate) count].
lesson check: 'eq: nil finds the explicit nil only' is: (count value: (zip eq: nil)) equals: 1.
lesson check: 'isNone finds nil and MISSING' is: (count value: zip isNone) equals: 3.
lesson check: 'notNone finds the rest' is: (count value: zip notNone) equals: 1.
lesson check: 'ne: matches present keys only' is: (count value: (zip ne: '1010')) equals: 1.

"Extractors: a named block, registered in every process that changes the collection."
PBKeySpec registerExtractor: 'name_length' block: [:p | | n |
    n := p at: 'name'.
    n isNil ifTrue: [NamelessPerson signal: 'a person without a name'].
    n size] version: '1'.
db run: [:t |
    t setRootObject: 'people' value: ((t getRootObject: 'people')
        addIndex: (PBRangeIndex name: 'by_name_length' keySpec: (PBKeySpec extractor: 'name_length')))].
people := db newTransaction getRootObject: 'people'.
lesson check: 'names of nine characters, by the extractor index'
    is: ((PBQuery from: people) where: ((PBField extractor: 'name_length') eq: 9)) count equals: 503.
lesson check: 'a name keeps its meaning: rebinding it is refused'
    signals: PBValidationError containing: 'name_length'
    during: [PBKeySpec registerExtractor: 'name_length' block: [:p | (p at: 'name') size + 1] version: '1'].

"An extractor that fails during a merge fails that commit only, with its own exception (IQ1, IP2)."
nameless := db newTransaction.
named := db newTransaction.
nameless setRootObject: 'people' value: (nameless newDictionary setAt: 800 value: (nameless newObject: { 'city' -> 'Oslo' })).
named setRootObject: 'people' value: (named newDictionary setAt: 801 value: (named newObject: { 'name' -> 'person801'. 'city' -> 'Oslo' })).
lesson check: 'the commit whose merge ran the failing extractor fails with the block''s own error'
    signals: NamelessPerson containing: 'a person without a name' during: [nameless commit].
named commit.
people := db newTransaction getRootObject: 'people'.
lesson check: 'the other commit went through' isTrue: (people has: 801).
lesson check: 'and the failed one left nothing behind' isTrue: (people has: 800) not.

space close.
dir deleteAll.
lesson finish.

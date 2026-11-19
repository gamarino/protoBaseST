"_st_index_both.st: protoBaseST's side of tests/interop/index_both_directions.sh (indexed queries,
 plan Task 4b, spec 6.1.3). A helper: the runner never runs files whose name starts with _.

 Usage: protost _st_index_both.st make|change|check|content <directory>

 The same steps as tests/interop/py_index_both.py, whose docstring states them (the records, the
 index definitions, the roots make writes, the mutators, index definitions and merges change
 runs, and the content lines), in protoBaseST. check runs validate on every root (its structure
 and every index against the elements), then, for every index and every orderable key among the
 elements, compares countOfKey: with the occurrences a scan of the elements finds under that key
 (order keys compared, so 1, 1.0 and Decimal 1 are one key); it prints one summary line per root.
 Any failure is an error (a non-zero exit)."
Import from: 'protobase'.

| mode dir extractor record definitions withIndexes space db tr roots find eqw r a b n key okey sorted render |
mode := Smalltalk arguments first.
dir := Smalltalk arguments at: 2.
extractor := 'interop.both.w'.
PBKeySpec registerExtractor: extractor block: [:e | (PBKeySpec path: 'w') extract: e] version: '1'.
roots := #('list' 'dict' 'hash' 'set' 'bag').
record := [:i | | fields |
  fields := OrderedCollection new.
  fields addLast: 'n' -> i; addLast: 'w' -> (i \\ 4).
  i \\ 4 = 0 ifTrue: [fields addLast: 'v' -> (i \\ 5)].
  i \\ 4 = 1 ifTrue: [fields addLast: 'v' -> ('s' , (i \\ 3) printString)].
  i \\ 4 = 2 ifTrue: [fields addLast: 'v' -> nil].
  PBObject withAll: fields asArray].
definitions := [{ PBEqualityIndex name: 'eq_v' path: 'v'. PBRangeIndex name: 'rg_w' keySpec: (PBKeySpec extractor: extractor).
  PBRangeIndex name: 'rg_n' path: 'n' }].
withIndexes := [:coll | definitions value inject: coll into: [:acc :index | acc addIndex: index]].
n := [:e | (PBKeySpec path: 'n') extract: e].
find := [:coll :i | coll elements detect: [:e | (n value: e) = i] ifNone: [Error signal: 'no element with n ' , i printString]].
okey := [:k | PBMemberKeys orderKeyOrNil: k].
"anArray of Integers, or of pairs of Integers, sorted (pairs lexicographically), as Python sorts them."
sorted := [:anArray | (anArray asSortedCollection: [:x :y |
  x isArray
    ifTrue: [(x at: 1) < (y at: 1) or: [(x at: 1) = (y at: 1) and: [(x at: 2) <= (y at: 2)]]]
    ifFalse: [x <= y]]) asArray].
"py_index_both.py's notation of a list of Integers or of pairs of them."
render := [:anArray | | out |
  out := WriteStream on: String new.
  out nextPut: $[.
  anArray doWithIndex: [:each :i |
    i > 1 ifTrue: [out nextPutAll: ', '].
    each isArray
      ifTrue: [out nextPut: $(; print: (each at: 1); nextPutAll: ', '; print: (each at: 2); nextPut: $)]
      ifFalse: [out print: each]].
  out nextPut: $].
  out contents].

space := PBObjectSpace storage: (PBFileStorage path: dir).
mode = 'make' ifTrue: [
  db := space newDatabase: 'both'.
  db newTransactionDo: [:t | | lst d h s bag |
    lst := t newList. d := t newDictionary. h := t newHashDictionary. s := t newSet. bag := t newCountedSet.
    0 to: 19 do: [:i | | x |
      x := record value: i.
      lst := lst appendLast: x.
      d := d setAt: i value: x.
      h := h setAt: i value: x.
      s := s add: x.
      bag := bag add: x.
      i \\ 2 = 0 ifTrue: [bag := bag add: x]].
    roots with: { lst. d. h. s. bag } do: [:name :coll | t setRootObject: name value: (withIndexes value: coll)]]].

mode = 'change' ifTrue: [
  db := space openDatabase: 'both'.
  r := Dictionary new.
  20 to: 39 do: [:i | r at: i put: (record value: i)].
  eqw := PBEqualityIndex name: 'eq_w' path: 'w'.
  db newTransactionDo: [:t | | lst d s bag |
    lst := t getRootObject: 'list'.
    lst := ((((lst insertAt: 2 value: (r at: 20)) appendFirst: (r at: 21)) appendLast: (r at: 22)) setAt: 5 value: (r at: 23)) removeAt: 7.
    lst := ((((lst extend: { r at: 24. r at: 25 }) sliceFrom: 1 to: 21) head: 19) tail: 2).
    t setRootObject: 'list' value: ((lst addIndex: eqw) removeIndex: 'rg_n').
    #('dict' 'hash') do: [:name |
      d := t getRootObject: name.
      d := (((d setAt: 20 value: (r at: 26)) setAt: 3 value: (r at: 27)) removeAt: 4) removeAt: 99.
      t setRootObject: name value: ((d addIndex: eqw) removeIndex: 'rg_n')].
    s := t getRootObject: 'set'.
    s := ((((s add: (r at: 28)) add: (find value: s value: 3)) remove: (find value: s value: 5)) remove: (r at: 39))
      union: { r at: 29. r at: 30 }.
    s := (s intersection: (s elements reject: [:e | (n value: e) = 6])) difference: { r at: 29 }.
    t setRootObject: 'set' value: ((s addIndex: eqw) removeIndex: 'rg_n').
    bag := t getRootObject: 'bag'.
    bag := (((bag add: (r at: 31)) add: (find value: bag value: 2)) remove: (find value: bag value: 4)) remove: (find value: bag value: 1).
    t setRootObject: 'bag' value: ((bag addIndex: eqw) removeIndex: 'rg_n')].
  a := db newTransaction.
  b := db newTransaction.
  a setRootObject: 'dict' value: (a newDictionary setAt: 40 value: (r at: 32)).
  b setRootObject: 'dict' value: (((b newDictionary setAt: 41 value: (r at: 33)) removeAt: 20)
    addIndex: (PBEqualityIndex name: 'eq_v2' path: 'v')).
  a setRootObject: 'hash' value: (a newHashDictionary setAt: 40 value: (r at: 32)).
  b setRootObject: 'hash' value: ((b newHashDictionary setAt: 41 value: (r at: 33)) removeAt: 3).
  a setRootObject: 'set' value: (a newSet add: (r at: 34)).
  b setRootObject: 'set' value: ((b newSet add: (r at: 35)) remove: (r at: 28)).
  a setRootObject: 'bag' value: ((a newCountedSet add: (r at: 36)) add: (r at: 36)).
  b setRootObject: 'bag' value: ((b newCountedSet add: (r at: 37)) remove: (r at: 31)).
  b commit.
  a commit].

mode = 'check' ifTrue: [
  tr := (space openDatabase: 'both') newTransaction.
  roots do: [:name | | coll elements lookups |
    coll := tr getRootObject: name.
    coll validate.
    elements := coll elements.
    lookups := 0.
    coll indexNames do: [:indexName | | index spec keys |
      index := coll getIndex: indexName.
      spec := index keySpecObject.
      keys := OrderedCollection new.
      elements do: [:e | | k |
        k := spec extract: e.
        ((okey value: k) notNil and: [(keys anySatisfy: [:x | ((okey value: x) compareWith: (okey value: k)) = 0]) not])
          ifTrue: [keys addLast: k]].
      keys do: [:k | | scanned |
        scanned := elements count: [:e | | ek |
          ek := spec extract: e.
          (okey value: ek) notNil and: [((okey value: ek) compareWith: (okey value: k)) = 0]].
        (index countOfKey: k) = scanned ifFalse: [
          ^ Error signal: name , '.' , indexName , ': countOfKey: ' , k printString , ' answers '
            , (index countOfKey: k) printString , ', a scan finds ' , scanned printString].
        lookups := lookups + 1]].
    ('checked ' , name , ': ' , coll count printString , ' elements, indexes '
      , (coll indexNames inject: '' into: [:acc :x | acc isEmpty ifTrue: [x] ifFalse: [acc , ',' , x]])
      , ', ' , lookups printString , ' key counts equal to scans') displayNl].
  tr abort].

mode = 'content' ifTrue: [
  tr := (space openDatabase: 'both') newTransaction.
  roots do: [:name | | coll items |
    coll := tr getRootObject: name.
    items := ((coll isKindOf: PBDictionary) or: [coll isKindOf: PBHashDictionary])
      ifTrue: [sorted value: (coll items collect: [:as | { as key. n value: as value } ])]
      ifFalse: [
        (coll isKindOf: PBCountedSet)
          ifTrue: [sorted value: (coll items collect: [:as | { n value: as key. as value } ])]
          ifFalse: [
            (coll isKindOf: PBList)
              ifTrue: [coll elements collect: [:e | n value: e]]
              ifFalse: [sorted value: (coll elements collect: [:e | n value: e])]]].
    (name , ' ' , (coll class typeName subStrings: '.') last , ' count=' , coll count printString , ' indexes='
      , (coll indexNames inject: '' into: [:acc :x | acc isEmpty ifTrue: [x] ifFalse: [acc , ',' , x]])
      , ' ' , (render value: items)) displayNl].
  tr abort].
space close.

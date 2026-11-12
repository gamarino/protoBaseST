"EXPECT: ok 36"
"PBCountedSet writes (plan Task 22; ProtoBase v2.0.0rc2 proto_db/collections/sets.py,
 CountedSet). A counted set is a keyed tree from the hash key of an element (PBKeys hashKey:)
 to a bucket, a tuple of (element, count) tuples with count >= 1 (format spec, 'Collections');
 count is the number of distinct elements and total_count the sum of the counts. add: adds
 one occurrence (a new element goes at the end of its bucket; a present one keeps its stored
 object and its place), remove: removes one (the last one takes the entry out, and an
 emptied bucket leaves the tree; an absent element is a new version with the same content).
 Elements go by order key: 1, 1.0 and Decimal 1.00 are one element, true another. Each call
 logs its intent, ('add' e) or ('remove' e), with the canonical element, a blind call
 included. An element whose (element, count) entry in its bucket tuple would nest deeper than
 MAX_VALUE_DEPTH is refused at add: (ELEMENT_WRAPPING 4: 1018 at most), and remove: does not
 check the wrapping, as ProtoBase's remove (canonical_for only). The answers are ProtoBase's
 for the same calls. A committed counted set reads back from storage with its counts."
Import from: 'protobase'.
Import from: '_check'.

| c empty a b gone same bucketOf tuples deep kinds base space db read |
c := Check new.
kinds := [:aColl | (aColl opLog asArray collect: [:op | (op at: 1) , ' ' , (op at: 2) printString]) asArray].
bucketOf := [:aSet :anElement | | node |
  node := PBAvl keyAt: (aSet stateAt: 'root') key: (PBKeys hashKey: anElement).
  node isNil ifTrue: [nil] ifFalse: [node value]].
empty := PBCountedSet new.
c that: 'a new counted set is empty' is: empty count equals: 0.
c that: 'with a total count of 0' is: empty totalCount equals: 0.
c that: 'its fields in ProtoBase''s order' is: empty state keys equals: #('indexes' 'count' 'root' 'total_count').

a := ((empty add: 1) add: 1.0) add: true.
c that: 'two distinct elements (1 and 1.0 are one, true another)' is: a count equals: 2.
c that: 'three occurrences' is: a totalCount equals: 3.
c that: 'countOf: 1' is: (a countOf: 1) equals: 2.
c that: 'countOf: Decimal 1.00' is: (a countOf: (Decimal fromString: '1.00')) equals: 2.
c that: 'countOf: true' is: (a countOf: true) equals: 1.
c that: 'the bucket of 1 holds the pair (1, 2)' is: (bucketOf value: a value: 1)
  equals: (PBTuple withAll: { PBTuple withAll: #(1 2) }).
c that: 'the stored element object is kept' is: (a items detect: [:each | each value = 2]) key class equals: SmallInteger.
c that: 'each call logs its intent' is: (kinds value: a) equals: #('add 1' 'add 1.0' 'add true').
c that: 'the receiver is unchanged' is: empty totalCount equals: 0.
c that: 'a new oid' isTrue: a oid ~= empty oid.
c that: 'a new one is mergeable' is: a isMergeable equals: true.

b := a remove: 1.
c that: 'remove: takes one occurrence' is: (b countOf: 1) equals: 1.
c that: 'the distinct count stays' is: b count equals: 2.
c that: 'the total count drops' is: b totalCount equals: 2.
c that: 'the pair is (1, 1)' is: (bucketOf value: b value: 1) equals: (PBTuple withAll: { PBTuple withAll: #(1 1) }).
gone := b remove: (Decimal fromString: '1').
c that: 'the last occurrence takes the element out' is: (gone has: 1) equals: false.
c that: 'one distinct element left' is: gone count equals: 1.
c that: 'one occurrence left' is: gone totalCount equals: 1.
c that: 'an emptied bucket leaves the tree' is: (bucketOf value: gone value: 1) equals: nil.
c that: 'a still holds two occurrences' is: (a countOf: 1) equals: 2.
same := gone remove: 'absent'.
c that: 'remove: of an absent element: a new version' isTrue: same ~~ gone.
c that: 'with the same tree' isTrue: (same stateAt: 'root') == (gone stateAt: 'root').
c that: 'and the same counts' is: { same count. same totalCount } equals: #(1 1).
c that: 'logged all the same' is: (kinds value: same) last equals: 'remove ''absent'''.
c that: 'a list is not an orderable element' signals: PBValidationError during: [empty add: #(1 2)].
c that: 'nor a NaN' signals: PBValidationError during: [empty add: Float nan].
c that: 'remove: of a NaN' signals: PBValidationError during: [a remove: Float nan].

"The nesting limit (plan Task 17b): the (element, count) entry in its bucket tuple adds 4."
tuples := [:n | | v | v := 1. n timesRepeat: [v := PBTuple withAll: { v }]. v].
deep := PBCountedSet new add: (tuples value: 509).
c that: 'an element of 509 tuples (1018)' is: deep count equals: 1.
c that: 'its bucket node value is 1022 deep' is: (PBCodec valueDepth: (deep stateAt: 'root') value) equals: 1022.
c that: 'an element of 510 tuples (1020)' signals: PBValidationError
  containing: 'PBCountedSet element nests 1020 MessagePack containers deep, and its bucket entry (element, count) in its bucket tuple adds 4 around it, so it may nest at most 1018 (MAX_VALUE_DEPTH = 1022, format spec "Value nesting depth")'
  during: [PBCountedSet new add: (tuples value: 510)].
c that: 'remove: does not check the wrapping (ProtoBase canonical_for)' is: (PBCountedSet new remove: (tuples value: 510)) count equals: 0.

"Written and read back."
base := FileSystem temp / ('pbst-counted-set-ops-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
space := PBObjectSpace storage: (PBFileStorage path: (base / 'space') pathString).
db := space newDatabase: 'cs'.
db newTransactionDo: [:t | t setRootObject: 'bag' value: ((((t newCountedSet add: 'e') add: 'e') add: 'f') add: 2)].
space close.
space := PBObjectSpace storage: (PBFileStorage path: (base / 'space') pathString).
db := space openDatabase: 'cs'.
db newTransactionDo: [:t | read := t getRootObject: 'bag'].
c that: 'the committed counts read back' is: { read countOf: 'e'. read countOf: 'f'. read countOf: 2. read count. read totalCount }
  equals: #(2 1 1 3 4).
c that: 'its tree is valid' isTrue: [PBAvl check: (read stateAt: 'root'). true] value.
space close.
base deleteAll.
c report displayNl.

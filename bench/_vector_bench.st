"_vector_bench.st: the data, the indexes and the checksums the vector maintenance workloads VB3 and
 VB5 share (Addendum V 5.5; vectors phase task V5), used by bench/vector_workload.st (standalone)
 and bench/cluster_workload.st (VB5 in a cluster). bench/py_vector_workload.py is the proto_db side
 and computes the same values with the same formulas. A helper: nothing here runs on import.

  VectorBench vectorsFrom: aPath n: n dim: d
                       the 'vectors' of the data file aPath (bench/py_vector_data.py), each a
                       PBTuple of d Floats; the file must hold n vectors of dim d
  VectorBench indexesOf: aPlan dim: d
                       the indexes of a plan, each on the element (VB3) or on the value (VB5:
                       a dictionary's elements are its values) of dim d with metric l2: none
                       nothing; exact the index 'near', exact backend; ivf the index 'near',
                       ivf_flat with nlist 16, train_iters 10, seed 51 and retrain_growth 1.03, so
                       that a few hundred adds cross its retrain threshold again and again
  VectorBench list: vectors plan: aPlan dim: d
                       VB3's start: a PBList of the vectors, then the plan's index added (build:,
                       an IVF index trained on them)
  VectorBench dictionary: vectors plan: aPlan dim: d
                       VB5's start: a PBDictionary from i to vector i (0-based), then the index
  VectorBench checksumOf: aCollection keyed: aBoolean centroids: aCentroidsBoolean
                       zlib's CRC-32 of a byte string: every element in the collection's order
                       (for a dictionary, keyed true, the key then the value, in key order) as
                       IEEE 754 binary64 big-endian numbers, a key as one Float; then per index,
                       by name, its member count, invalid count, trained size and centroid count
                       as Floats, and, centroids true, every centroid component. VB3 includes the
                       centroids (its commits are serial: proto_db's pure-Python k-means is
                       reproduced bit for bit, DV3); VB5 does not, because a cluster's commit order
                       decides which members a retrain sees, and the checksum must not depend on
                       that order (the counts, the trained size included, do not).
  VectorBench queriesFrom: aPath dim: d, records: vectors, search: anIndex query: q k: k,
  answersChecksum: answers
                       VB1's and VB2's (task V6): the data file's query points, the records
                       { 'i'. 'vec' } of the vectors, the positions answering a near(k) search
                       (a PBVectorSearch), and the CRC-32 of answers' positions as Floats."

Object subclass: #VectorBench.

"The 'queries' of the data file aPath (bench/py_vector_data.py), each a PBTuple of d Floats."
VectorBench class >> queriesFrom: aPath dim: d
  | queries |
  queries := ((MessagePack decode: aPath asFileReference binaryContents) at: 'queries') collect: [:q | PBTuple withAll: q].
  (queries allSatisfy: [:q | q size = d]) ifFalse: [Error signal: 'vector bench: ' , aPath , ' holds queries of another dim than ' , d printString].
  ^ queries.

"VB1's and VB2's elements: a record { 'i' -> position from 0. 'vec' -> vector } per vector."
VectorBench class >> records: vectors
  ^ (1 to: vectors size) asArray collect: [:i | PBObject withAll: { 'i' -> (i - 1). 'vec' -> (vectors at: i) }].

"The 'i' of the k nearest records to aQuery: a PBVectorSearch over anIndex's plan (the planner's
 near[] rules are task V7's; proto_db's plan for near(k) on an indexed collection is this one)."
VectorBench class >> search: anIndex query: aQuery k: k
  ^ (PBVectorSearch index: anIndex term: (PBTerm path: 'vec' op: 'near[]' value: (PBNearQuery vector: aQuery k: k)) where: nil)
    execute collect: [:e | e at: 'i'].

"zlib's CRC-32 of every answer's positions, in order, as IEEE 754 binary64 big-endian numbers."
VectorBench class >> answersChecksum: anAnswers
  | w |
  w := WriteStream on: ByteArray new.
  anAnswers do: [:answer | answer do: [:i | w nextPutFloat64: i asFloat bigEndian: true]].
  ^ w contents crc32.

VectorBench class >> vectorsFrom: aPath n: n dim: d
  | data |
  data := MessagePack decode: aPath asFileReference binaryContents.
  ((data at: 'n') = n and: [(data at: 'dim') = d]) ifFalse: [
    Error signal: 'vector bench: ' , aPath , ' holds ' , (data at: 'n') printString , ' vectors of dim '
      , (data at: 'dim') printString , ', not ' , n printString , ' of dim ' , d printString].
  ^ (data at: 'vectors') collect: [:v | PBTuple withAll: v].

VectorBench class >> indexesOf: aPlan dim: d
  aPlan = 'none' ifTrue: [^ #()].
  aPlan = 'exact' ifTrue: [
    ^ { PBVectorIndex name: 'near' keySpec: PBKeySpec element dim: d metric: 'l2' backend: 'exact' params: nil }].
  aPlan = 'ivf' ifTrue: [
    ^ { PBVectorIndex name: 'near' keySpec: PBKeySpec element dim: d metric: 'l2' backend: 'ivf_flat'
        params: (Dictionary new at: 'nlist' put: 16; at: 'train_iters' put: 10; at: 'seed' put: 51;
          at: 'retrain_growth' put: 1.03; yourself) }].
  ^ Error signal: 'vector bench: unknown plan ' , aPlan printString.

VectorBench class >> list: vectors plan: aPlan dim: d
  | list |
  list := PBList new extend: vectors.
  (self indexesOf: aPlan dim: d) do: [:index | list := list addIndex: index].
  ^ list.

VectorBench class >> dictionary: vectors plan: aPlan dim: d
  | dict |
  dict := PBDictionary new.
  1 to: vectors size do: [:i | dict := dict setAt: i - 1 value: (vectors at: i)].
  (self indexesOf: aPlan dim: d) do: [:index | dict := dict addIndex: index].
  ^ dict.

VectorBench class >> checksumOf: aCollection keyed: aBoolean centroids: aCentroidsBoolean
  | w put |
  w := WriteStream on: ByteArray new.
  put := [:x | w nextPutFloat64: x asFloat bigEndian: true].
  aBoolean
    ifTrue: [aCollection keysAndValuesDo: [:k :v | put value: k. v do: put]]
    ifFalse: [aCollection do: [:v | v do: put]].
  aCollection indexNames asSortedCollection do: [:name | | index |
    index := aCollection getIndex: name.
    put value: index memberCount.
    put value: index invalidCount.
    put value: index trainedSize.
    put value: index centroids size.
    aCentroidsBoolean ifTrue: [index centroids do: [:c | c do: put]]].
  ^ w contents crc32.

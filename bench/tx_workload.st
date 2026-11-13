"tx_workload.st: committed transactions per second of protoBaseST on PBFileStorage.
 py_tx_workload.py runs the same transactions in ProtoBase; run_tx.sh runs both and prints the
 commits per second.

 Every profile runs in a new directory under $TX_DIR (a space whose database 'bench' gets its roots
 from one untimed transaction), commits a fixed number of transactions through PBDatabase run:
 (durability is always fsync), closes the space, and verifies the result on a new space over the
 same directory: the read-back proves every committed transaction is there.

   tiny          each transaction reads the root Dictionary 'kv', sets one new key (i -> i \\ 1000)
                 and writes it back
   small-record  100 records (PBObject: name balance hits stamp) in the root Dictionary 'records';
                 transaction i reads record i \\ 100, sets balance + i, hits + 1, stamp i, and
                 writes it back into the Dictionary
   batch-100     each transaction reads 'kv', inserts 100 new keys (k -> k \\ 97), writes it back
   conc-<mode>-<N>  N actors (TxWriter asActor) share one PBDatabase and commit CONC tiny
                 transactions in all, CONC / N each, through run:retries: 1000:
                   disjoint  writer w reads and writes its own root 'kv-w'
                   merge     every writer blindly writes a one-key PBDictionary to the shared root
                             'shared' (never read: merged at commit, rebaseOnto:)
                   hot       every writer increments key 0 of the shared root 'hot' (read-modify-
                             write: conflicts, retried)

 Each profile prints one line, tab-separated:
   op <profile> <transactions> <seconds> <retries> <checksum>
 seconds is the wall time of the transactions only (not the setup, close or read-back); retries
 is the block runs beyond one per transaction. The checksum is '<count>:<sum of key * value>' (for
 small-record '<records>:<sum of balances>:<sum of hits>:<sum of stamps>', for hot '1:<counter>'),
 computed from the read-back and compared here with the expected value: a wrong result, or a
 retry where none can happen (one writer; disjoint roots; blind writes), signals an Error and the
 run exits non-zero. The last line is 'tx_workload ok'.

 Usage: TX_DIR=<empty directory> [TX_SCALE=n] protost tx_workload.st"
Import from: 'protobase'.

"One writer of the conc profiles, driven as an actor: it waits only on the publisher (ruling R19)."
Object subclass: #TxWriter instanceVariableNames: 'attempts'.

"Commits each transactions of aMode as writer w through aDb; answers the block runs."
TxWriter >> run: aMode writer: w each: each db: aDb
  attempts := 0.
  1 to: each do: [:i | | key |
    key := w * each + i.
    aDb run: [:tr | | d |
      attempts := attempts + 1.
      aMode = 'disjoint' ifTrue: [
        d := tr getRootObject: 'kv-' , w printString.
        tr setRootObject: 'kv-' , w printString value: (d setAt: key value: key \\ 1000)].
      aMode = 'merge' ifTrue: [
        tr setRootObject: 'shared' value: (tr newDictionary setAt: key value: key \\ 1000)].
      aMode = 'hot' ifTrue: [
        d := tr getRootObject: 'hot'.
        tr setRootObject: 'hot' value: (d setAt: 0 value: (d getAt: 0) + 1)]]
      retries: 1000].
  ^ attempts.

| scale base tiny small batch conc nRecords batchKeys report openSpace setup dictSum readback
  timedRun setKey space db r want n stamps |
scale := ((Smalltalk getenv: 'TX_SCALE') ifNil: ['1']) asNumber.
base := Smalltalk getenv: 'TX_DIR'.
base isNil ifTrue: [Error signal: 'TX_DIR is not set'].
tiny := 100 * scale. small := 100 * scale. batch := 10 * scale. conc := 120 * scale.
nRecords := 100. batchKeys := 100.

report := [:name :txns :micros :retries :checksum :expected |
  checksum = expected ifFalse: [Error signal: name , ': checksum ' , checksum , ', expected ' , expected].
  ('op' , (String with: Character tab) , name , (String with: Character tab) , txns printString
    , (String with: Character tab) , (micros / 1000000) asFloat printString
    , (String with: Character tab) , retries printString
    , (String with: Character tab) , checksum) displayNl].
openSpace := [:name | PBObjectSpace storage: (PBFileStorage path: (base asFileReference / name) pathString)].
"A new space with database 'bench' whose roots (an Array of name -> one-argument block of the
 transaction) are set by one untimed transaction; answers {space. db}."
setup := [:name :roots | | sp d |
  sp := openSpace value: name.
  d := sp newDatabase: 'bench'.
  d newTransactionDo: [:tr | roots do: [:each | tr setRootObject: each key value: (each value value: tr)]].
  {sp. d}].
dictSum := [:d | | c s |
  c := 0. s := 0.
  d keysAndValuesDo: [:k :v | c := c + 1. s := s + (k * v)].
  c printString , ':' , s printString].
readback := [:name :aBlock | | sp |
  sp := openSpace value: name.
  [aBlock value: (sp openDatabase: 'bench') newTransaction] ensure: [sp close]].
"Runs count transactions through aDb run:, aBlock value: tr value: i for i in 1..count;
 answers {microseconds. retries}."
timedRun := [:aDb :count :aBlock | | attempts t0 us |
  attempts := 0.
  t0 := Time microsecondClockValue.
  1 to: count do: [:i | aDb run: [:tr | attempts := attempts + 1. aBlock value: tr value: i]].
  us := Time microsecondClockValue - t0.
  {us. attempts - count}].
setKey := [:tr :root :key :value |
  tr setRootObject: root value: ((tr getRootObject: root) setAt: key value: value)].

"tiny"
r := setup value: 'tiny' value: {'kv' -> [:tr | tr newDictionary]}.
space := r first. db := r last.
[r := timedRun value: db value: tiny value: [:tr :i | setKey value: tr value: 'kv' value: i value: i \\ 1000]]
  ensure: [space close].
want := tiny printString , ':' , ((1 to: tiny) inject: 0 into: [:a :i | a + (i * (i \\ 1000))]) printString.
report value: 'tiny' value: tiny value: r first value: r last
  value: (readback value: 'tiny' value: [:tr | dictSum value: (tr getRootObject: 'kv')]) value: want.
r last = 0 ifFalse: [Error signal: 'tiny: a single writer retried'].

"small-record"
r := setup value: 'small' value: {'records' -> [:tr | | d |
  d := tr newDictionary.
  0 to: nRecords - 1 do: [:k |
    d := d setAt: k value: (tr newObject: {'name' -> ('account ' , k printString). 'balance' -> 0. 'hits' -> 0. 'stamp' -> 0})].
  d]}.
space := r first. db := r last.
[r := timedRun value: db value: small value: [:tr :i | | recs rec |
  recs := tr getRootObject: 'records'.
  rec := recs getAt: i \\ nRecords.
  rec := rec withAll: {'balance' -> ((rec at: 'balance') + i). 'hits' -> ((rec at: 'hits') + 1). 'stamp' -> i}.
  tr setRootObject: 'records' value: (recs setAt: i \\ nRecords value: rec)]]
  ensure: [space close].
"The last stamp of record k is the largest i <= small with i \\ nRecords = k (0 if none)."
stamps := (0 to: nRecords - 1) inject: 0 into: [:a :k |
  a + ((1 to: small) inject: 0 into: [:m :i | i \\ nRecords = k ifTrue: [m max: i] ifFalse: [m]])].
want := nRecords printString , ':' , (small * (small + 1) // 2) printString , ':' , small printString , ':' , stamps printString.
report value: 'small-record' value: small value: r first value: r last
  value: (readback value: 'small' value: [:tr | | c bal hits st |
    c := 0. bal := 0. hits := 0. st := 0.
    (tr getRootObject: 'records') keysAndValuesDo: [:k :rec |
      c := c + 1. bal := bal + (rec at: 'balance'). hits := hits + (rec at: 'hits'). st := st + (rec at: 'stamp')].
    c printString , ':' , bal printString , ':' , hits printString , ':' , st printString])
  value: want.
r last = 0 ifFalse: [Error signal: 'small-record: a single writer retried'].

"batch-100"
r := setup value: 'batch' value: {'kv' -> [:tr | tr newDictionary]}.
space := r first. db := r last.
[r := timedRun value: db value: batch value: [:tr :i | | d |
  d := tr getRootObject: 'kv'.
  (i - 1) * batchKeys + 1 to: i * batchKeys do: [:k | d := d setAt: k value: k \\ 97].
  tr setRootObject: 'kv' value: d]]
  ensure: [space close].
n := batch * batchKeys.
want := n printString , ':' , ((1 to: n) inject: 0 into: [:a :k | a + (k * (k \\ 97))]) printString.
report value: 'batch-100' value: batch value: r first value: r last
  value: (readback value: 'batch' value: [:tr | dictSum value: (tr getRootObject: 'kv')]) value: want.
r last = 0 ifFalse: [Error signal: 'batch-100: a single writer retried'].

"conc-<mode>-<N>"
#('disjoint' 'merge' 'hot') do: [:mode |
  #(1 2 4) do: [:writers | | each name roots actors futures t0 us total retries check |
    each := conc // writers.
    total := each * writers.
    name := mode , '-' , writers printString.
    roots := OrderedCollection new.
    roots add: 'shared' -> [:tr | tr newDictionary]; add: 'hot' -> [:tr | tr newDictionary setAt: 0 value: 0].
    0 to: writers - 1 do: [:w | roots add: ('kv-' , w printString) -> [:tr | tr newDictionary]].
    r := setup value: name value: roots asArray.
    space := r first. db := r last.
    [actors := (1 to: writers) collect: [:w | TxWriter new asActor].
     t0 := Time microsecondClockValue.
     futures := (1 to: writers) collect: [:w | (actors at: w) run: mode writer: w - 1 each: each db: db].
     retries := (futures inject: 0 into: [:a :f | a + f wait]) - total.
     us := Time microsecondClockValue - t0]
      ensure: [space close].
    check := readback value: name value: [:tr |
      mode = 'disjoint'
        ifTrue: [| c s |
          c := 0. s := 0.
          0 to: writers - 1 do: [:w |
            (tr getRootObject: 'kv-' , w printString) keysAndValuesDo: [:k :v | c := c + 1. s := s + (k * v)]].
          c printString , ':' , s printString]
        ifFalse: [mode = 'merge'
          ifTrue: [dictSum value: (tr getRootObject: 'shared')]
          ifFalse: ['1:' , ((tr getRootObject: 'hot') getAt: 0) printString]]].
    want := mode = 'hot'
      ifTrue: ['1:' , total printString]
      ifFalse: [total printString , ':' , ((1 to: total) inject: 0 into: [:a :k | a + (k * (k \\ 1000))]) printString].
    report value: 'conc-' , name value: total value: us value: retries value: check value: want.
    (mode ~= 'hot' and: [retries ~= 0]) ifTrue: [Error signal: 'conc-' , name , ': disjoint writers retried']]].

'tx_workload ok' displayNl.

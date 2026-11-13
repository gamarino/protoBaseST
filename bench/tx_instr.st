"tx_instr.st: runs PROFILE (tiny, small-record or batch-100, as tx_workload.st) for N
 transactions in a new space under TX_DIR, and nothing else, so that run_tx_instr.sh can take
 the instructions of one transaction as the difference of two runs (setup cancels).
 Usage: TX_DIR=<dir> PROFILE=<name> N=<n> protost tx_instr.st"
Import from: 'protobase'.
| profile n space db |
profile := Smalltalk getenv: 'PROFILE'.
n := (Smalltalk getenv: 'N') asNumber.
space := PBObjectSpace storage: (PBFileStorage path: (Smalltalk getenv: 'TX_DIR')).
[db := space newDatabase: 'bench'.
 db newTransactionDo: [:tr | | d |
   d := tr newDictionary.
   profile = 'small-record' ifTrue: [
     0 to: 99 do: [:k | d := d setAt: k value: (tr newObject: {'name' -> ('account ' , k printString). 'balance' -> 0. 'hits' -> 0. 'stamp' -> 0})]].
   tr setRootObject: 'kv' value: d].
 1 to: n do: [:i |
   profile = 'tiny' ifTrue: [
     db run: [:tr | tr setRootObject: 'kv' value: ((tr getRootObject: 'kv') setAt: i value: i \\ 1000)]].
   profile = 'small-record' ifTrue: [
     db run: [:tr | | recs rec |
       recs := tr getRootObject: 'kv'.
       rec := recs getAt: i \\ 100.
       rec := rec withAll: {'balance' -> ((rec at: 'balance') + i). 'hits' -> ((rec at: 'hits') + 1). 'stamp' -> i}.
       tr setRootObject: 'kv' value: (recs setAt: i \\ 100 value: rec)]].
   profile = 'batch-100' ifTrue: [
     db run: [:tr | | d |
       d := tr getRootObject: 'kv'.
       (i - 1) * 100 + 1 to: i * 100 do: [:k | d := d setAt: k value: k \\ 97].
       tr setRootObject: 'kv' value: d]]]]
  ensure: [space close].

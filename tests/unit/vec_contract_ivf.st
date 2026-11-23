"EXPECT: ok 2"
"Vectors phase V6 (Addendum V, 2.4, 2.7 and 5.1): the index contract for PBVectorIndex, its
 ivf_flat registrations (tests/contracts/index_contract.py:836 at v2.0.0rc4): cosine, l2 and ip
 with nlist 3 and nprobe 3 (every list probed: the answers are exact). Every check of
 tests/unit/_vcontract.st but (f), for the seeds 1..PBST_PROP_SEEDS (default 8, proto_db's
 SEEDS). Then the teeth (tests/unit/test_vector_index.py
 test_vector_contract_rejects_broken_variants): each vector plant of _qplants.st, made exact on
 'cosine' and 'l2', is rejected by planMatchesScan for at least one seed (a failure String, never
 another error). The exact registrations are tests/unit/vec_contract_exact.st's, and check (f),
 the collections, is tests/unit/vec_contract_coll_cosine.st's, vec_contract_coll_l2.st's and
 vec_contract_coll_ip.st's (the split of review I2 of task V6). Saves go to out/vec_contract (git
 ignores out/), a new directory per run; nothing is removed."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.
Import from: '_qplants'.
Import from: '_vcontract'.

| c fails registrations seeds teeth caught |
c := Check new.
seeds := (1 to: (QData seeds: 8)) asArray.
registrations := #('cosine' 'l2' 'ip') collect: [:m | { m. 'ivf_flat'. { 'nlist' -> 3. 'nprobe' -> 3 }. 'records' }].
fails := VContract failuresOf: registrations seeds: seeds checks: (VContract checks copyWithout: #collections).
fails do: [:each | ('FAIL ' , each) displayNl].
c that: 'the contract but the collections holds for PBVectorIndex, every ivf_flat registration, every seed' is: fails size equals: 0.

teeth := { OnceVectorIndex. MetricBlindVectorIndex. LastTieVectorIndex }.
caught := teeth select: [:plant |
  #('cosine' 'l2') anySatisfy: [:m | seeds anySatisfy: [:seed |
    ((VContract kind: plant metric: m backend: 'exact' params: nil set: 'records' seed: seed) planMatchesScan) isString]]].
(teeth reject: [:plant | caught includes: plant]) do: [:plant | ('NOT CAUGHT ' , plant name) displayNl].
c that: 'every planted vector defect is rejected by planMatchesScan' is: caught size equals: teeth size.
c report displayNl.

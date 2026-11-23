"EXPECT: ok 1"
"Vectors phase V6 (Addendum V, 2.4, 2.7 and 5.1): the index contract for PBVectorIndex, its exact
 registrations (tests/contracts/index_contract.py:832-839 at v2.0.0rc4): exact cosine, l2 and ip;
 exact l2 with numpy false (a parameter protoBaseST stores and ignores, deviation DV2); and exact
 cosine on plain values through an extractor. Every check of tests/unit/_vcontract.st but (f),
 for the seeds 1..PBST_PROP_SEEDS (default 8, proto_db's SEEDS). The contract is split so that
 each file keeps a wide margin under the runner's timeout (review I2 of task V6): the ivf_flat
 registrations and the teeth are tests/unit/vec_contract_ivf.st's, and check (f), the
 collections, is tests/unit/vec_contract_coll_cosine.st's, vec_contract_coll_l2.st's and
 vec_contract_coll_ip.st's. Saves go to out/vec_contract (git ignores out/), a new directory per
 run; nothing is removed."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.
Import from: '_vcontract'.

| c fails registrations seeds |
c := Check new.
registrations := OrderedCollection new.
#('cosine' 'l2' 'ip') do: [:m | registrations add: { m. 'exact'. nil. 'records' }].
registrations add: { 'l2'. 'exact'. { 'numpy' -> false }. 'records' }; add: { 'cosine'. 'exact'. nil. 'values' }.
seeds := (1 to: (QData seeds: 8)) asArray.
fails := VContract failuresOf: registrations seeds: seeds checks: (VContract checks copyWithout: #collections).
fails do: [:each | ('FAIL ' , each) displayNl].
c that: 'the contract but the collections holds for PBVectorIndex, every exact registration, every seed' is: fails size equals: 0.
c report displayNl.

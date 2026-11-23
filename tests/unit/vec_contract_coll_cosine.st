"EXPECT: ok 1"
"Vectors phase V6 (Addendum V, 2.4, 2.7 and 5.1): check (f) of the index contract for
 PBVectorIndex (tests/contracts/index_contract.py check_collections at v2.0.0rc4; the check is
 tests/unit/_vcontract.st's collections) for the cosine registrations, exact and ivf_flat (nlist 3,
 nprobe 3), for the seeds 1..PBST_PROP_SEEDS (default 8, proto_db's SEEDS): attached to every
 collection kind protoBaseST writes with mutators, the index on the value_vector extractor follows
 20 random mutators, and after each, and after a save and a load, it validates and answers every
 term as near_oracle does. One file per metric keeps each run well under the runner's timeout
 (review I2 of task V6). The two other exact registrations, l2 with numpy false and cosine on
 plain values, would run exact l2's and exact cosine's check draw for draw (it indexes the
 value_vector extractor whatever the registration's key specs, and numpy is ignored, DV2), so
 they are not run twice. The other checks are tests/unit/vec_contract_exact.st's and
 vec_contract_ivf.st's. Saves go to out/vec_contract (git ignores out/), a new directory per run;
 nothing is removed."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_queries'.
Import from: '_vcontract'.

| c fails |
c := Check new.
fails := VContract failuresOf: { { 'cosine'. 'exact'. nil. 'records' }. { 'cosine'. 'ivf_flat'. { 'nlist' -> 3. 'nprobe' -> 3 }. 'records' } }
  seeds: (1 to: (QData seeds: 8)) asArray checks: #(#collections).
fails do: [:each | ('FAIL ' , each) displayNl].
c that: 'every collection mutator keeps the cosine vector indexes answering as the oracle, every seed' is: fails size equals: 0.
c report displayNl.

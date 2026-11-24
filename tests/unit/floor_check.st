"EXPECT: ok 5"
"The floor check (src/protobase/floor.st, final review I1) on the floor: every probe passes, so
 the package loads, and check answers true. The refusal's text names the floor and each missing
 capability (the refusal itself, at load time, is floor_refuses_without_bytes_written.st,
 floor_refuses_without_compare_and_set.st and floor_refuses_without_kmeans_primitive.st). The probes cover what protoBaseST calls of the floor:
 Object >> compareAndSet:from:to: (the write-once publishers), ConnectionTimedOut >> bytesWritten (the TCP sender) and the four Float primitives of the vector
 kernel."
Import from: 'protobase'.
Import from: '_check'.

| c |
c := Check new.
c that: 'on the floor binary no capability is missing'
  is: PBFloor missing equals: #().
c that: 'check answers true on the floor'
  is: PBFloor check equals: true.
c that: 'the probes name the write-once CAS, the transport capability and the four vector primitives, each with its release'
  is: (PBFloor probes collect: [:each | each first])
  equals: #('Object >> compareAndSet:from:to: (protoST 0.17.0)'
    'ConnectionTimedOut >> bytesWritten (protoST 0.16.1, protoIO 0.7.1)'
    'Float class >> fsum: (protoST 0.15.0)' 'Float class >> fsumOfProducts:with: (protoST 0.15.0)'
    'Float class >> fsumOfSquaredDifferences:with: (protoST 0.15.0)'
    'Float class >> fsumOfPowSquaredDifferences:with: (protoST 0.16.0)').
c that: 'the requirement names the release, the protoST floor and its protoIO'
  is: PBFloor requirement equals: 'protoBaseST 0.5.0 requires protoST 0.17.0 or later (protoIO 0.7.1)'.
c that: 'the refusal states the requirement, then every missing capability'
  is: (PBFloor refusalFor: #('A' 'B'))
  equals: 'protoBaseST 0.5.0 requires protoST 0.17.0 or later (protoIO 0.7.1); this protoST lacks A, B. Build protoST 0.17.0 or later against protoIO 0.7.1 (README, Requirements).'.
c report displayNl.

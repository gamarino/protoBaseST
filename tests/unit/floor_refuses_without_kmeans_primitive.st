"EXPECT-ERROR: protoBaseST 0.4.1 requires protoST 0.17.0 or later (protoIO 0.7.1); this protoST lacks Float class >> fsumOfPowSquaredDifferences:with: (protoST 0.16.0)."
"The floor check (src/protobase/floor.st, final review I1): on a protoST without the k-means
 distance primitive Float fsumOfPowSquaredDifferences:with: (older than 0.16.0), Import from:
 'protobase' refuses with PBNotSupportedError naming the floor and the missing capability; without
 the check, the vector kernel, which calls the primitive directly since the floor moved to 0.16.1,
 signalled MessageNotUnderstood at its first IVF training.

 The missing capability is simulated, in this test only: before the import, this file redefines
 Float class >> respondsTo: to deny that one selector, the probe the floor check makes of it.
 Nothing in src/ knows of the simulation."
Float class >> respondsTo: aSelector
  aSelector == #fsumOfPowSquaredDifferences:with: ifTrue: [^ false].
  ^ super respondsTo: aSelector.

Import from: 'protobase'.
'protobase loaded below its floor' displayNl.

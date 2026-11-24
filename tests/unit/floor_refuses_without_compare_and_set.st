"EXPECT-ERROR: protoBaseST 0.4.1 requires protoST 0.17.0 or later (protoIO 0.7.1); this protoST lacks Object >> compareAndSet:from:to: (protoST 0.17.0)."
"The floor check (src/protobase/floor.st): on a protoST that does not understand
 compareAndSet:from:to: (protoST 0.16.1 and older, where the write-once publishers' only CAS
 was setInstVar:from:to:), Import from: 'protobase' refuses with PBNotSupportedError naming the
 floor and the missing capability, before any other module loads.

 The missing capability is simulated, in this test only: before the import, this file redefines
 Object class >> canUnderstand: to deny compareAndSet:from:to:, the probe the floor check makes
 of it. Nothing in src/ knows of the simulation."
Object class >> canUnderstand: aSelector
  aSelector == #compareAndSet:from:to: ifTrue: [^ false].
  ^ super canUnderstand: aSelector.

Import from: 'protobase'.
'protobase loaded below its floor' displayNl.

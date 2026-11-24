"EXPECT-ERROR: protoBaseST 0.4.1 requires protoST 0.17.0 or later (protoIO 0.7.1); this protoST lacks ConnectionTimedOut >> bytesWritten (protoST 0.16.1, protoIO 0.7.1)."
"The floor check (src/protobase/floor.st, final review I1): on a protoST whose ConnectionTimedOut
 does not answer bytesWritten (protoST 0.16.0 and older), Import from: 'protobase' refuses with
 PBNotSupportedError naming the floor and the missing capability, before any other module loads;
 without the check, protoBaseST loaded and its TCP sender dropped frames with no word naming the
 cause (the review measured cluster_transport_tcp_slow_reader.st on 0.16.0: exit 124).

 The missing capability is simulated, in this test only: before the import, this file redefines
 ConnectionTimedOut class >> canUnderstand: to deny bytesWritten, the one probe the floor check
 makes of it. Nothing in src/ knows of the simulation. The real older binary was checked by hand
 (finalfix-report.md): protoST 0.16.0 refuses with the same text."
ConnectionTimedOut class >> canUnderstand: aSelector
  aSelector == #bytesWritten ifTrue: [^ false].
  ^ super canUnderstand: aSelector.

Import from: 'protobase'.
'protobase loaded below its floor' displayNl.

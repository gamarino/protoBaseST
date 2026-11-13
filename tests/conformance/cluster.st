"EXPECT: cluster skipped visibly"
"The cluster section (README, 'Using the vectors', 8) and the invalid vectors of the
 layers roots_log (an acceptor log) and message (bytes received on a cluster
 connection). The framed log files (roots-torn.log, ranges.log, segments.log and the
 invalid vectors of layer log) are verified by framing_logs.st (PBFramedLog), the acceptor
 log roots.log and the invalid vectors of layer roots_log by rootlog.st (PBAcceptorLog), the
 cluster segment by cluster_segment.st (PBSpaceRoot databases:term:epoch:previous:), the
 message frames and the invalid vectors of layer message by messages.st (PBClusterMessage),
 except message-oversized: a frame length over 64 MiB is refused by the frame layer, cluster
 Task 6. That one is a visible skip: one 'SKIP: invalid message message-oversized' line with
 its reason. The Task 25 accounting accepts exactly this line as a justified skip. The files
 are still verified against vectors.sha256 (Vectors manifest), and the refusal of a cluster
 node's space by PBFileStorage path: is checked here."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest cluster base refused |
manifest := Vectors manifest.
cluster := manifest at: 'cluster'.
((manifest at: 'invalid') select: [:e | (e at: 'id') = 'message-oversized']) do: [:e |
  ('SKIP: invalid ' , (e at: 'layer') , ' ' , (e at: 'id') , ': pending, the frame layer is cluster Task 6') displayNl].
"The section must hold exactly the items skipped above or verified elsewhere."
(cluster keys asSortedCollection asArray = #('messages' 'ranges_log' 'roots_log' 'roots_log_torn' 'segment' 'segments_log'))
  ifFalse: [('FAIL the cluster section holds ' , cluster keys asSortedCollection asArray printString) displayNl. Smalltalk exit: 1].
base := FileSystem temp / ('pbst-cluster-' , Smalltalk pid printString).
base deleteAll.
(base / 'cluster') ensureCreateDirectory.
refused := [PBFileStorage path: base. false] on: PBNotSupportedError do: [:e | e return: true].
base deleteAll.
refused ifFalse: ['FAIL a space holding cluster/ was opened' displayNl. Smalltalk exit: 1].
'cluster skipped visibly' displayNl

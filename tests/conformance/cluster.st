"EXPECT: cluster vectors ok"
"The cluster section (README, 'Using the vectors', 8) and the invalid vectors of the
 layers roots_log (an acceptor log) and message (bytes received on a cluster
 connection). The framed log files (roots-torn.log, ranges.log, segments.log and the
 invalid vectors of layer log) are verified by framing_logs.st (PBFramedLog), the acceptor
 log roots.log and the invalid vectors of layer roots_log by rootlog.st (PBAcceptorLog), the
 cluster segment by cluster_segment.st (PBSpaceRoot databases:term:epoch:previous:), the
 message frames and the invalid vectors of layer message by messages.st (PBClusterMessage),
 except message-oversized, verified here: a frame length over 64 MiB is refused by the frame
 layer (PBClusterFrame lengthFrom:) from its 4 length bytes. The files are still verified
 against vectors.sha256 (Vectors manifest), and the refusal of a cluster node's space by
 PBFileStorage path: is checked here."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest cluster base refused oversized |
manifest := Vectors manifest.
cluster := manifest at: 'cluster'.
oversized := (manifest at: 'invalid') select: [:e | (e at: 'id') = 'message-oversized'].
oversized size = 1 ifFalse: [('FAIL the manifest lists ' , oversized size printString , ' message-oversized vectors') displayNl. Smalltalk exit: 1].
oversized do: [:e |
  | outcome |
  ((e at: 'layer') = 'message' and: [(e at: 'error') = 'protocol']) ifFalse: [
    ('FAIL message-oversized is listed as ' , (e at: 'layer') , '/' , (e at: 'error')) displayNl. Smalltalk exit: 1].
  outcome := [PBClusterFrame lengthFrom: (Vectors bytesOf: (e at: 'file')). 'accepted']
    on: PBDBError do: [:x | (x isKindOf: PBClusterProtocolError) ifTrue: [nil] ifFalse: [x class name , ': ' , x messageText]].
  outcome isNil ifFalse: [('FAIL message-oversized: ' , outcome) displayNl. Smalltalk exit: 1]].
"The section must hold exactly the items verified elsewhere (the files listed above)."
(cluster keys asSortedCollection asArray = #('messages' 'ranges_log' 'roots_log' 'roots_log_torn' 'segment' 'segments_log'))
  ifFalse: [('FAIL the cluster section holds ' , cluster keys asSortedCollection asArray printString) displayNl. Smalltalk exit: 1].
base := FileSystem temp / ('pbst-cluster-' , Smalltalk pid printString).
base deleteAll.
(base / 'cluster') ensureCreateDirectory.
refused := [PBFileStorage path: base. false] on: PBNotSupportedError do: [:e | e return: true].
base deleteAll.
refused ifFalse: ['FAIL a space holding cluster/ was opened' displayNl. Smalltalk exit: 1].
'cluster vectors ok' displayNl

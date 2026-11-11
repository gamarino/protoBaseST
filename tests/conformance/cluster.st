"EXPECT: cluster skipped visibly"
"The cluster section (README, 'Using the vectors', 8) and the invalid vectors of the
 layers roots_log (an acceptor log) and message (bytes received on a cluster
 connection). Clusters are outside the prototype (design spec 10.5: PBFileStorage
 refuses a space holding cluster/ with PBNotSupportedError), so every item is a
 visible skip: one 'SKIP: cluster <item>' line per item of the cluster section (each
 message frame by its id) and one 'SKIP: invalid <layer> <id>' line per manifest
 entry of the two layers. The Task 25 accounting accepts exactly these lines as
 justified skips. The files are still verified against vectors.sha256 (Vectors
 manifest), and the refusal of a cluster node's space is checked here."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest cluster base refused |
manifest := Vectors manifest.
cluster := manifest at: 'cluster'.
#('segment' 'roots_log' 'roots_log_torn' 'ranges_log' 'segments_log') do: [:item |
  ('SKIP: cluster ' , item , ' (' , ((cluster at: item) at: 'file') , '): clusters are outside the prototype') displayNl].
(cluster at: 'messages') do: [:message |
  ('SKIP: cluster message ' , (message at: 'id') , ' (' , (message at: 'file') , '): clusters are outside the prototype') displayNl].
((manifest at: 'invalid') select: [:e | #('roots_log' 'message') includes: (e at: 'layer')]) do: [:e |
  ('SKIP: invalid ' , (e at: 'layer') , ' ' , (e at: 'id') , ': clusters are outside the prototype') displayNl].
"The section must hold exactly the items skipped above."
(cluster keys asSortedCollection asArray = #('messages' 'ranges_log' 'roots_log' 'roots_log_torn' 'segment' 'segments_log'))
  ifFalse: [('FAIL the cluster section holds ' , cluster keys asSortedCollection asArray printString) displayNl. Smalltalk exit: 1].
base := FileSystem temp / ('pbst-cluster-' , Smalltalk pid printString).
base deleteAll.
(base / 'cluster') ensureCreateDirectory.
refused := [PBFileStorage path: base. false] on: PBNotSupportedError do: [:e | e return: true].
base deleteAll.
refused ifFalse: ['FAIL a space holding cluster/ was opened' displayNl. Smalltalk exit: 1].
'cluster skipped visibly' displayNl

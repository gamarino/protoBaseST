"EXPECT: ok 8"
"The framed-log reader (PBFramedLog payloadsOf:kind:, ProtoBase logfile.read_log) on the
 valid logs of the vectors, beside the refusals of tests/conformance/invalid_log.st: each
 cluster log reads the number of entries the manifest lists, a torn tail is dropped and
 every earlier entry read, and a new log (no bytes, a prefix of the header, zero bytes after
 it) holds no entry. Clusters stay outside the prototype (tests/conformance/cluster.st);
 this only checks that the reader accepts what it must."
Import from: 'protobase'.
Import from: '_check'.

| c cluster read header |
c := Check new.
cluster := ((Import from: 'json') JSON parse: '../conformance/manifest.json' asFileReference contents) at: 'cluster'.
read := [:item |
  | entry |
  entry := cluster at: item.
  PBFramedLog payloadsOf: ('../conformance/vectors/' , (entry at: 'file')) asFileReference binaryContents
    kind: (entry at: 'kind')].
c that: 'the acceptor log: every entry, of the listed size'
  is: ((read value: 'roots_log') collect: [:p | p size]) asArray
  equals: (((cluster at: 'roots_log') at: 'entries') collect: [:e | e at: 'size']) asArray.
c that: 'a torn tail: every earlier entry' is: (read value: 'roots_log_torn') size equals: ((cluster at: 'roots_log_torn') at: 'entries').
c that: 'ranges.log' is: (read value: 'ranges_log') size equals: ((cluster at: 'ranges_log') at: 'entries') size.
c that: 'segments.log: the segment UUIDs'
  is: ((read value: 'segments_log') collect: [:p | p hex asLowercase]) asArray
  equals: ((cluster at: 'segments_log') at: 'entries') asArray.
header := PBFramedLog headerOfKind: 'ROOT' utf8Encoded.
c that: 'no bytes: a new log' is: (PBFramedLog payloadsOf: ByteArray new kind: 'ROOT') size equals: 0.
c that: 'a torn header: a new log' is: (PBFramedLog payloadsOf: (header copyFrom: 1 to: 9) kind: 'ROOT') size equals: 0.
c that: 'zero bytes after a prefix: a new log'
  is: (PBFramedLog payloadsOf: (header copyFrom: 1 to: 5) , (ByteArray new: 20) kind: 'ROOT') size equals: 0.
c that: 'a kind that is not 4 characters' signals: PBValidationError during: [PBFramedLog payloadsOf: header kind: 'ROOTS'].
c report displayNl.

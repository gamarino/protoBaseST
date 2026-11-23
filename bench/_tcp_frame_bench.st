"_tcp_frame_bench.st: the measurement of bench/run_tcp_frames.sh (final review M4), imported by
 tcp_frames.st (the transport as it is) and tcp_frames_whole_body.st (the same transport reading
 each body in one read, as 0.3.0 did). Two PBTcpTransports on 127.0.0.1, a to b. For each frame size
 in FRAME_SIZES (bytes of the message's reason; default 65536 262144 1048576 2097152), one frame is
 encoded once, then offered to a's sender for b FRAMES times (default 5), one after the other: each
 time, the milliseconds from the offer until b's handler has the message. Self-reporting: the
 handler checks every message's term and the size of its reason, and the line of a size is
 written only when every frame arrived and checked; any other outcome signals.
 Prints one line per size: 'frame <bytes> chunk <readChunk> ms <times...> min <min> median <median>
 delivered <n> checked <n>'. Timings are reported, never asserted."
Import from: 'protobase'.
Import from: 'net'.

| sizes frames membership a b got bad sender env |
env := [:name :default | (Smalltalk getenv: name) ifNil: [default]].
sizes := ((env value: 'FRAME_SIZES' value: '65536 262144 1048576 2097152') substrings: ' ') collect: [:s | s asNumber].
frames := (env value: 'FRAMES' value: '5') asNumber.
membership := [:pairs | PBMembership peers: (pairs collect: [:p | PBPeer nodeId: p first host: '127.0.0.1' port: p last]) voters: nil].
got := Atom on: #().
bad := Atom on: 0.
a := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000.
b := PBTcpTransport withListener: (ServerSocket listenOn: 0 host: '127.0.0.1') requestTimeout: 60000.
a start: 'a' peers: (membership value: { { 'a'. a port }. { 'b'. b port } }) key: nil handler: [:m | nil].
b start: 'b' peers: (membership value: { { 'a'. a port }. { 'b'. b port } }) key: nil
  handler: [:m | got swap: [:old | old copyWith: { m at: 'term'. (m at: 'reason') size }]].
sender := (a instVarNamed: 'run') value senders at: 'b'.
sizes do: [:n | | frame times sorted checked |
  frame := PBClusterFrame encode: (PBClusterMessage type: 'reject' from: 'a' fields: { 'term' -> n. 'rid' -> 1.
    'inc' -> 0. 'root' -> nil. 'certain' -> false. 'reason' -> (String new: n withAll: $x). 'highest' -> 0.
    'remaining' -> 0 }) to: 'b' key: nil.
  times := OrderedCollection new.
  got swap: [:old | #()].
  1 to: frames do: [:i | | t0 |
    t0 := Time microsecondClockValue.
    sender offer: frame.
    [got value size >= i] whileFalse: [(Future after: 1) wait].
    times add: Time microsecondClockValue - t0 + 500 // 1000].
  checked := (got value select: [:each | each first = n and: [each last = n]]) size.
  (got value size = frames and: [checked = frames]) ifFalse: [
    ^ Error signal: 'frame ' , n printString , ': delivered ' , got value size printString , ', checked ' , checked printString].
  sorted := times asArray asSortedCollection asArray.
  ('frame ' , frame size printString , ' chunk ' , PBTcpTransport readChunk printString , ' ms'
    , (times inject: '' into: [:s :t | s , ' ' , t printString]) , ' min ' , sorted first printString
    , ' median ' , (sorted at: sorted size + 1 // 2) printString , ' delivered ' , got value size printString
    , ' checked ' , checked printString) displayNl].
a stop wait.
b stop wait.
((a stats at: 'frames_sent') = (sizes size * frames) and: [(b stats at: 'frames_rejected') = 0]) ifFalse: [
  ^ Error signal: 'stats: ' , a stats printString , ' ' , b stats printString].
('done: frames_sent ' , (a stats at: 'frames_sent') printString , ', frames_dropped ' , (a stats at: 'frames_dropped') printString
  , ', frames_rejected ' , (b stats at: 'frames_rejected') printString) displayNl.

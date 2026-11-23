"The TCP frame-size bench (bench/run_tcp_frames.sh, final review M4) with each body read in one
 read, the shape of 0.3.0's reader: a bench-only redefinition of PBTcpTransport class >> readChunk
 (nothing in src/ changes). It is the comparison column only; it gives up the bound a small
 readChunk puts on a reader's turn (readChunk's comment)."
Import from: 'protobase'.
PBTcpTransport class >> readChunk
  ^ 1073741824.
Import from: '_tcp_frame_bench'.

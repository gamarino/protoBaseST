"_st_term_values.st: protoBaseST's side of tests/interop/py_term_cases.py (indexed queries, plan
 Task 5). A helper: the runner never runs files whose name starts with _.

 Usage: STPATH=<repo>/src:<repo>/tests/unit protost _st_term_values.st <count> <seed>

 Prints one line: the hexadecimal MessagePack bytes of a map with
   'values'  the wire form of each value of QData values: count seed: seed, in order, with the
             oids QData pinOids: gives its records (so the bytes are the same in every run), each atom
             written {'@ref': [oid, 0, type tag]}
   'atoms'   an array of [oid, r] for each distinct atom among them (QData's records hold one
             attribute, r)
 so that proto_db can evaluate its terms on the very values the protoBaseST test draws."
Import from: 'protobase'.
Import from: '_queries'.

| args values ref atoms seen wire |
args := Smalltalk arguments.
values := QData pinOids: (QData values: (args at: 1) asInteger seed: (args at: 2) asInteger).
atoms := OrderedCollection new.
seen := Set new.
ref := [:anAtom |
  (seen includes: anAtom oid hex) ifFalse: [
    seen add: anAtom oid hex.
    atoms addLast: { anAtom oid. anAtom at: 'r' }].
  MessagePackMap withAll: { '@ref' -> { anAtom oid. 0. PBTypeRegistry writerTag: anAtom tag } }].
wire := values collect: [:each | PBCodec toWire: each atomRef: ref].
(MessagePack encode: (MessagePackMap withAll: { 'values' -> wire. 'atoms' -> atoms asArray })) hex displayNl.

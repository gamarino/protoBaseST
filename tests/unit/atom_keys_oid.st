"EXPECT: ok 21"
"Atom keys are oids, and the save keeps them (plan Task 15, keeping Task 10 fix round 1 and
 ruling R13): an atom's map-key and order-key identity is its oid, drawn in memory on first
 need (ProtoBase D21) and persisted by the save, so an unsaved atom used as a key keeps its
 key after the save, in memory and when the record is read back. Two objects of one oid
 are one key: a map holding both is refused (PBValidationError) before any byte is
 written, as ProtoBase's reader would refuse those bytes; the pairs tested are an atom and
 a stub of its record ({atomV1 -> a. atomV2 -> b}) and a saved atom and its decoded twin
 (PBAtom >> _decodedTwin, ProtoBase Atom._decoded_twin: the atom a load of its record
 would produce, built from the state it was saved with). A PBDictionary takes the second
 as the same key (setAt:value: replaces), as ProtoBase's. The records are saved into a
 PBFileStorage (plan Task 17) and read back through a fresh storage."
Import from: 'protobase'.
Import from: '_check'.

| c sink k map dict rec h okey hkey oid twin stub base st loaded |
c := Check new.
base := FileSystem temp / ('pbst-atom-keys-oid-' , Smalltalk pid printString).
base deleteAll.
sink := PBFileStorage path: base pathString.
k := PBObject withAll: { 'name' -> 'key' }.
map := PBFrozenDict withAssociations: { k -> 'v'. 'plain' -> 1 }.
dict := PBDictionary new setAt: k value: 'in a dictionary'.
rec := PBObject withAll: { 'map' -> map. 'dict' -> dict }.
h := k hash.
okey := PBKeys orderKey: k.
hkey := PBKeys hashKey: k.
oid := k oid.
c that: 'not saved yet' is: k pointer equals: nil.
rec _saveInto: sink.
c that: 'the key record is saved' isTrue: k pointer notNil.
c that: 'its oid is the one drawn in memory' is: k oid equals: oid.
c that: 'its hash is unchanged' is: k hash equals: h.
c that: 'its order key is unchanged' is: (PBKeys orderKey: k) equals: okey.
c that: 'its hash key is unchanged' is: (PBKeys hashKey: k) equals: hkey.
c that: 'the map still finds it' is: (map at: k) equals: 'v'.
c that: 'the dictionary still finds it' is: (dict getAt: k) equals: 'in a dictionary'.

"Read back from the segment file."
st := PBFileStorage path: base pathString.
loaded := PBTypeRegistry unloadedAtomFor: 19 at: rec pointer storage: st.
c that: 'the record''s oid' is: loaded oid equals: rec oid.
c that: 'the stored map finds the key by the atom in memory' is: ((loaded at: 'map') at: k) equals: 'v'.
c that: 'the stored dictionary finds it too' is: ((loaded at: 'dict') getAt: k) equals: 'in a dictionary'.
c that: 'the stored key is = to it' is: ((loaded at: 'map') keys first) = k equals: true.

"Two objects of one oid."
stub := k unloadedCopy.
c that: 'a stub of the key record is another object' isTrue: stub ~~ k.
c that: 'of the same oid' is: stub oid equals: k oid.
c that: '{atomV1 -> a. atomV2 -> b} is refused' signals: PBValidationError containing: 'twice'
  during: [PBFrozenDict withAssociations: { k -> 'a'. stub -> 'b' }].
twin := k _decodedTwin.
c that: 'the decoded twin is another object' isTrue: twin ~~ k.
c that: 'loaded, at the same pointer, with the same oid' is: { twin isLoaded. twin pointer. twin oid } equals: { true. k pointer. k oid }.
c that: 'holding the saved state' is: (twin at: 'name') equals: 'key'.
c that: '{saved A -> a. twin of A -> b} is refused' signals: PBValidationError containing: 'twice'
  during: [PBObject withAll: { 'map' -> (PBFrozenDict withAssociations: { k -> 'a'. twin -> 'b' }) }].
c that: 'a PBDictionary takes the twin as the same key' is: ((dict setAt: twin value: 'b') count) equals: 1.
c that: 'an unsaved atom has no twin' signals: PBUserError during: [(PBObject withAll: #()) _decodedTwin].
st close.
sink close.
base deleteAll.
c report displayNl.

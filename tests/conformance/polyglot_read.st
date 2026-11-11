"EXPECT: polyglot read ok 21"
"The polyglot_database section (README, 'Using the vectors', 9), on a copy of
 vectors/polyglot. First with no class for polyglot.st.Order: the record reads as a
 PBOpaqueAtom with its fields (D59), the ProtoBase record it references is readable,
 the older record written as polyglot.st.SalesOrder (referenced under the declared
 name) reads as an opaque atom of the referenced name, describeDatabase: is the
 manifest's contents, and dumpSpace:to: writes what ProtoBase's verifier writes
 (its atom and collection counts on this space are 22 and 5). Then with a class registered under polyglot.st.Order, declaring
 the alias polyglot.st.SalesOrder: a space opened afterwards reads both records as
 that class, the older one through the declared alias. Keeping the record byte for
 byte when the record that references it is rewritten needs the writer (plan Task 20)."
Import from: 'protobase'.
Import from: '_vectors'.
Object subclass: #Check instanceVariableNames: 'failures count'.
Check class >> new
  ^ self basicNew setUp.
Check >> setUp
  failures := OrderedCollection new.
  count := 0.
Check >> that: aLabel is: actual equals: expected
  count := count + 1.
  actual = expected ifFalse: [failures add: aLabel , ': expected ' , expected printString , ', got ' , actual printString].
Check >> report
  failures do: [:each | ('FAIL ' , each) displayNl].
  ^ failures isEmpty ifTrue: ['ok ' , count printString] ifFalse: ['failed'].
| manifest section c dir space snap holder order older customer contents dump reread |
manifest := Vectors manifest.
section := manifest at: 'polyglot_database'.
contents := section at: 'contents'.
c := Check new.
dir := Vectors copySpace: 'polyglot_database'.
space := PBObjectSpace storage: (PBFileStorage path: dir).
snap := (space openDatabase: 'db') snapshotAt: (space openDatabase: 'db') history first.
holder := snap getRootObject: 'holder'.
order := holder at: 'order'.
c that: 'the manifest names the opaque type' is: (section at: 'opaque_type') equals: 'polyglot.st.Order'.
c that: 'the order reads as an opaque atom' is: order class equals: PBOpaqueAtom.
c that: 'its type name' is: order tag equals: 'polyglot.st.Order'.
c that: 'its fields' is: order attributeNames equals: #('customer' 'lines' 'number' 'placed' 'total').
c that: 'its number' is: (order at: 'number') equals: 7.
c that: 'its total' is: (order at: 'total') printString equals: '12.50'.
customer := order at: 'customer'.
c that: 'the ProtoBase record it references' is: customer class equals: PBObject.
c that: 'is readable' is: (customer at: 'name') equals: 'ACME'.
older := holder at: 'older_order'.
c that: 'the older record is opaque too' is: older class equals: PBOpaqueAtom.
c that: 'under the name it was referenced by' is: older tag equals: 'polyglot.st.Order'.
c that: 'its field' is: (older at: 'number') equals: 6.
c that: 'describeDatabase: is the manifest contents' is: (PBNotation describeDatabase: snap)
  equals: (Dictionary new
    at: 'roots' put: (contents at: 'roots'); at: 'mutables' put: (contents at: 'mutables');
    at: 'indexes' put: (contents at: 'indexes'); at: 'origin' put: (contents at: 'origin'); yourself).
dump := PBNotation dumpSpace: space to: dir parent / ((dir basename) , '-dump.json').
reread := Vectors json parse: (dir parent / ((dir basename) , '-dump.json')) contents.
(dir parent / ((dir basename) , '-dump.json')) delete.
"ProtoBase's verifier reports 22 atoms and 5 collections on this space."
c that: 'dumpSpace: atoms' is: (reread at: 'atoms') equals: 22.
c that: 'dumpSpace: collections' is: (reread at: 'collections') equals: 5.
c that: 'dumpSpace: opaque_types' is: (reread at: 'opaque_types') equals: #('polyglot.st.Order').
c that: 'dumpSpace: the database' is: ((reread at: 'databases') at: 'db') equals: (PBNotation describeDatabase: snap).
space close.

"A class for the type, registered after: later loads take it (ProtoBase: 'a class
 registered later under that name takes over for the loads that follow')."
PBObject subclass: #PolyglotOrder.
PolyglotOrder class >> typeName
  ^ 'polyglot.st.Order'.
PolyglotOrder class >> typeAliases
  ^ #('polyglot.st.SalesOrder').
PBObjectSpace registerAtomClass: PolyglotOrder.
space := PBObjectSpace storage: (PBFileStorage path: dir).
snap := (space openDatabase: 'db') snapshotAt: (space openDatabase: 'db') history first.
holder := snap getRootObject: 'holder'.
c that: 'with a class, the order is a PolyglotOrder' is: (holder at: 'order') class equals: PolyglotOrder.
c that: 'its number' is: ((holder at: 'order') at: 'number') equals: 7.
c that: 'the record written as SalesOrder' is: (holder at: 'older_order') class equals: PolyglotOrder.
c that: 'resolves through the declared alias' is: ((holder at: 'older_order') at: 'number') equals: 6.
c that: 'an absent field of a class reads as nil' is: ((holder at: 'older_order') at: 'total') equals: nil.
space close.
dir deleteAll.
('polyglot read ' , c report) displayNl

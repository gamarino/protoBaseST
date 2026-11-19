"EXPECT: ok 29"
"Refusals of the write side (plan Task 18, design spec 7.1 and 10.5; ProtoBase
 set_root_object, new_mutable, set_mutable and canonical_for): a root name starting with
 '__' is reserved for the format (PBValidationError), for setRootObject: and, since proto_db
 2.0.0rc4 (_check_not_reserved in remove_root_object), for removeRootObject: too, checked
 after the name and before the transaction's state; a Symbol (a long one: a short Symbol
 literal is the String itself in protoST, STATUS D35), a Dictionary or a Fraction
 as a value is PBValidationError naming the root or cell it was going to (holder
 Root 'name' or Mutable 'name'); so is a value deeper than MAX_VALUE_DEPTH; replace: must
 be a Boolean; a name must be a non-empty String. Each refusal happens at the call, the
 transaction stays active, and its commit publishes nothing of it. A blind merge onto a
 root whose current value has an index is PBNotSupportedError, through the commit."
Import from: 'protobase'.
Import from: '_check'.

| c base space db tx size deep |
c := Check new.
base := FileSystem temp / ('pbst-tx-refusals-' , Smalltalk pid printString).
base deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space newDatabase: 'db'.
size := db history size.
tx := db newTransaction.
c that: 'a __ root name' signals: PBValidationError containing: '__' during: [tx setRootObject: '__currentModules' value: 1].
c that: 'a __ root name with replace:' signals: PBValidationError during: [tx setRootObject: '__x' value: 1 replace: true].
c that: 'a Symbol value' signals: PBValidationError containing: 'Root ''s''' during: [tx setRootObject: 's' value: #foobarbaz].
c that: 'a Symbol in a cell' signals: PBValidationError containing: 'Mutable ''m''' during: [tx newMutable: 'm' value: #foobarbaz].
c that: 'a Dictionary value' signals: PBValidationError containing: 'Dictionary' during: [
  tx setRootObject: 'd' value: (Dictionary new at: 1 put: 2; yourself)].
c that: 'a Fraction value' signals: PBValidationError containing: 'Fraction' during: [tx setRootObject: 'f' value: 1/3].
c that: 'replace: not a Boolean' signals: PBValidationError containing: 'replace' during: [
  tx setRootObject: 'x' value: 1 replace: 1].
c that: 'an empty root name' signals: PBValidationError during: [tx setRootObject: '' value: 1].
c that: 'a Symbol root name' signals: PBValidationError during: [tx setRootObject: #foobarbaz value: 1].
c that: 'an empty cell name' signals: PBValidationError during: [tx newMutable: '' value: 1].
c that: 'a removal: an empty name' signals: PBValidationError during: [tx removeRootObject: ''].
c that: 'a removal of a __ root name' signals: PBValidationError containing: 'reserved for the format' during: [
  tx removeRootObject: '__catalog'].

"The holder quotes the name as Python's repr does (ProtoBase f'{name!r}')."
c that: 'a name with a single quote: double quotes' signals: PBValidationError containing: 'Root "it''s": ' during: [
  tx setRootObject: 'it''s' value: #foobarbaz].
c that: 'a name with both quotes: the single one escaped' signals: PBValidationError
  containing: 'Mutable ''a"b\''c'': ' during: [tx newMutable: 'a"b''c' value: #foobarbaz].
c that: 'repr: a backslash, controls, Latin-1 non-printables, the rest kept' is: (PBCodec repr: (String withAll: {
  $x. $\. $y. Character value: 10. Character value: 9. Character value: 1. Character value: 127.
  Character value: 160. Character value: 173. Character value: 233 }))
  equals: '''x\\y\n\t\x01\x7f\xa0\xad' , (String with: (Character value: 233)) , ''''.

"Deeper than MAX_VALUE_DEPTH (1022): refused naming where the value was going."
deep := 1.
1023 timesRepeat: [deep := Array with: deep].
c that: 'a root deeper than the limit' signals: PBValidationError containing: 'Root ''deep''' during: [
  tx setRootObject: 'deep' value: deep].
c that: 'a cell deeper than the limit' signals: PBValidationError containing: 'Mutable ''deep''' during: [
  tx newMutable: 'deep' value: deep].
db newTransactionDo: [:t | t newMutable: 'cell' value: 0].
size := db history size.
c that: 'setMutable: deeper than the limit' signals: PBValidationError containing: 'Mutable ''cell''' during: [
  tx setMutable: 'cell' value: deep].
c that: 'the transaction is still active' is: tx isActive equals: true.
c that: 'nothing was written' is: { tx rootNames asArray. tx mutableNames asArray } equals: { #(). #() }.
tx commit.
c that: 'a removal of a __ root name is refused before the state check' signals: PBValidationError
  containing: 'reserved for the format' during: [tx removeRootObject: '__currentModules'].
c that: 'so the commit publishes nothing' is: db history size equals: size.
c that: 'the refused writes are absent' is: db newTransaction rootNames asArray equals: #().


"1022 nested lists are within the limit: committed and read back."
deep := 1.
1022 timesRepeat: [deep := Array with: deep].
db newTransactionDo: [:t | t setRootObject: 'deep' value: deep. t newMutable: 'deep' value: deep].
tx := db newTransaction.
c that: 'a root of 1022 lists round-trips' is: (PBCodec encode: (tx getRootObject: 'deep')) equals: (PBCodec encode: deep).
c that: 'a cell of 1022 lists too' is: (PBCodec encode: (tx getMutable: 'deep')) equals: (PBCodec encode: deep).
space close.

"A blind merge onto a root whose current value has indexes: refused through the commit
 (design spec 7.4), on a copy of the database vector ('people' has the indexes by_age and
 by_city)."
base deleteAll.
base ensureCreateDirectory.
'../conformance/vectors/database' asFileReference files do: [:f | f copyTo: base / f basename].
space := PBObjectSpace storage: (PBFileStorage path: base pathString).
db := space openDatabase: 'db'.
size := db history size.
tx := db newTransaction.
tx setRootObject: 'people' value: (tx newDictionary setAt: 'zed' value: 1).
c that: 'a merge onto an indexed value' signals: PBNotSupportedError containing: 'by_age' during: [tx commit].
c that: 'the transaction is aborted' is: tx isActive equals: false.
c that: 'nothing was published' is: db history size equals: size.
tx := db newTransaction.
tx setRootObject: 'people' value: (tx newDictionary setAt: 'zed' value: 1) replace: true.
tx commit.
c that: 'replace: true substitutes the indexed value' is: (db newTransaction getRootObject: 'people') keys asArray equals: #('zed').
space close.
base deleteAll.
c report displayNl.

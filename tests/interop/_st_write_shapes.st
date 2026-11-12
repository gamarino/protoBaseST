"_st_write_shapes.st <directory> <out.json>: protoST's side of st_to_py.sh (design spec 10.2
 and 10.3, plan Task 20; a helper, never run as a test). It writes the shapes of
 py_write_space.py through the transactions' write side, in three commits after the creation
 of the database 'erp' (versions 1 to 3 after version 0):

  1. the mutable cell 'customer:acme' (a demo.erp.Customer), 'invoices' (a PBDictionary from
     number to demo.erp.Invoice, whose customer is a PBMutableObject) and 'settings' (a plain
     PBObject);
  2. every collection protoBaseST can write: 'tags' (PBList), 'rates' (PBDictionary of
     Decimal), 'hash' (PBHashDictionary), 'set' (PBSet), and the two review-focus cases:
     'bounds' (a PBDictionary keyed by the integer boundaries 2^63-1, 2^63, 2^64-1, 2^64,
     -2^63, -2^63-1 and 2^64+1, valued by their names) with 'bound_values' (a PBList of the
     same integers), and 'strings' (a PBList of strings of 254, 255, 256 and 300 code points:
     U+00E9 is two bytes in UTF-8, so the 255 and 254 are not boxed by the code point
     threshold although they hold more than 256 bytes, and 256 and 300 are boxed);
  3. invoice 1001 paid (a new version made with with:value:), the customer renamed through its
     mutable cell, and a second cell 'sequence'.

 Not written, because protoBaseST cannot yet or never will: an indexed collection, a
 CountedSet or RepeatedKeysDictionary (their writes are plan Task 22) and demo.erp.AuditNote
 (a type only Python knows: an opaque atom is never rewritten). Writes PBNotation
 dumpSpace:to: of the space to <out.json> and prints 'written'."
Import from: 'protobase'.
Import from: 'erp_model'.

| args space db p63 p64 |
args := Smalltalk arguments.
args size = 2 ifFalse: [
  'usage: _st_write_shapes.st <directory> <out.json>' displayNl.
  Smalltalk exit: 2].
p63 := 2 raisedTo: 63.
p64 := 2 raisedTo: 64.
space := PBObjectSpace storage: (PBFileStorage path: (args at: 1)).
db := space newDatabase: 'erp'.

db newTransactionDo: [:t | | acme invoices |
  acme := t newMutable: 'customer:acme'
    value: (Customer withAll: { 'name' -> 'ACME S.A.'. 'taxId' -> '30-12345678-9' }).
  invoices := (t newDictionary
    setAt: 1001 value: (Invoice withAll: { 'number' -> 1001. 'customer' -> acme. 'total' -> (Decimal fromString: '1250.00') }))
    setAt: 1002 value: (Invoice withAll: { 'number' -> 1002. 'customer' -> acme. 'total' -> (Decimal fromString: '99.90') }).
  t setRootObject: 'invoices' value: invoices.
  t setRootObject: 'settings' value: (t newObject: {
    'currency' -> 'ARS'. 'decimals' -> 2. 'started' -> (CalendarDate year: 2026 month: 1 day: 1) })].

db newTransactionDo: [:t | | bounds boundValues keys |
  t setRootObject: 'tags' value: (t newList extend: {
    'urgent'. 2. 3.5. nil. (ByteArray withAll: #(0 1)). (PBTuple withAll: { 1. 'x' }) }).
  t setRootObject: 'rates' value: ((t newDictionary
    setAt: 'ARS' value: (Decimal fromString: '1.00'))
    setAt: 'USD' value: (Decimal fromString: '1450.25')).
  t setRootObject: 'hash' value: ((t newHashDictionary
    setAt: 'k' value: 'v')
    setAt: 2 value: (CalendarDate year: 2026 month: 1 day: 1)).
  t setRootObject: 'set' value: (((t newSet add: 1) add: 'a') add: (PBTuple withAll: { 1. 2 })).
  keys := { p63 - 1. p63. p64 - 1. p64. p63 negated. p63 negated - 1. p64 + 1 }.
  bounds := t newDictionary.
  keys do: [:k | bounds := bounds setAt: k value: k printString].
  t setRootObject: 'bounds' value: bounds.
  boundValues := t newList.
  keys do: [:k | boundValues := boundValues appendLast: k].
  t setRootObject: 'bound_values' value: boundValues.
  t setRootObject: 'strings' value: (t newList extend: (#(254 255 256 300) collect: [:n |
    String new: n withAll: (n = 300 ifTrue: [$x] ifFalse: [Character value: 233])]))].

db newTransactionDo: [:t | | invoices paid customer |
  invoices := t getRootObject: 'invoices'.
  paid := (invoices getAt: 1001) with: 'paidOn' value: (CalendarDate year: 2026 month: 11 day: 20).
  t setRootObject: 'invoices' value: (invoices setAt: 1001 value: paid).
  customer := PBMutableObject name: 'customer:acme'.
  customer set: t value: ((customer get: t) with: 'name' value: 'ACME Argentina S.A.').
  t newMutable: 'sequence' value: 1003].

space close.
space := PBObjectSpace storage: (PBFileStorage path: (args at: 1)).
PBNotation dumpSpace: space to: (args at: 2).
space close.
'written' displayNl.

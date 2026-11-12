"EXPECT: ok 47"
"Every Smalltalk block of docs/tutorial.md, in order, in one session (plan Task 24). A line of the tutorial that ends in => value is asserted here. tutorial_sync.sh fails when a block of the tutorial is not in this file."

Import from: 'protobase'.
Import from: '../unit/_check'.

| dir space db invoices inv paid reader other outcome attempts acme lines
  totals tags seen asOf moment1 moment2 mine theirs v |
| c |
c := Check new.
PBObject subclass: #Invoice.

Invoice class >> typeName
  ^ 'demo.erp.Invoice'.

Invoice class >> typeAliases
  ^ #().

"Behaviour names no implementation may store as an attribute."
Invoice class >> reservedAttributeNames
  ^ #('isPaid' 'is_paid').

"Accessors only answer the stored value."
Invoice >> number
  ^ self at: 'number'.

Invoice >> total
  ^ self at: 'total'.

Invoice >> paidOn
  ^ self at: 'paidOn'.

"Behaviour. The name isPaid is reserved above, so it can never be a stored attribute."
Invoice >> isPaid
  ^ self paidOn notNil.

PBObjectSpace registerAtomClass: Invoice.
dir := FileSystem temp / ('erp-tutorial-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
space listDatabases.                          "=> #()"
c that: 'tutorial' is: (space listDatabases) equals: #().
db := space newDatabase: 'erp'.
space listDatabases.                          "=> #('erp')"
c that: 'tutorial' is: (space listDatabases) equals: #('erp').
db name.                                      "=> 'erp'"
c that: 'tutorial' is: (db name) equals: 'erp'.
db newTransactionDo: [:tr |
    tr setRootObject: 'invoices' value: tr newDictionary.
    tr setRootObject: 'hits' value: 0].
db history size.                              "=> 2"
c that: 'tutorial' is: (db history size) equals: 2.
db newTransactionDo: [:tr |
    invoices := tr getRootObject: 'invoices'.
    inv := Invoice withAll: {
        'number' -> 1043.
        'total'  -> (Decimal fromString: '1250.00') }.
    tr setRootObject: 'invoices' value: (invoices setAt: 1043 value: inv)].
reader := db newTransaction.
((reader getRootObject: 'invoices') getAt: 1043) total.     "=> 1250.00"
c that: 'tutorial' is: (((reader getRootObject: 'invoices') getAt: 1043) total) printString equals: '1250.00'.
((reader getRootObject: 'invoices') getAt: 1043) isPaid.    "=> false"
c that: 'tutorial' is: (((reader getRootObject: 'invoices') getAt: 1043) isPaid) equals: false.
((reader getRootObject: 'invoices') getAt: 7) isNil.        "=> true"
c that: 'tutorial' is: (((reader getRootObject: 'invoices') getAt: 7) isNil) equals: true.
reader abort.
reader isActive.                              "=> false"
c that: 'tutorial' is: (reader isActive) equals: false.
outcome := [reader getRootObject: 'hits'] on: PBUserError do: [:e | e messageText].
outcome.                                      "=> 'The transaction is aborted; start a new one'"
c that: 'tutorial' is: (outcome) equals: 'The transaction is aborted; start a new one'.
tags := PBSet new.
tags add: 'urgent'.
tags count.                                   "=> 0"
c that: 'tutorial' is: (tags count) equals: 0.
tags := tags add: 'urgent'.
tags count.                                   "=> 1"
c that: 'tutorial' is: (tags count) equals: 1.
(tags has: 'urgent').                         "=> true"
c that: 'tutorial' is: ((tags has: 'urgent')) equals: true.
lines := PBList new.
lines := (lines appendLast: 'a') appendLast: 'c'.
lines := lines insertAt: 1 value: 'b'.
lines elements.                               "=> #('a' 'b' 'c')"
c that: 'tutorial' is: (lines elements) equals: #('a' 'b' 'c').
lines getAt: 0.                               "=> 'a'"
c that: 'tutorial' is: (lines getAt: 0) equals: 'a'.
lines getAt: -1.                              "=> 'c'"
c that: 'tutorial' is: (lines getAt: -1) equals: 'c'.
outcome := [lines getAt: 3] on: PBValidationError do: [:e | e messageText].
outcome.                                      "=> 'List position 3 out of range for a list of 3'"
c that: 'tutorial' is: (outcome) equals: 'List position 3 out of range for a list of 3'.
(lines sliceFrom: 1 to: nil) elements.        "=> #('b' 'c')"
c that: 'tutorial' is: ((lines sliceFrom: 1 to: nil) elements) equals: #('b' 'c').
(lines removeAt: 0) elements.                 "=> #('b' 'c')"
c that: 'tutorial' is: ((lines removeAt: 0) elements) equals: #('b' 'c').
lines count.                                  "=> 3"
c that: 'tutorial' is: (lines count) equals: 3.
totals := PBDictionary new.
totals := totals setAt: 1043 value: 12.
totals := totals setAt: 1043.0 value: 13.
totals count.                                 "=> 1"
c that: 'tutorial' is: (totals count) equals: 1.
totals := totals setAt: (Decimal fromString: '1043.00') value: 14.
totals count.                                 "=> 1"
c that: 'tutorial' is: (totals count) equals: 1.
(totals getAt: 1043).                         "=> 14"
c that: 'tutorial' is: ((totals getAt: 1043)) equals: 14.
(totals has: true).                           "=> false"
c that: 'tutorial' is: ((totals has: true)) equals: false.
totals := totals setAt: 'x' value: 0.
totals keys.                                  "=> #(1043 'x')"
c that: 'tutorial' is: (totals keys) equals: #(1043 'x').
paid := inv with: 'paidOn' value: (CalendarDate year: 2026 month: 11 day: 11).
paid isPaid.                                  "=> true"
c that: 'tutorial' is: (paid isPaid) equals: true.
inv isPaid.                                   "=> false"
c that: 'tutorial' is: (inv isPaid) equals: false.
inv = paid.                                   "=> false"
c that: 'tutorial' is: (inv = paid) equals: false.
paid number.                                  "=> 1043"
c that: 'tutorial' is: (paid number) equals: 1043.
db newTransactionDo: [:tr |
    invoices := tr getRootObject: 'invoices'.
    tr setRootObject: 'invoices' value: (invoices setAt: 1043 value: paid)].
((db newTransaction getRootObject: 'invoices') getAt: 1043) isPaid.     "=> true"
c that: 'tutorial' is: (((db newTransaction getRootObject: 'invoices') getAt: 1043) isPaid) equals: true.
reader := db newTransaction.
reader getRootObject: 'hits'.
db newTransactionDo: [:other | other setRootObject: 'hits' value: 7].
reader setRootObject: 'hits' value: 8.
outcome := [reader commit. 'committed'] on: PBConflictError do: [:e | e messageText].
outcome.                                      "=> 'Root ''hits'' of database ''erp'' was changed by a concurrent commit'"
c that: 'tutorial' is: (outcome) equals: 'Root ''hits'' of database ''erp'' was changed by a concurrent commit'.
reader isActive.                              "=> false"
c that: 'tutorial' is: (reader isActive) equals: false.
attempts := 0.
db run: [:tr |
    attempts := attempts + 1.
    v := tr getRootObject: 'hits'.
    attempts = 1 ifTrue: [
        db newTransactionDo: [:rival | rival setRootObject: 'hits' value: 100]].
    tr setRootObject: 'hits' value: v + 1].
attempts.                                     "=> 2"
c that: 'tutorial' is: (attempts) equals: 2.
(db newTransaction getRootObject: 'hits').    "=> 101"
c that: 'tutorial' is: ((db newTransaction getRootObject: 'hits')) equals: 101.
reader := db newTransaction.
other := db newTransaction.
reader setRootObject: 'tags' value: (reader newDictionary setAt: 'urgent' value: true).
other setRootObject: 'tags' value: (other newDictionary setAt: 'paid' value: false).
reader commit.
other commit.
seen := (db newTransaction getRootObject: 'tags') keys.
seen.                                         "=> #('paid' 'urgent')"
c that: 'tutorial' is: (seen) equals: #('paid' 'urgent').
mine := PBDictionary new setAt: 'a' value: 1.
theirs := PBDictionary new setAt: 'b' value: 2.
mine opLog.                                   "=> PBFrozenList(PBTuple('set', 'a', 1))"
c that: 'tutorial' is: (mine opLog) printString equals: 'PBFrozenList(PBTuple(''set'', ''a'', 1))'.
(mine rebaseOnto: theirs) keys.               "=> #('a' 'b')"
c that: 'tutorial' is: ((mine rebaseOnto: theirs) keys) equals: #('a' 'b').
acme := PBMutableObject name: 'customer:acme'.
db newTransactionDo: [:tr | tr newMutable: acme name value: 'ACME S.A.'].
moment1 := db history first committedAt.
db newTransactionDo: [:tr | acme set: tr value: 'ACME Argentina S.A.'].
moment2 := db history first committedAt.
acme get: db newTransaction.                  "=> 'ACME Argentina S.A.'"
c that: 'tutorial' is: (acme get: db newTransaction) equals: 'ACME Argentina S.A.'.
asOf := [:moment |
    | entry |
    entry := db history detect: [:each | each committedAt <= moment]
        ifNone: [PBUserError signal: 'the database did not exist yet'].
    db snapshotAt: entry].
(asOf value: moment1) getMutable: 'customer:acme'.      "=> 'ACME S.A.'"
c that: 'tutorial' is: ((asOf value: moment1) getMutable: 'customer:acme') equals: 'ACME S.A.'.
(asOf value: moment2) getMutable: 'customer:acme'.      "=> 'ACME Argentina S.A.'"
c that: 'tutorial' is: ((asOf value: moment2) getMutable: 'customer:acme') equals: 'ACME Argentina S.A.'.
db history last version.                      "=> 0"
c that: 'tutorial' is: (db history last version) equals: 0.
(db snapshotAt: db history last) rootNames.   "=> #()"
c that: 'tutorial' is: ((db snapshotAt: db history last) rootNames) equals: #().
outcome := [totals setAt: 'k' value: Dictionary new] on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'its order is unspecified'.      "=> true"
c that: 'tutorial' is: (outcome includesSubstring: 'its order is unspecified') equals: true.
outcome := [totals setAt: 'k' value: (1/2)] on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'a Fraction cannot be stored'.   "=> true"
c that: 'tutorial' is: (outcome includesSubstring: 'a Fraction cannot be stored') equals: true.
outcome := [totals setAt: 'k' value: #invoice] on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'a Symbol cannot be stored'.     "=> true"
c that: 'tutorial' is: (outcome includesSubstring: 'a Symbol cannot be stored') equals: true.
outcome := [totals setAt: (PBFrozenList withAll: #(1)) value: 0] on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'not an orderable key'.          "=> true"
c that: 'tutorial' is: (outcome includesSubstring: 'not an orderable key') equals: true.
outcome := [db newTransactionDo: [:tr | tr setRootObject: '__x' value: 1]]
    on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'reserved for the format'.       "=> true"
c that: 'tutorial' is: (outcome includesSubstring: 'reserved for the format') equals: true.
space close.
dir deleteAll.
space isClosed.                               "=> true"
c that: 'tutorial' is: (space isClosed) equals: true.
c report displayNl.

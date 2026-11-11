"_st_dump.st <directory> <out.json>: protoST's side of design spec 10.2 (a helper of
 py_to_st.sh, never run as a test). It imports examples/erp/erp_model.st (on STPATH), writes
 PBNotation dumpSpace:to: of the space, and reads the Python-written database 'erp' through
 a transaction: its describeDatabase: equals the snapshot's, every root read is in its read
 set, and the ERP records answer their accessors (Invoice isPaid, the customer through its
 PBMutableObject, the AuditNote as an opaque atom). Versions 2 and 1 are read through
 snapshotAt:. Prints 'st dump ok', or each failed
 check and exits 1."
Import from: 'protobase'.
Import from: 'erp_model'.

| args failures check space db tx snapshot json inv1001 inv1002 customer audit older |
args := Smalltalk arguments.
args size = 2 ifFalse: [
  'usage: _st_dump.st <directory> <out.json>' displayNl.
  Smalltalk exit: 2].
failures := OrderedCollection new.
check := [:label :actual :expected |
  actual = expected ifFalse: [
    failures add: label , ': expected ' , expected printString , ', got ' , actual printString]].
space := PBObjectSpace storage: (PBFileStorage path: (args at: 1)).
PBNotation dumpSpace: space to: (args at: 2).

db := space openDatabase: 'erp'.
check value: 'versions' value: (db history collect: [:e | e version]) asArray value: #(3 2 1 0).
snapshot := db snapshotAt: db history first.
tx := db newTransaction.
json := [:d | (Import from: 'json') JSON stringify: d].
check value: 'the transaction describes the snapshot''s database'
  value: (json value: (PBNotation describeDatabase: tx))
  value: (json value: (PBNotation describeDatabase: snapshot)).
check value: 'every root is in the read set' value: tx readSet keys asArray value: tx rootNames asArray.
check value: 'the mutable cells' value: tx mutableNames asArray value: #('customer:acme' 'sequence').

inv1001 := (tx getRootObject: 'invoices') getAt: 1001.
inv1002 := (tx getRootObject: 'invoices') getAt: 1002.
check value: 'an invoice is an Invoice' value: inv1001 class value: Invoice.
check value: 'its number' value: inv1001 number value: 1001.
check value: 'its total' value: inv1001 total printString value: '1250.00'.
check value: 'paid' value: inv1001 isPaid value: true.
check value: 'paid on' value: (PBNotation describe: inv1001 paidOn) printString
  value: (PBNotation describe: (CalendarDate year: 2026 month: 11 day: 20)) printString.
check value: 'not paid' value: inv1002 isPaid value: false.
customer := inv1001 customer get: tx.
check value: 'the customer through its cell' value: customer class value: Customer.
check value: 'renamed' value: customer name value: 'ACME Argentina S.A.'.
check value: 'tax id' value: customer taxId value: '30-12345678-9'.
check value: 'the cell read is recorded' value: (tx mutableReadSet includesKey: 'customer:acme') value: true.
audit := tx getRootObject: 'audit'.
check value: 'a Python-only type is opaque' value: audit class value: PBOpaqueAtom.
check value: 'its type name' value: audit typeName value: 'demo.erp.AuditNote'.
check value: 'its field' value: (audit at: 'text') value: 'created'.
tx abort.

"Older versions are read, not only counted (review M4): at version 2 invoice 1001 is
 unpaid and the customer has its first name; version 1 has no collection roots yet."
older := db snapshotAt: (db history at: 2).
check value: 'version 2' value: older version value: 2.
check value: 'invoice 1001 unpaid at version 2' value: ((older getRootObject: 'invoices') getAt: 1001) isPaid value: false.
check value: 'the customer''s name at version 2' value: (older getMutable: 'customer:acme') name value: 'ACME S.A.'.
check value: 'no sequence cell at version 2' value: (older getMutable: 'sequence') value: nil.
older := db snapshotAt: (db history at: 3).
check value: 'version 1' value: older version value: 1.
check value: 'no tags at version 1' value: (older getRootObject: 'tags') value: nil.
check value: 'invoice 1002 at version 1' value: ((older getRootObject: 'invoices') getAt: 1002) total printString value: '99.90'.
check value: 'the audit note at version 1' value: ((older getRootObject: 'audit') at: 'text') value: 'created'.
space close.

failures isEmpty ifTrue: ['st dump ok' displayNl] ifFalse: [
  failures do: [:each | ('FAIL ' , each) displayNl].
  Smalltalk exit: 1].

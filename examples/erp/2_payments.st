"Step 2, protoST: record payments and rename a customer.

  protost 2_payments.st <directory>

Records never change: a payment is a new version of the invoice, made with with:value:, and
the invoice dictionary that holds it is a new version too. A customer is renamed through its
PBMutableObject, the one thing in the database that is a name for 'the latest version'.
Two commits: version 2 (six payments) and version 3 (the rename)."
Import from: 'protobase'.
Import from: 'erp_model'.

| space db acme |
space := PBObjectSpace storage: (PBFileStorage path: (Smalltalk arguments at: 1)).
db := space openDatabase: 'erp'.

db newTransactionDo: [:tr | | invoices |
    invoices := tr getRootObject: 'invoices'.
    4 to: 24 by: 4 do: [:i | | invoice |
        invoice := invoices getAt: 1000 + i.
        invoices := invoices
            setAt: 1000 + i
            value: (invoice with: 'paidOn' value: (CalendarDate year: 2026 month: 11 day: i))].
    tr setRootObject: 'invoices' value: invoices].

acme := PBMutableObject name: 'customer:acme'.
db newTransactionDo: [:tr |
    acme set: tr value: ((acme get: tr) with: 'name' value: 'ACME Argentina S.A.')].

space close.

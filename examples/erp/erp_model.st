"EXPECT: erp model ok"
"-- erp_model.st: the record types of the ERP example, protoST side (design spec 4.5) --

  Invoice    demo.erp.Invoice: number, customer (a PBMutableObject naming the
             customer's cell), total (a Decimal), paidOn (a CalendarDate, absent or
             nil while unpaid); behaviour: isPaid
  Customer   demo.erp.Customer: name, taxId

The same names and aliases are declared by examples/erp/erp_model.py, which also
declares demo.erp.AuditNote: protoST has no class for that one and reads its records
as PBOpaqueAtom (D59). Accessors only answer the stored value (A4). A behaviour name
is never a persisted attribute in any implementation of the type: Invoice reserves
isPaid (here) and is_paid (Python's name for it), so a record holding either is
refused when loaded, in both languages.

Importing this module registers both classes. Run directly (the test runner does),
it checks its own declarations and prints 'erp model ok'."

Import from: 'protobase'.

PBObject subclass: #Invoice.

Invoice class >> typeName
  ^ 'demo.erp.Invoice'.

Invoice class >> typeAliases
  ^ #().

"The behaviour names of every implementation of the type."
Invoice class >> reservedAttributeNames
  ^ #('isPaid' 'is_paid').

"Accessors: they only answer the stored value."
Invoice >> number
  ^ self at: 'number'.

Invoice >> customer
  ^ self at: 'customer'.

Invoice >> total
  ^ self at: 'total'.

Invoice >> paidOn
  ^ self at: 'paidOn'.

"Behaviour: reserves the name isPaid, which no implementation may persist."
Invoice >> isPaid
  ^ self paidOn notNil.

PBObject subclass: #Customer.

Customer class >> typeName
  ^ 'demo.erp.Customer'.

Customer class >> typeAliases
  ^ #().

Customer >> name
  ^ self at: 'name'.

Customer >> taxId
  ^ self at: 'taxId'.

PBObjectSpace registerAtomClass: Invoice.
PBObjectSpace registerAtomClass: Customer.

((PBTypeRegistry classForTag: 'demo.erp.Invoice') == Invoice
  and: [(PBTypeRegistry classForTag: 'demo.erp.Customer') == Customer
  and: [(PBTypeRegistry classForTag: 'demo.erp.AuditNote') == PBOpaqueAtom]])
    ifTrue: ['erp model ok'] ifFalse: ['erp model: the registry does not map demo.erp.* to its classes'].

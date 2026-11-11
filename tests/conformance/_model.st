"_model.st: the application type of the conformance vectors (a helper).

ConformanceInvoice is conformance.Invoice, persisted before as
conformance.LegacyInvoice (ProtoBase tests/conformance/model.py at v2.0.0rc1):
a record type, so a PBObject subclass, with the declared name and the aliases
every implementation that reads the vectors must declare (D57). This file is
its only definition and registration; _vectors.st imports it, so every runner
that loads the vectors has it registered exactly once."

Import from: 'protobase'.

PBObject subclass: #ConformanceInvoice.

ConformanceInvoice class >> typeName
  ^ 'conformance.Invoice'.

ConformanceInvoice class >> typeAliases
  ^ #('conformance.LegacyInvoice').

PBObjectSpace registerAtomClass: ConformanceInvoice.

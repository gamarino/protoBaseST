"""The record types of the ERP example, Python side (design spec 4.5 and 10.2).

Each type declares its language-neutral name (D57), the one ``erp_model.st`` declares for
the protoST class of the same type; defining the class registers it with ProtoBase.

- ``demo.erp.Invoice``: ``number`` (int), ``customer`` (a ``MutableObject`` naming the
  customer's cell), ``total`` (``Decimal``), ``paidOn`` (a ``date``, absent or ``None``
  while unpaid). Its behaviour is ``is_paid()``.
- ``demo.erp.Customer``: ``name``, ``taxId``.
- ``demo.erp.AuditNote``: ``text``, ``at``. Deliberately Python-only: protoST has no class
  for it and reads its records as opaque atoms (D59).

A behaviour name may never be a persisted attribute in any implementation of the type
(design spec 4.5). Invoice's behaviour is ``is_paid`` here and ``isPaid`` in protoST, so both
classes reserve both names: ``isPaid`` is defined below as an alias of ``is_paid``, and the
protoST class lists ``is_paid`` in ``reservedAttributeNames``.

Used by ``tests/interop/py_write_space.py`` and ``tests/interop/py_verify.py``.
"""
from proto_db import DBObject


class Invoice(DBObject):
    """An invoice; paid once ``paidOn`` holds a date."""

    __type_name__ = "demo.erp.Invoice"
    __type_aliases__ = ()

    def is_paid(self) -> bool:
        """Whether the invoice is paid (behaviour: never a persisted attribute)."""
        return self.has_defined_attr("paidOn") and self.paidOn is not None

    isPaid = is_paid


class Customer(DBObject):
    """A customer, held in a mutable cell such as ``customer:acme``."""

    __type_name__ = "demo.erp.Customer"
    __type_aliases__ = ()


class AuditNote(DBObject):
    """A note only Python knows: protoST reads it as an opaque atom."""

    __type_name__ = "demo.erp.AuditNote"
    __type_aliases__ = ()

"-- records.st: PBObject, the records of format 4, read side --

ProtoBase's DBObject (format spec v2.0.0rc1, 'Records' and 'Atom records',
'Attribute names'; ProtoBase proto_db/core/dbobject.py at the tag): an
immutable record of named canonical values.

  PBObject class >> typeName   'proto_db.core.dbobject.DBObject'; an application
                               type subclasses PBObject and overrides typeName and
                               typeAliases (design spec 4.5), and is registered
                               with PBObjectSpace registerAtomClass:
  at: aName                    the attribute's value; an attribute the record does
                               not hold reads as nil
  hasDefinedAttr: aName        whether the record holds the attribute (even as nil)
  attributeNames               the names the record holds, sorted

Loading a record refuses (PBCorruptionError) a persisted attribute named like
a behaviour name of DBObject, with_ or has_defined_attr (format spec,
'Attribute names': a reader may refuse the behaviour names of its own class
for the type, as ProtoBase does; vector invalid/atom-reserved-name). The names
every type refuses (a leading _, oid, atom_pointer, context) are refused by the
envelope (framing.st). An application class may reserve more names with
reservedAttributeNames (class side); DBObject's (dbObjectBehaviourNames) are
checked in every subclass whatever it answers there.

PBOpaqueAtom, the record of a type with no class here, is in registry.st;
with: (ProtoBase's with_) comes with the writer (plan Task 15)."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/keys'.

PBAtom subclass: #PBObject.

PBObject class >> typeName
  ^ 'proto_db.core.dbobject.DBObject'.

"No field is required (format spec, 'Records')."
PBObject class >> requiredFields
  ^ #().

PBObject class >> persistedFields
  ^ #().

"The behaviour names of DBObject, which no persisted attribute may carry, in
 any subclass: the check reads them from PBObject, so no override drops them."
PBObject class >> dbObjectBehaviourNames
  ^ #('with_' 'has_defined_attr').

"The names an application class reserves besides DBObject's: none by default."
PBObject class >> reservedAttributeNames
  ^ #().

PBObject class >> _checkPersistedNames: aState at: aPointer
  | behaviour reserved |
  behaviour := PBObject dbObjectBehaviourNames.
  reserved := self reservedAttributeNames.
  aState keys do: [:name |
    (behaviour includes: name) ifTrue: [
      ^ PBCorruptionError signal: 'the record at ' , aPointer printString , ' (' , self typeName
        , ') holds the attribute ' , name printString , ', a behaviour name of DBObject: no persisted attribute may carry it'].
    (reserved includes: name) ifTrue: [
      ^ PBCorruptionError signal: 'the record at ' , aPointer printString , ' (' , self typeName
        , ') holds the attribute ' , name printString , ', a name ' , self name , ' reserves (reservedAttributeNames)']].
  ^ aState.

"The value of the attribute aName; nil when the record does not hold it."
PBObject >> at: aName
  ^ self stateAt: aName.

"Whether the record holds the attribute aName, even as nil (ProtoBase
 has_defined_attr: a name that cannot be an attribute answers false)."
PBObject >> hasDefinedAttr: aName
  (PBAtomEnvelope _nameProblem: aName) isNil ifFalse: [^ false].
  ^ self state includesKey: aName.

"The names of the attributes the record holds, sorted."
PBObject >> attributeNames
  ^ _PBNames sorted: self state keys.

PBTypeRegistry register: PBObject.

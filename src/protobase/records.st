"-- records.st: PBObject, the records of format 4, read side --

ProtoBase's DBObject (format spec v2.0.0rc2, 'Records' and 'Atom records',
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

New records (plan Task 15), each a new atom with its own oid, drawn on first
need (ProtoBase D21); the receiver of with:value: and withAll: never changes:

  PBObject withAll: { 'name' -> 'Ada'. 'born' -> 1815 }
                               ProtoBase DBObject(name=..., born=...); an
                               application class builds its records the same
                               way (Invoice withAll: {...}); PBObject new is
                               an empty record
  aRecord with: aName value: v ProtoBase with_(name=v): a new record holding
                               the receiver's attributes with aName set to v
                               (nil defines it as nil)
  aRecord withAll: { ... }     with_(**changes)

The attributes keep the order they were given in; a change keeps an existing
attribute's place and appends a new one, as ProtoBase's dict update does (the
order ProtoBase writes). Values pass through PBCodec canonical: at once.
Attribute names are checked as the format spec's 'Atom records' requires, with
PBValidationError: a non-empty String that does not start with _, is not oid,
atom_pointer or context, nor a behaviour name of DBObject (with_,
has_defined_attr) or of the class (reservedAttributeNames); a name given twice
in one call is refused too, and so is a change naming parents or with_parents
(parentsApiNames: reserved for new fields from proto_db 2.0.0rc4, R157; a stored
field of either name still loads and is carried unchanged). A class need not be registered to build records;
its records are refused when saved until it is (PBObjectSpace
registerAtomClass:), as ProtoBase refuses a class with no declared type name.

PBOpaqueAtom, the record of a type with no class here, is in registry.st; it
refuses with:value: and withAll: (PBNotSupportedError naming its type)."

Import from: 'protobase/errors'.
Import from: 'protobase/values'.
Import from: 'protobase/registry'.
Import from: 'protobase/keys'.
Import from: 'protobase/codec'.
Import from: 'protobase/framing'.

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

"The names of DBObject's parents API (proto_db 2.0.0rc4, format spec 'Reserved names', R157,
 R158): no change may create or set a field of either name. The reservation is write-only: a
 stored field of either name (written before format 5) still loads, reads and is carried
 unchanged by a new version, so the read path (_checkPersistedNames:at:) never checks them."
PBObject class >> parentsApiNames
  ^ #('parents' 'with_parents').

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

"=== new records ==============================================================="

"A new record of this class holding the attributes anArray lists (Associations
 name -> value, in order)."
PBObject class >> withAll: anArray
  ^ self _unsavedWithState: (self _state: #() with: anArray).

"An empty record of this class (ProtoBase DBObject())."
PBObject class >> new
  ^ self withAll: #().

"The PBFrozenDict of the attributes anArrayOfAssociations (a record's state, in
 order) updated by the changes aChanges: an existing name keeps its place, a
 new one is appended, each value canonical, each name checked. A stored field
 named parents or with_parents (R157) is carried unchanged and placed last, in
 the order of parentsApiNames, as proto_db 2.0.0rc4's with_ does (_take_legacy
 takes them out, _carry puts them back after the other attributes), so the new
 version's bytes are rc4's."
PBObject class >> _state: anArrayOfAssociations with: aChanges
  | names values given legacy |
  ((aChanges isKindOf: Array) or: [aChanges isKindOf: OrderedCollection]) ifFalse: [
    ^ PBValidationError signal: self name , ': the attributes are an Array of Associations (name -> value), not '
      , (PBKeys _preview: aChanges)].
  names := OrderedCollection new.
  values := OrderedCollection new.
  legacy := Dictionary new.
  anArrayOfAssociations do: [:each |
    | name |
    name := self _checkAttributeName: each key.
    (PBObject parentsApiNames includes: name)
      ifTrue: [legacy at: name put: each value]
      ifFalse: [names addLast: name. values addLast: each value]].
  given := Set new.
  aChanges do: [:each |
    | name i |
    (each isKindOf: Association) ifFalse: [
      ^ PBValidationError signal: self name , ': an attribute is an Association (name -> value), not '
        , (PBKeys _preview: each)].
    name := self _checkAttributeName: each key.
    (PBObject parentsApiNames includes: name) ifTrue: [
      ^ PBValidationError signal: self name , ': the attribute name ' , name printString
        , ' is reserved for the parents API of DBObject (format spec, Reserved names): a change never writes it'].
    (given includes: name) ifTrue: [
      ^ PBValidationError signal: self name , ': the attribute ' , name printString , ' is given twice'].
    given add: name.
    i := names indexOf: name.
    i = 0
      ifTrue: [names addLast: name. values addLast: (self _canonical: each value field: name)]
      ifFalse: [values at: i put: (self _canonical: each value field: name)]].
  PBObject parentsApiNames do: [:name |
    (legacy includesKey: name) ifTrue: [names addLast: name. values addLast: (legacy at: name)]].
  ^ PBFrozenDict withAssociations: ((1 to: names size) asArray collect: [:i | (names at: i) -> (values at: i)]).

"aValue canonical, a PBValidationError of the codec naming the field aName
 (ProtoBase: Field 'name' of <type name>: ...)."
PBObject class >> _canonical: aValue field: aName
  ^ PBCodec canonical: aValue for: ['Field ' , (PBCodec repr: aName) , ' of ' , self typeName].

"aName, when it may be a persisted attribute of this class; PBValidationError
 naming the rule it breaks otherwise (format spec 'Atom records')."
PBObject class >> _checkAttributeName: aName
  | why |
  why := PBAtomEnvelope _nameProblem: aName.
  why isNil ifFalse: [^ PBValidationError signal: self name , ': ' , why].
  (PBObject dbObjectBehaviourNames includes: aName) ifTrue: [
    ^ PBValidationError signal: self name , ': the attribute name ' , aName printString
      , ' is a behaviour name of DBObject: no persisted attribute may carry it'].
  (self reservedAttributeNames includes: aName) ifTrue: [
    ^ PBValidationError signal: self name , ': the attribute name ' , aName printString , ' is a name '
      , self name , ' reserves (reservedAttributeNames)'].
  ^ aName.

"A new record of this class (a new atom, with its own oid) holding the
 receiver's attributes with aName set to aValue (ProtoBase with_)."
PBObject >> with: aName value: aValue
  ^ self withAll: { aName -> aValue }.

"A new record of this class holding the receiver's attributes updated by
 anArray (Associations name -> value), ProtoBase's with_(**changes)."
PBObject >> withAll: anArray
  ^ self class _unsavedWithState: (self class _state: self state associations with: anArray).

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

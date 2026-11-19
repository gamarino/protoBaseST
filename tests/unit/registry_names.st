"EXPECT: ok 54"
"PBTypeRegistry (format spec, 'Type names (D57)', 'Atoms of unknown types (D59)',
 'Built-in type aliases'): aliases and names map to registered classes, an
 unknown proto_db. name is corruption, any other unknown valid name is an
 opaque atom, a bad name is refused when registered (PBValidationError) and
 when read (PBCorruptionError), and conflicting registrations are refused.
 Since plan Task 12 every built-in type of format 4 has its class (abstract ones included).
 The aliases 22 and 23 of format 5 (proto_db 2.0.0rc4: the runtime registry's ModuleList and
 Catalog) are in the table with no class: a record of either is PBNotSupportedError."
Import from: 'protobase'.
Import from: '_check'.

PBAtom subclass: #Invoice.
Invoice class >> typeName
  ^ 'acme.sales.Invoice'.
Invoice class >> typeAliases
  ^ #('acme.sales.LegacyInvoice' 'myapp.models.Invoice').

PBAtom subclass: #OtherInvoice.
OtherInvoice class >> typeName
  ^ 'acme.sales.Invoice'.

PBAtom subclass: #AliasThief.
AliasThief class >> typeName
  ^ 'acme.sales.Thief'.
AliasThief class >> typeAliases
  ^ #('acme.sales.LegacyInvoice').

PBAtom subclass: #LegacyPerson.
LegacyPerson class >> typeName
  ^ 'acme.people.Person'.
LegacyPerson class >> typeAliases
  ^ { 'myapp.models.make.<locals>.Person'. 'myapp.mod', (String with: (Character value: 232)), 'les.Personne' }.

PBAtom subclass: #EmptyAlias.
EmptyAlias class >> typeName
  ^ 'acme.sales.Empty'.
EmptyAlias class >> typeAliases
  ^ #('').

PBAtom subclass: #BadName.
BadName class >> typeName
  ^ 'bad'.

PBAtom subclass: #ReservedName.
ReservedName class >> typeName
  ^ 'proto_db.custom.Thing'.

PBAtom subclass: #FakeModuleList.
FakeModuleList class >> typeName
  ^ 'proto_db.registry.ModuleList'.

PBAtom subclass: #FakeCatalog.
FakeCatalog class >> typeName
  ^ 'proto_db.registry.Catalog'.

PBAtom subclass: #BuiltinAlias.
BuiltinAlias class >> typeName
  ^ 'acme.sales.Other'.
BuiltinAlias class >> typeAliases
  ^ #('proto_db.collections.List').

| c names |
c := Check new.
"The built-in table: 24 names, the alias is the 0-based index."
names := PBTypeRegistry builtinNames.
c that: 'built-in count' is: { names size. PBTypeRegistry builtinCount } equals: #(24 24).
c that: 'aliases 22 and 23 are the registry types of format 5'
  is: (names copyFrom: 23 to: 24) equals: #('proto_db.registry.ModuleList' 'proto_db.registry.Catalog').
c that: 'alias 0' is: (names at: 1) equals: 'proto_db.avl.KeyNode'.
c that: 'alias 21' is: (names at: 22) equals: 'proto_db.avl.CountedKeyNode'.
names at: 1 put: 'tampered.Name'.
c that: 'builtinNames answers a copy' is: (PBTypeRegistry builtinNames at: 1) equals: 'proto_db.avl.KeyNode'.

"Every built-in type has its class, registered under its name."
c that: 'every built-in alias has its class' is: ((0 to: 21) asArray reject: [:alias |
    | cls |
    cls := PBTypeRegistry classForTag: alias.
    cls typeName = (PBTypeRegistry builtinNames at: alias + 1) and: [(PBTypeRegistry tagFor: cls) = alias]]) equals: #().
c that: 'alias 6' is: (PBTypeRegistry classForTag: 6) equals: PBDictionary.
c that: 'proto_db.collections.Dictionary' is: (PBTypeRegistry classForTag: 'proto_db.collections.Dictionary') equals: PBDictionary.
c that: 'tagFor: a built-in class is its alias' is: (PBTypeRegistry tagFor: PBDictionary) equals: 6.
c that: 'registering the same class again is a no-op' is: (PBTypeRegistry register: PBDictionary) equals: PBDictionary.

"Unknown names."
c that: 'proto_db.nonexistent.X' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'proto_db.nonexistent.X'].
c that: 'polyglot.st.Order' is: (PBTypeRegistry classForTag: 'polyglot.st.Order') equals: PBOpaqueAtom.
c that: 'bad, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'bad'].
c that: 'a.b-c, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'a.b-c'].
c that: 'a..b, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'a..b'].
c that: '.a.b, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: '.a.b'].
c that: '1a.b, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: '1a.b'].
c that: 'a non-ASCII name, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'acme.Caf', (String with: (Character value: 233))].
c that: 'aliases 22 and 23, by alias or by name, have no class: not supported'
  is: ({ 22. 23. 'proto_db.registry.ModuleList'. 'proto_db.registry.Catalog' } collect: [:tag |
    [PBTypeRegistry classForTag: tag. 'accepted'] on: PBDBError do: [:e |
      ((e isKindOf: PBNotSupportedError) and: [e messageText includesSubstring: 'has no class in protoBaseST yet'])
        ifTrue: ['not supported'] ifFalse: [e class name]]])
  equals: #('not supported' 'not supported' 'not supported' 'not supported').
c that: 'alias 24' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 24].
c that: 'alias -1' signals: PBCorruptionError during: [PBTypeRegistry classForTag: -1].
c that: 'a float tag' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 1.5].
c that: 'an empty name' signals: PBCorruptionError during: [PBTypeRegistry classForTag: ''].
c that: 'a Boolean tag' signals: PBCorruptionError during: [PBTypeRegistry classForTag: true].

"Registration refusals."
c that: 'bad, when registered' signals: PBValidationError during: [PBTypeRegistry register: BadName].
c that: 'a proto_db. name outside the table' signals: PBValidationError during: [PBTypeRegistry register: ReservedName].
c that: 'a class declaring a registry type name (22, 23) is refused and the alias keeps no class'
  is: ({ FakeModuleList. FakeCatalog } collect: [:cls |
      [PBTypeRegistry register: cls. 'registered'] on: PBValidationError do: [:e |
        (e messageText includesSubstring: 'format-5 type of the runtime registry') ifTrue: ['refused'] ifFalse: [e messageText]]])
    , ({ 22. 23 } collect: [:tag | [PBTypeRegistry classForTag: tag. 'a class'] on: PBNotSupportedError do: [:e | 'no class']])
  equals: #('refused' 'refused' 'no class' 'no class').
c that: 'a built-in name as an alias' signals: PBValidationError during: [PBTypeRegistry register: BuiltinAlias].
c that: 'the abstract base (no typeName)' signals: PBValidationError during: [PBTypeRegistry register: PBAtom].
c that: 'not a class' signals: PBValidationError during: [PBTypeRegistry register: 42].

"Application types: the declared name, its aliases (a rename and a pre-D57 Python name)."
PBTypeRegistry register: Invoice.
c that: 'declared name' is: (PBTypeRegistry classForTag: 'acme.sales.Invoice') equals: Invoice.
c that: 'an alias' is: (PBTypeRegistry classForTag: 'acme.sales.LegacyInvoice') equals: Invoice.
c that: 'a pre-D57 Python name' is: (PBTypeRegistry classForTag: 'myapp.models.Invoice') equals: Invoice.
c that: 'an alias reads as the declared name' is: (PBTypeRegistry nameOfTag: 'acme.sales.LegacyInvoice') equals: 'acme.sales.Invoice'.
c that: 'the canonical tag of an alias' is: (PBTypeRegistry canonicalTag: 'myapp.models.Invoice') equals: 'acme.sales.Invoice'.
c that: 'tagFor: an application class is its declared name' is: (PBTypeRegistry tagFor: Invoice) equals: 'acme.sales.Invoice'.
c that: 'the same name by another class' signals: PBValidationError containing: 'already registered' during: [PBTypeRegistry register: OtherInvoice].
c that: 'an alias taken by another class' signals: PBValidationError containing: 'already registered' during: [PBTypeRegistry register: AliasThief].
c that: 'a refused registration leaves the table unchanged' isTrue: (PBTypeRegistry isRegistered: 'acme.sales.Thief') not.
c that: 'tagFor: an unregistered class' signals: PBValidationError during: [PBTypeRegistry tagFor: OtherInvoice].

"Aliases outside the grammar (pre-D57 Python default names) are declared and read."
PBTypeRegistry register: LegacyPerson.
c that: 'a <locals> alias' is: (PBTypeRegistry classForTag: 'myapp.models.make.<locals>.Person') equals: LegacyPerson.
c that: 'a non-ASCII alias' is: (PBTypeRegistry classForTag: 'myapp.mod', (String with: (Character value: 232)), 'les.Personne') equals: LegacyPerson.
c that: 'a <locals> alias reads as the declared name' is: (PBTypeRegistry canonicalTag: 'myapp.models.make.<locals>.Person') equals: 'acme.people.Person'.
c that: 'an empty alias' signals: PBValidationError during: [PBTypeRegistry register: EmptyAlias].
c that: 'an unregistered <locals> name, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'other.make.<locals>.X'].

"writerTag: refuses what every reader refuses; an alias is written as the declared name."
c that: 'writerTag: bad' signals: PBValidationError during: [PBTypeRegistry writerTag: 'bad'].
c that: 'writerTag: an unknown proto_db. name' signals: PBValidationError during: [PBTypeRegistry writerTag: 'proto_db.nonexistent.X'].
c that: 'writerTag: alias 24' signals: PBValidationError during: [PBTypeRegistry writerTag: 24].
c that: 'a record of alias 22 or 23 (format 5, feature registry) is never written at format 4'
  is: ({ 22. 'proto_db.registry.Catalog' } collect: [:tag |
    [(PBAtomEnvelope tag: tag oid: (ByteArray new: 16) state: (PBFrozenDict withAssociations: #())) encode. 'written']
      on: PBDBError do: [:e | ((e isKindOf: PBNotSupportedError) and: [e messageText includesSubstring: 'format 5'])
        ifTrue: ['refused'] ifFalse: [e class name , ': ' , e messageText]]])
  equals: #('refused' 'refused').
c that: 'writerTag: a <locals> alias' is: (PBTypeRegistry writerTag: 'myapp.models.make.<locals>.Person') equals: 'acme.people.Person'.
c that: 'writerTag: an opaque name' is: (PBTypeRegistry writerTag: 'polyglot.st.Order') equals: 'polyglot.st.Order'.

"Canonical tags: a built-in name becomes its alias, an alias stays."
c that: 'canonical of a built-in name' is: (PBTypeRegistry canonicalTag: 'proto_db.avl.CountedKeyNode') equals: 21.
c that: 'canonical of an alias' is: (PBTypeRegistry canonicalTag: 19) equals: 19.
c that: 'canonical of an unknown name' is: (PBTypeRegistry canonicalTag: 'polyglot.st.Order') equals: 'polyglot.st.Order'.
c report displayNl.

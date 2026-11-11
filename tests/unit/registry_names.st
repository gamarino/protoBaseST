"EXPECT: ok 40"
"PBTypeRegistry (format spec, 'Type names (D57)', 'Atoms of unknown types (D59)',
 'Built-in type aliases'): aliases and names map to registered classes, an
 unknown proto_db. name is corruption, any other unknown valid name is an
 opaque atom, a bad name is refused when registered (PBValidationError) and
 when read (PBCorruptionError), and conflicting registrations are refused.
 PlaceholderDictionary stands in for PBDictionary until plan Task 12."
Import from: 'protobase'.
Import from: '_check'.

PBAtom subclass: #PlaceholderDictionary.
PlaceholderDictionary class >> typeName
  ^ 'proto_db.collections.Dictionary'.

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

PBAtom subclass: #BadName.
BadName class >> typeName
  ^ 'bad'.

PBAtom subclass: #ReservedName.
ReservedName class >> typeName
  ^ 'proto_db.custom.Thing'.

PBAtom subclass: #BuiltinAlias.
BuiltinAlias class >> typeName
  ^ 'acme.sales.Other'.
BuiltinAlias class >> typeAliases
  ^ #('proto_db.collections.List').

| c names |
c := Check new.
"The built-in table: 22 names, the alias is the 0-based index."
names := PBTypeRegistry builtinNames.
c that: 'built-in count' is: names size equals: 22.
c that: 'alias 0' is: (names at: 1) equals: 'proto_db.avl.KeyNode'.
c that: 'alias 21' is: (names at: 22) equals: 'proto_db.avl.CountedKeyNode'.
names at: 1 put: 'tampered.Name'.
c that: 'builtinNames answers a copy' is: (PBTypeRegistry builtinNames at: 1) equals: 'proto_db.avl.KeyNode'.

"A built-in type without a class yet is an explicit refusal, never corruption."
c that: 'alias 6 before its class is registered' signals: PBNotSupportedError containing: 'proto_db.collections.Dictionary'
  during: [PBTypeRegistry classForTag: 6].
PBTypeRegistry register: PlaceholderDictionary.
c that: 'alias 6' is: (PBTypeRegistry classForTag: 6) equals: PlaceholderDictionary.
c that: 'proto_db.collections.Dictionary' is: (PBTypeRegistry classForTag: 'proto_db.collections.Dictionary') equals: PlaceholderDictionary.
c that: 'tagFor: a built-in class is its alias' is: (PBTypeRegistry tagFor: PlaceholderDictionary) equals: 6.
c that: 'registering the same class again is a no-op' is: (PBTypeRegistry register: PlaceholderDictionary) equals: PlaceholderDictionary.

"Unknown names."
c that: 'proto_db.nonexistent.X' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'proto_db.nonexistent.X'].
c that: 'polyglot.st.Order' is: (PBTypeRegistry classForTag: 'polyglot.st.Order') equals: PBOpaqueAtom.
c that: 'bad, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'bad'].
c that: 'a.b-c, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'a.b-c'].
c that: 'a..b, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'a..b'].
c that: '.a.b, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: '.a.b'].
c that: '1a.b, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: '1a.b'].
c that: 'a non-ASCII name, when read' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 'acme.Caf', (String with: (Character value: 233))].
c that: 'alias 22' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 22].
c that: 'alias -1' signals: PBCorruptionError during: [PBTypeRegistry classForTag: -1].
c that: 'a float tag' signals: PBCorruptionError during: [PBTypeRegistry classForTag: 1.5].
c that: 'an empty name' signals: PBCorruptionError during: [PBTypeRegistry classForTag: ''].
c that: 'a Boolean tag' signals: PBCorruptionError during: [PBTypeRegistry classForTag: true].

"Registration refusals."
c that: 'bad, when registered' signals: PBValidationError during: [PBTypeRegistry register: BadName].
c that: 'a proto_db. name outside the table' signals: PBValidationError during: [PBTypeRegistry register: ReservedName].
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

"Canonical tags: a built-in name becomes its alias, an alias stays."
c that: 'canonical of a built-in name' is: (PBTypeRegistry canonicalTag: 'proto_db.avl.CountedKeyNode') equals: 21.
c that: 'canonical of an alias' is: (PBTypeRegistry canonicalTag: 19) equals: 19.
c that: 'canonical of an unknown name' is: (PBTypeRegistry canonicalTag: 'polyglot.st.Order') equals: 'polyglot.st.Order'.
c report displayNl.

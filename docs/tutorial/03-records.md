# 3. Records

<!-- example: examples/tutorial/03_records.st -->
Program: [examples/tutorial/03_records.st](../../examples/tutorial/03_records.st).
Previous: [2. Values and versions](02-values-and-versions.md). Next: [4. Collections and queries](04-collections-and-queries.md).

## Declaring a record type

An application record type subclasses `PBObject` (`proto_db`'s `DBObject`) and declares a
**type name**, a language-neutral name that is written into the file:

```smalltalk
PBObject subclass: #Book.

Book class >> typeName
  ^ 'tutorial.library.Book'.

"Names the type was stored under before (none yet)."
Book class >> typeAliases
  ^ #().

"Behaviour names: never stored as attributes, by any implementation of the type."
Book class >> reservedAttributeNames
  ^ #('isClassic').
```

The file holds the type name and the attributes, never the class or its methods. Any
implementation that declares the same name reads the record with its own class: a Python class
with `__type_name__ = "tutorial.library.Book"` reads it in Python (chapter 11). `typeAliases`
lists the names the type was stored under before, which is how a type is renamed. The class is
registered once per process:

```smalltalk
PBObjectSpace registerAtomClass: Author.
PBObjectSpace registerAtomClass: Book.
```

A record whose type has no registered class is still readable, as a `PBOpaqueAtom`: its
attributes can be read, everything else is refused, and it is never rewritten.

## Accessors read, behaviour computes

```smalltalk
Book >> title
  ^ self at: 'title'.

"Behaviour: computed, so its name is reserved above."
Book >> isClassic
  ^ self year < 1990.
```

An accessor only answers the stored value. A method that computes is behaviour, and its name is
listed in `reservedAttributeNames`: if a program in any language stored an attribute named
`isClassic`, the stored value and the method would disagree about what `isClassic` means. Storing
a reserved name is refused, and a record that holds one is refused when loaded.

## A change is a new version

```smalltalk
revised := blue withAll: { 'title' -> 'Smalltalk-80: The Language'. 'year' -> 1989 }.
lesson check: 'the new version has the new title' is: revised title equals: 'Smalltalk-80: The Language'.
lesson check: 'the old version keeps the old one' is: blue title equals: 'Smalltalk-80: The Language and its Implementation'.
lesson check: 'two versions are two identities' isTrue: (revised = blue) not.
```

`with:value:` and `withAll:` answer a new record with a new identity (an oid). There are no
setters. Two records are `=` when they are the same record (same oid), not when their attributes
match. A record that should keep its identity while its state changes, a customer or an author,
is not modelled by a record but by a mutable cell that holds successive records (chapter 7).

## References between records

```smalltalk
reread := books getAt: 1.
lesson check: 'the record comes back as a Book' is: reread class equals: Book.
lesson check: 'with its behaviour' is: reread isClassic equals: true.
lesson check: 'its author is an Author' is: reread author name equals: 'Adele Goldberg'.
lesson check: 'both books lead to one author record' isTrue: (books getAt: 1) author = (books getAt: 2) author.
```

A record that refers to another is stored with a reference to it, and the referenced record is
stored once. On reading, a reference loads its record when a message first needs it.

## Schema change

There are no class versions and no instance migration. A record is a map of attribute names to
values, so:

- an attribute added to the class is absent (`nil` through `at:`) in older records;
- an attribute no longer used stays in older records, readable with `at:`;
- a renamed type keeps its old records readable through `typeAliases`;
- behaviour always comes from the class registered in the running process.

GemStone answers schema change with class versions and explicit migration; Soil stores a
description of the instance variables by name. The two orientation chapters compare them.

## What to take away

- A type name, not a class, is what the file holds; any language may declare it.
- Records change by new versions; identity is the oid.
- Reserve the names of behaviour.

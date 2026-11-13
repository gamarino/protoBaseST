# 2. Values and versions

<!-- example: examples/tutorial/02_values_and_versions.st -->
Program: [examples/tutorial/02_values_and_versions.st](../../examples/tutorial/02_values_and_versions.st).
Previous: [1. A first commit](01-first-commit.md). Next: [3. Records](03-records.md).

This is the chapter that differs most from every Smalltalk object database you may know. In
GemStone and in Soil you change an object in place and commit; the database finds what changed.
In protoBaseST, records and collections are **values**: they never change. A message that would
change one answers a new version, and the program stores the new version.

## The trap

```smalltalk
tags := PBSet new.
tags add: 'smalltalk'.
lesson check: 'a discarded add: changed nothing' is: tags count equals: 0.
tags := tags add: 'smalltalk'.
lesson check: 'keep the answer' is: tags count equals: 1.
```

`add:`, `remove:`, `setAt:value:`, `removeAt:`, `appendLast:` and the rest answer a new collection.
The names are `proto_db`'s, kept so that one document explains both languages; three of them mean
something else in Pharo: `Set >> add:` and `Set >> remove:` change the set there and answer the
element, and `removeAt:` on a Pharo collection removes in place and answers the element. A
statement that discards the answer changes nothing, and nothing fails. The README states this in a
box, and [decisions.md](../decisions.md) records the alternatives (`copyWith:`, `copyWithout:`);
the workshop may overrule it.

## Old versions stay valid

```smalltalk
before := tags.
tags := (tags add: 'databases') remove: 'smalltalk'.
lesson check: 'the new version' is: tags elements equals: #('databases').
lesson check: 'the old version, untouched' is: before elements equals: #('smalltalk').
```

Nothing was copied to keep the old version: the collections are persistent trees (AVL trees, as in
`proto_db`), and a new version shares every unchanged node with the old one. That sharing is what
makes two things cheap that are expensive with mutable objects:

- **readers need no lock**: a transaction holds the version it started with, and nobody can change
  it under it;
- **history is kept for the price of what changed**: an old version is still a whole, valid value
  (chapter 7).

## Lists count from zero

```smalltalk
shelf := ((PBList new appendLast: 'Blue Book') appendLast: 'Green Book') appendLast: 'Orange Book'.
lesson check: 'getAt: 0 is the first' is: (shelf getAt: 0) equals: 'Blue Book'.
lesson check: 'getAt: -1 is the last' is: (shelf getAt: -1) equals: 'Orange Book'.
lesson check: 'removeAt: answers a new list' is: (shelf removeAt: 0) elements equals: #('Green Book' 'Orange Book').
lesson check: 'and shelf still has three' is: shelf count equals: 3.
lesson check: 'a position out of range is an error, never nil'
    signals: PBValidationError containing: 'out of range' during: [shelf getAt: 3].
```

`PBList` positions are zero-based because `proto_db`'s `List` is, and the tree nodes on disk
store counts both languages read. A position out of range is an error, never `nil`. The values a
program builds itself (`PBFrozenList`, `PBTuple`, `Array`) stay one-based, as Smalltalk's are.

## Changing what is stored

```smalltalk
db newTransactionDo: [:tr |
    | current |
    current := tr getRootObject: 'shelf'.
    current appendLast: 'Purple Book'.
    lesson check: 'inside the transaction, the discarded version is not stored'
        is: (tr getRootObject: 'shelf') count equals: 3.
    tr setRootObject: 'shelf' value: (current appendLast: 'Purple Book')].
```

The pattern is always the same: read the root, build the new version, write the root back. There
is no dirty tracking, because nothing can become dirty; the write is explicit. In exchange there
is nothing to forget: Soil's documentation for its manual mode warns that `markDirty:` "is only as
reliable as remembering to call it" (see [Coming from Soil](soil.md)); here a change that is not
written back is simply a value nobody kept.

## What to take away

- Keep the answer of every collection message.
- An old version is a whole value, shared, not copied.
- A change to stored data is: read, build a new version, write the root.

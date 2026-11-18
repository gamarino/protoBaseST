# 12. What is refused, and why

<!-- example: examples/tutorial/12_refusals.st -->
Program: [examples/tutorial/12_refusals.st](../../examples/tutorial/12_refusals.st).
Previous: [11. One directory, two languages](11-python-interop.md). Back to the [index](README.md).

The rule of the whole prototype: if a value, a type, a version or an operation cannot be stored or
done **exactly**, protoBaseST signals an error that names it, at the call that receives it. It
never stores something else in its place. A silent approximation in a database is found years
later, by someone else, in another language.

## Values with no exact kind

```smalltalk
text := lesson check: 'a Fraction: storing it as a float would be another number'
    signals: PBValidationError containing: 'a Fraction cannot be stored' during: [d setAt: 'k' value: 1/3].
lesson say: text.
lesson check: 'a protoST Dictionary: its order is unspecified, and a map''s order is in its bytes'
    signals: PBValidationError containing: 'its order is unspecified' during: [d setAt: 'k' value: Dictionary new].
lesson check: 'a Symbol longer than six bytes: the format has no symbol kind yet'
    signals: PBValidationError containing: 'a Symbol cannot be stored' during: [d setAt: 'k' value: #customer].
```

| Refused | Why | Use instead |
|---|---|---|
| `Fraction` | no kind in the format; a float would be another number | `Decimal`, or two integers |
| protoST `Dictionary` | its order is unspecified, and the order of a map is part of its bytes | `PBFrozenDict` (keeps insertion order) or `PBDictionary` |
| `Symbol` longer than six bytes | format 4 has no symbol kind; a string would come back as another kind | `String` |
| `Set`, `Bag`, `Interval`, `Character`, a block, any other object | no kind in the format | convert explicitly |
| a list or map as a key | not orderable | `PBTuple` |

The `Fraction` is the one a Smalltalk program meets by accident: `balance * rate / 100` is a
`Fraction` whenever the division is not exact. Storing it is refused on the spot, at
`setRootObject:value:`, not at commit; chapter 5's program says what it means instead (`//`).

A short symbol such as `#paid` is accepted, because in protoST a literal of six bytes or fewer *is*
the `String` `'paid'`:

```smalltalk
lesson check: '#paid is the String ''paid''' is: ((d setAt: 'k' value: #paid) getAt: 'k') equals: 'paid'.
```

## Names that belong to the format

```smalltalk
lesson check: 'a root name starting with __'
    signals: PBValidationError containing: 'reserved for the format' during: [tr setRootObject: '__meta' value: 1].
lesson check: 'an attribute named oid'
    signals: PBValidationError containing: 'oid' during: [tr newObject: { 'oid' -> 1 }].
```

## Misuse

```smalltalk
lesson check: 'a transaction after its end'
    signals: PBUserError containing: 'aborted' during: [tr setRootObject: 'x' value: 1].
lesson check: 'a database that does not exist'
    signals: PBValidationError containing: 'nope' during: [space openDatabase: 'nope'].
space close.
lesson check: 'a closed space'
    signals: PBClosedError containing: '' during: [space openDatabase: 'refusals'].
```

## What this prototype cannot do exactly

```smalltalk
(dir / 'cluster') ensureCreateDirectory.
lesson check: 'a cluster directory (no cluster mode here)'
    signals: PBNotSupportedError containing: 'cluster' during: [PBFileStorage path: dir pathString].
```

`PBNotSupportedError` means valid data or a valid operation outside what the prototype handles:
a cluster directory, a write to an indexed collection (chapter 4; planned for 0.3.0 to narrow to
vector and unknown index kinds only, draft [chapter 17](17-indexes.md)), a wall clock in an IANA time
zone (protoST has no time-zone database), a record of a type with no class here beyond reading its
attributes. Data that is damaged is `PBCorruptionError`. The complete list, with the cost of each
refusal, is [deviations.md](../deviations.md); what is missing altogether is
[not-done.md](../not-done.md).

## What to take away

- An error at the call, naming the value, rather than a different value in the file.
- `PBValidationError`: you gave it something it must not store. `PBNotSupportedError`: valid, but
  not handled by this prototype. `PBCorruptionError`: the data is damaged.

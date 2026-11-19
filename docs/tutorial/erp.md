# Tutorial: a small ERP on protoBaseST

This tutorial builds the core of a small ERP, step by step, and stops at each design choice to say
why it was made. It is written for the FAST Smalltalk workshop (2026-12-03), where protoBaseST is
shown as a **proposal prototype**, to be criticised. Read it as an argument as much as a manual.

Every Smalltalk block in this file is run by `tests/docs/tutorial_snippets.st`, in order, in one
session. A line ending in `"=> value"` states what the expression answers, and the test asserts
it. `tests/docs/tutorial_sync.sh` fails when a block or a `=> value` here differs from the test.
That guard covers the code blocks and their `=>` lines, **not the prose** around them: a number
or a claim in the text is checked only by whoever edits it. Blocks of other languages (`sh`,
`python`, `text`) are not run.

Contents:

1. [Before you start](#1-before-you-start)
2. [The model: values, versions and mutable objects](#2-the-model-values-versions-and-mutable-objects)
3. [Declaring record types](#3-declaring-record-types)
4. [Opening a space and its databases](#4-opening-a-space-and-its-databases)
5. [A first transaction](#5-a-first-transaction)
6. [Every collection message answers a new version](#6-every-collection-message-answers-a-new-version)
7. [Lists count from zero](#7-lists-count-from-zero)
8. [Keys, and what the format compares](#8-keys-and-what-the-format-compares)
9. [Records change by new versions](#9-records-change-by-new-versions)
10. [Conflicts and retries](#10-conflicts-and-retries)
11. [Blind writes merge](#11-blind-writes-merge)
12. [Mutable objects, history and as-of reads](#12-mutable-objects-history-and-as-of-reads)
13. [What the prototype refuses, and what each refusal protects](#13-what-the-prototype-refuses-and-what-each-refusal-protects)
14. [One directory, two languages](#14-one-directory-two-languages)
15. [Where to go next](#15-where-to-go-next)

## 1. Before you start

You need a protoST binary, version 0.12.0 or newer
([release](https://github.com/gamarino/protoST); it adds `Decimal`, `CalendarDate`, `UUID`, random
bytes and the UTC clock), and this repository's `src/` on the module path:

```sh
export PROTOST=../protoST/build_release/protost
export STPATH="$PWD/src"
$PROTOST tutorial.st          # any script that starts with: Import from: 'protobase'.
```

The snippets below are one script. A protoST script has no class to hold local variables, so the
temporaries are declared once, here, and every later block uses them:

```smalltalk
Import from: 'protobase'.

| dir space db invoices inv paid reader other outcome attempts acme lines
  totals tags seen asOf moment1 moment2 mine theirs v |
```

## 2. The model: values, versions and mutable objects

Three ideas carry the whole design. They come from `proto_db`, the Python database whose on-disk
format protoBaseST reads and writes; protoBaseST changes none of them.

**A value never changes.** A record, a list, a dictionary, a set is a value. A message that would
change it answers a *new version* and leaves the receiver as it was. The old version stays valid
for whoever holds it. Two reasons make this the foundation rather than a style:

- *Readers need no lock.* A transaction reads the version that was current when it started. If
  values changed in place, a reader would need a lock, or a copy, to keep seeing one moment.
- *History is free.* Each new version shares every unchanged part with the old one (the trees are
  persistent), so keeping the old version costs only what changed.

**Mutable things are cells, and they change only by commit.** Not everything can be a value: a
customer is still "the customer ACME" after it is renamed. A `PBMutableObject` is a *name* for a
cell of the database. The value in the cell is replaced by a commit, and the history keeps every
earlier value. The name is the one thing that means "the latest version".

**A transaction is a unit of work.** It reads one snapshot, remembers what it read, and at commit
the database checks that none of it changed meanwhile. That check is what makes concurrent writers
safe without locks held across a transaction.

What this prototype adds to the picture is a second implementation: the same files are read and
written by Python (`proto_db`) and by protoST. Section 14 shows it.

## 3. Declaring record types

An application record type subclasses `PBObject` (`proto_db`'s `DBObject`). It has a
language-neutral *type name*, written into the file, and optionally the names it used to have. The
same name must be declared by every implementation that reads the type. This is the same
declaration as `examples/erp/erp_model.st`.

```smalltalk
PBObject subclass: #Invoice.

Invoice class >> typeName
  ^ 'demo.erp.Invoice'.

Invoice class >> typeAliases
  ^ #().

"Behaviour names no implementation may store as an attribute."
Invoice class >> reservedAttributeNames
  ^ #('isPaid' 'is_paid').

"Accessors only answer the stored value."
Invoice >> number
  ^ self at: 'number'.

Invoice >> total
  ^ self at: 'total'.

Invoice >> paidOn
  ^ self at: 'paidOn'.

"Behaviour. The name isPaid is reserved above, so it can never be a stored attribute."
Invoice >> isPaid
  ^ self paidOn notNil.

PBObjectSpace registerAtomClass: Invoice.
```

Why accessors only read: a record's fields are what the file holds, and the file is shared with
Python. A method that computes (`isPaid`) is behaviour; if a Python program stored an attribute
with that name, the two meanings would collide, so the name is declared reserved and a record that
holds it is refused when loaded.

There are no generated setters. A change is `with:value:`, shown in section 9.

## 4. Opening a space and its databases

A *space* is a directory. It holds any number of named *databases*. Opening the directory creates
it if needed.

```smalltalk
dir := FileSystem temp / ('erp-tutorial-' , Smalltalk pid printString).
dir deleteAll.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
space listDatabases.                          "=> #()"
db := space newDatabase: 'erp'.
space listDatabases.                          "=> #('erp')"
db name.                                      "=> 'erp'"
```

`newDatabase:` already commits version 0, the empty database. `openDatabase:` opens one that
exists; the first time, `newDatabase:` is the way in. `space close` ends the session; the last
section of this tutorial calls it.

## 5. A first transaction

```smalltalk
db newTransactionDo: [:tr |
    tr setRootObject: 'invoices' value: tr newDictionary.
    tr setRootObject: 'hits' value: 0].
db history size.                              "=> 2"
```

`newTransactionDo:` commits when the block ends and aborts if the block raises (the exception
goes on). It never retries; section 10 shows `run:`, which does.

A *root* is a named entry point of the database: `invoices` and `hits` here. Everything stored is
reachable from the roots. `tr newDictionary` is a new, empty `PBDictionary`.

Now an invoice, in a second transaction:

```smalltalk
db newTransactionDo: [:tr |
    invoices := tr getRootObject: 'invoices'.
    inv := Invoice withAll: {
        'number' -> 1043.
        'total'  -> (Decimal fromString: '1250.00') }.
    tr setRootObject: 'invoices' value: (invoices setAt: 1043 value: inv)].
reader := db newTransaction.
((reader getRootObject: 'invoices') getAt: 1043) total.     "=> 1250.00"
((reader getRootObject: 'invoices') getAt: 1043) isPaid.    "=> false"
((reader getRootObject: 'invoices') getAt: 7) isNil.        "=> true"
```

`getRootObject:` records what the transaction read, the *read set*, and the commit checks it.
`getAt:` on a dictionary answers `nil` for an absent key. A `Decimal` is stored as a decimal, with
its trailing zeros: money does not go through `Float`.

An explicit transaction ends in `commit` or `abort`. After either, every message to it is a
`PBUserError`, so a transaction can never be used twice by mistake:

```smalltalk
reader abort.
reader isActive.                              "=> false"
outcome := [reader getRootObject: 'hits'] on: PBUserError do: [:e | e messageText].
outcome.                                      "=> 'The transaction is aborted; start a new one'"
```

## 6. Every collection message answers a new version

> **Read this before you write a line.** In protoBaseST, `add:`, `remove:`, `setAt:value:`,
> `removeAt:` and every other collection message **answer a new collection and leave the receiver
> unchanged**. The names are `proto_db`'s. Three of them mean something else in Pharo:
>
> | Message | Pharo | protoBaseST |
> |---|---|---|
> | `Set add:` | adds in place, answers the **element** | answers a **new set** |
> | `Set remove:` | removes in place, answers the element | answers a **new set** |
> | `List removeAt:` | removes in place, answers the element | answers a **new list** |
>
> A statement that discards the result changes nothing, and nothing fails.

```smalltalk
tags := PBSet new.
tags add: 'urgent'.
tags count.                                   "=> 0"
tags := tags add: 'urgent'.
tags count.                                   "=> 1"
(tags has: 'urgent').                         "=> true"
```

The first `add:` built a set and threw it away. Keep the answer.

Why the names were not changed: `proto_db`'s names are the documented API of the Python
implementation, and the point of this prototype is that one document explains both languages.
The cost is the trap above, paid by Smalltalk programmers. `docs/decisions.md` records the call
and the alternatives (`copyWith:`, `copyWithout:`); the workshop is where it can be overruled.

## 7. Lists count from zero

> **`PBList` positions are zero-based.** `getAt: 0` is the first element. This is deliberate:
> `proto_db`'s `List` is zero-based, and the persisted tree nodes store counts that are the same in
> both languages. `getAt: -1` is the last element. A position out of range is a
> `PBValidationError`, never `nil`. Every other protoBaseST collection is unaffected: a `PBFrozenList`,
> a `PBTuple` or an `Array` you build yourself are ordinary one-based Smalltalk collections.

```smalltalk
lines := PBList new.
lines := (lines appendLast: 'a') appendLast: 'c'.
lines := lines insertAt: 1 value: 'b'.
lines elements.                               "=> #('a' 'b' 'c')"
lines getAt: 0.                               "=> 'a'"
lines getAt: -1.                              "=> 'c'"
outcome := [lines getAt: 3] on: PBValidationError do: [:e | e messageText].
outcome.                                      "=> 'List position 3 out of range for a list of 3'"
(lines sliceFrom: 1 to: nil) elements.        "=> #('b' 'c')"
(lines removeAt: 0) elements.                 "=> #('b' 'c')"
lines count.                                  "=> 3"
```

`insertAt: n value:` with `n` equal to the count appends. `sliceFrom:to:` follows Python's slice
rules, so `nil` is an open end. The last two lines show again the rule of section 6: `removeAt:`
answered a new list, and `lines` still has three elements.

An error rather than `nil` for a bad position is `proto_db`'s rule too (`tests/unit/list_positions.st`
records `proto_db`'s own answers next to this one's). A silent `nil` in a database hides an
off-by-one for as long as the data lives.

## 8. Keys, and what the format compares

The format has its own idea of when two keys are equal, and the database follows it, not
protoST's `=`. Python and protoST must agree on every key of a shared file, and protoST's `=`
would coerce through doubles.

```smalltalk
totals := PBDictionary new.
totals := totals setAt: 1043 value: 12.
totals := totals setAt: 1043.0 value: 13.
totals count.                                 "=> 1"
totals := totals setAt: (Decimal fromString: '1043.00') value: 14.
totals count.                                 "=> 1"
(totals getAt: 1043).                         "=> 14"
(totals has: true).                           "=> false"
```

`1043`, `1043.0` and `Decimal 1043.00` are one key. `true` is a key of its own, not `1`.
Dictionaries iterate in key order, not insertion order:

```smalltalk
totals := totals setAt: 'x' value: 0.
totals keys.                                  "=> #(1043 'x')"
```

(Numbers order before strings, as in the format's order key. The order is part of the
format, so both languages iterate alike.)

## 9. Records change by new versions

```smalltalk
paid := inv with: 'paidOn' value: (CalendarDate year: 2026 month: 11 day: 11).
paid isPaid.                                  "=> true"
inv isPaid.                                   "=> false"
inv = paid.                                   "=> false"
paid number.                                  "=> 1043"
```

`inv` and `paid` are two atoms, two identities. Storing `paid` in the dictionary is another new
version of the dictionary, written in a transaction:

```smalltalk
db newTransactionDo: [:tr |
    invoices := tr getRootObject: 'invoices'.
    tr setRootObject: 'invoices' value: (invoices setAt: 1043 value: paid)].
((db newTransaction getRootObject: 'invoices') getAt: 1043) isPaid.     "=> true"
```

Nothing was deleted: the version where invoice 1043 is unpaid is still in the file (section 12).

## 10. Conflicts and retries

A transaction that *read* a root and then wrote it is protected: if somebody else committed that
root meanwhile, the commit fails, because the value the transaction computed from is stale.

```smalltalk
reader := db newTransaction.
reader getRootObject: 'hits'.
db newTransactionDo: [:other | other setRootObject: 'hits' value: 7].
reader setRootObject: 'hits' value: 8.
outcome := [reader commit. 'committed'] on: PBConflictError do: [:e | e messageText].
outcome.                                      "=> 'Root ''hits'' of database ''erp'' was changed by a concurrent commit'"
reader isActive.                              "=> false"
```

`run:` is the usual shape for a read-modify-write: on `PBConflictError` it starts a fresh
transaction and runs the block again, after a short, randomised, growing wait, up to ten times.
Because the block can run more than once, it must have no effect outside the transaction. Here
the first attempt is made to conflict on purpose:

```smalltalk
attempts := 0.
db run: [:tr |
    attempts := attempts + 1.
    v := tr getRootObject: 'hits'.
    attempts = 1 ifTrue: [
        db newTransactionDo: [:rival | rival setRootObject: 'hits' value: 100]].
    tr setRootObject: 'hits' value: v + 1].
attempts.                                     "=> 2"
(db newTransaction getRootObject: 'hits').    "=> 101"
```

`PBOutcomeUnknownError` (the commit may or may not have happened) is never retried, because
running the block again could apply it twice. Any other error aborts and propagates.

## 11. Blind writes merge

Conflicts are checked on what a transaction *read*. A transaction that builds a collection from
nothing and writes it, without reading the root, has no stale input to protect. When both of two
such transactions write different keys, nobody should lose:

```smalltalk
reader := db newTransaction.
other := db newTransaction.
reader setRootObject: 'tags' value: (reader newDictionary setAt: 'urgent' value: true).
other setRootObject: 'tags' value: (other newDictionary setAt: 'paid' value: false).
reader commit.
other commit.
seen := (db newTransaction getRootObject: 'tags') keys.
seen.                                         "=> #('paid' 'urgent')"
```

The second commit did not replace the first one's dictionary. Each collection version remembers
the operations that built it (`opLog`), and when a root was written but not read, the commit
*replays those operations* onto the version that is current. Both tags survive and neither side
retried.

```smalltalk
mine := PBDictionary new setAt: 'a' value: 1.
theirs := PBDictionary new setAt: 'b' value: 2.
mine opLog.                                   "=> PBFrozenList(PBTuple('set', 'a', 1))"
(mine rebaseOnto: theirs) keys.               "=> #('a' 'b')"
```

If the second transaction had *read* `tags` first, it would have conflicted instead, and
`setRootObject:value:replace: true` says "last writer wins" explicitly. The merge is only defined
for the collections that support it (`PBDictionary`, `PBHashDictionary`, `PBSet`,
`PBCountedSet`). A write that cannot be merged replaces, as `proto_db` does; an *indexed*
collection is refused outright (section 13).

## 12. Mutable objects, history and as-of reads

```smalltalk
acme := PBMutableObject name: 'customer:acme'.
db newTransactionDo: [:tr | tr newMutable: acme name value: 'ACME S.A.'].
moment1 := db history first committedAt.
db newTransactionDo: [:tr | acme set: tr value: 'ACME Argentina S.A.'].
moment2 := db history first committedAt.
acme get: db newTransaction.                  "=> 'ACME Argentina S.A.'"
```

`acme` is a handle: it holds a name, not a value, and it is itself immutable. `get:` and `set:value:`
take the transaction. `newMutable:value:` requires that the cell does not exist yet.

Every committed version stays readable. `db history` answers `PBHistoryEntry` objects, newest
first; `snapshotAt:` opens one entry for reading. `proto_db` has no "as of a moment" message; it is
a three-line helper, and a script has no class to hold it, so it is a block:

```smalltalk
asOf := [:moment |
    | entry |
    entry := db history detect: [:each | each committedAt <= moment]
        ifNone: [PBUserError signal: 'the database did not exist yet'].
    db snapshotAt: entry].
(asOf value: moment1) getMutable: 'customer:acme'.      "=> 'ACME S.A.'"
(asOf value: moment2) getMutable: 'customer:acme'.      "=> 'ACME Argentina S.A.'"
db history last version.                      "=> 0"
(db snapshotAt: db history last) rootNames.   "=> #()"
```

A moment is the `committedAt` of a version, taken from the history, never from a wall clock.
That keeps the example deterministic, and it is the honest way to ask "what did the database say
at this commit". Commit times are never decreasing but may repeat, which is why the helper takes
the newest entry at or before the moment.

## 13. What the prototype refuses, and what each refusal protects

The prototype's rule is: if a value, a type, a version or an operation cannot be stored exactly,
say so, naming it. A silent approximation in a database is found years later. Each refusal below
is a `PBValidationError` raised when you write, not when you commit.

```smalltalk
outcome := [totals setAt: 'k' value: Dictionary new] on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'its order is unspecified'.      "=> true"
outcome := [totals setAt: 'k' value: (1/2)] on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'a Fraction cannot be stored'.   "=> true"
outcome := [totals setAt: 'k' value: #invoice] on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'a Symbol cannot be stored'.     "=> true"
outcome := [totals setAt: (PBFrozenList withAll: #(1)) value: 0] on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'not an orderable key'.          "=> true"
outcome := [db newTransactionDo: [:tr | tr setRootObject: '__x' value: 1]]
    on: PBValidationError do: [:e | e messageText].
outcome includesSubstring: 'reserved for the format'.       "=> true"
```

- **A `Dictionary` is refused** because its order is unspecified in protoST, and in the format
  the order of a map is part of its bytes. Use `PBFrozenDict`, which keeps insertion order, or a
  `PBDictionary` (a database collection).
- **A `Fraction` is refused** because `1/2` has no kind in the format. Storing it as a float
  would be a different number; storing it as a string would be a different kind.
- **A `Symbol` is refused**, with one trap: in protoST a literal of six bytes or fewer, such as
  `#paid`, *is* the `String` `'paid'`, so it is accepted as a string. `#invoice` is a real
  `Symbol` and is refused. Nothing in a stored file depends on telling them apart. When the
  format gains a symbol kind, protoST will get an explicit wrapper for it.
- **A list is not a key**, as in Python: a key must be orderable, and lists and maps are not.
  Use a `PBTuple`.
- **A root name starting with `__`** belongs to the format.

Reading is as explicit as writing. Data this version cannot interpret is `PBCorruptionError`
(damaged or malformed) or `PBNotSupportedError` (valid, but outside what the prototype handles:
for example a record of a type with no class here is a `PBOpaqueAtom`, readable field by field and
refused for anything else). `docs/deviations.md` lists every refusal and divergence.

## 14. One directory, two languages

The point of keeping `proto_db`'s format is that the files are shared. `proto_db`'s own verifier
accepts what protoBaseST writes:

```sh
python -m proto_db.tools.verify DIR
```

Its prerequisites: `proto_db` at `v2.0.0rc4` importable (`v2.0.0rc2` before the cluster branch; `tests/interop/setup_venv.sh` builds a venv
with it), `msgpack` 1.2.0 or newer, and `DIR` the path the script's `dir` holds
(`dir pathString`, under `FileSystem temp`). Run it **before the last block of section 15**: that
block closes the space and deletes the directory.

The verifier is outside this repository (it is `proto_db`'s). What is checked here, in
`tests/interop/`, is that spaces written by protoST pass it with an identical dump, spaces written
by Python are dumped identically by protoST, commits from both languages stack on one directory,
and concurrent commits from both get `proto_db`'s outcomes in 27 scenarios.
`examples/erp/` is a worked demo: Python creates customers and invoices, protoST records payments
and renames a customer, a blind write from each language merges, and both print the same as-of
report. See [examples/erp/README.md](../../examples/erp/README.md).

Not proven: anything outside those scenarios, any `proto_db` release other than `v2.0.0rc2` (the cluster
branch moves the venv to `v2.0.0rc4`; the cluster's data interop is tested at rc4, and the whole
interop suite runs against it in the final verification, cluster Task 30), and
behaviour under load (the AVL structures are many times slower than `proto_db`'s; the dated figures
are in [deviations.md](../deviations.md#performance)).

## 15. Where to go next

```smalltalk
space close.
dir deleteAll.
space isClosed.                               "=> true"
```

- [reference.md](../reference.md): every public class and message.
- [deviations.md](../deviations.md): everything that differs from `proto_db`, and every refusal.
- [not-done.md](../not-done.md): what is not here, and the cost of each omission.
- [decisions.md](../decisions.md): the choices, with what each one costs if it is wrong.
- [README.md](README.md): the chaptered tutorial, twelve small self-checking programs one
  concept each, and two orientation chapters, coming from GemStone/S and coming from Soil.

The questions this prototype exists to ask the workshop are in the README.

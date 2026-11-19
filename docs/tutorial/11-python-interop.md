# 11. One directory, two languages

<!-- example: examples/tutorial/_interop_write.st -->
<!-- example: examples/tutorial/11_python_side.py -->
<!-- example: examples/tutorial/_interop_read.st -->
<!-- example: examples/tutorial/_indexed_change.st -->
<!-- example: examples/tutorial/11_indexed_python_side.py -->
Program: [examples/tutorial/11_python_interop.sh](../../examples/tutorial/11_python_interop.sh),
which runs [_interop_write.st](../../examples/tutorial/_interop_write.st),
[11_python_side.py](../../examples/tutorial/11_python_side.py) and
[_interop_read.st](../../examples/tutorial/_interop_read.st) on one directory; and, for the
indexed section, [examples/tutorial/11_indexed_interop.sh](../../examples/tutorial/11_indexed_interop.sh).
Previous: [10. Crashes and reopening](10-crash-recovery.md). Next: [12. What is refused, and why](12-refusals.md).

This is the reason protoBaseST exists. It is not a Smalltalk database with an export format: its
files *are* `proto_db`'s files (format 4, `proto_db` at `v2.0.0rc2`), so a Python program and a
protoST program open the same directory, read the same versions and commit on top of each other.

## protoST writes

```smalltalk
PBObject subclass: #Book.

Book class >> typeName
  ^ 'tutorial.interop.Book'.

PBObjectSpace registerAtomClass: Book.
```

```smalltalk
db newTransactionDo: [:tr |
    tr newMutable: author name value: 'Adele Goldberg'.
    tr setRootObject: 'books' value: ((tr newDictionary
        setAt: 1 value: (Book withAll: {
            'title' -> 'Smalltalk-80: The Language'.
            'author' -> author.
            'price' -> (Decimal fromString: '54.90').
            'published' -> (CalendarDate year: 1989 month: 1 day: 1).
            'cover' -> #[137 80 78 71] }))
```

## Python reads, and commits

The Python class declares the same type name; the name, not the class, is what the file holds:

```python
class Book(DBObject):
    """A book, the Python class of tutorial.interop.Book."""

    __type_name__ = "tutorial.interop.Book"
    __type_aliases__ = ()
```

```python
    first = books.get_at(1)
    assert isinstance(first, Book), type(first)
    assert first.title == "Smalltalk-80: The Language", first.title
    assert first.price == Decimal("54.90") and str(first.price) == "54.90", first.price
    assert first.published == date(1989, 1, 1), first.published
    assert first.cover == b"\x89PNG", first.cover
    assert first.author.get(tx) == "Adele Goldberg"
```

Each value arrives as the Python value of its kind: a `Decimal` with its scale, a `date`, `bytes`,
a `MutableObject` that reads the same cell. Python then adds a book, renames the author through
the cell and writes a tag blindly, in one commit:

```python
    def work(tx):
        books = tx.get_root_object("books")
        tx.set_root_object("books", books.set_at(3, Book(
            title="Smalltalk-80: The Interactive Programming Environment",
            author=books.get_at(1).author,
            price=Decimal("47.50"),
            published=date(1984, 1, 1),
            cover=b"")))
        tx.set_mutable("author:goldberg", "Adele J. Goldberg")
        tx.set_root_object("tags", tx.new_dictionary().set_at("from", "python"))
```

`proto_db`'s own verifier (`python -m proto_db.tools.verify DIR`) then checks the whole
directory.

## protoST reads Python's commit

```smalltalk
lesson check: 'Python''s book is a Book here' is: third class equals: Book.
lesson check: 'its title' is: (third at: 'title') equals: 'Smalltalk-80: The Interactive Programming Environment'.
lesson check: 'its price, a Decimal with its scale' is: (third at: 'price') printString equals: '47.50'.
lesson check: 'its date' is: (third at: 'published') equals: (CalendarDate year: 1984 month: 1 day: 1).
lesson check: 'its author is the same cell' is: (third at: 'author') name equals: 'author:goldberg'.
lesson check: 'renamed by Python' is: ((third at: 'author') get: tr) equals: 'Adele J. Goldberg'.
```

```smalltalk
db newTransactionDo: [:t | t setRootObject: 'tags' value: (t newDictionary setAt: 'and' value: 'protoST')].
lesson check: 'both tags, merged' is: (db newTransaction getRootObject: 'tags') keys equals: #('and' 'from').
```

The blind write from protoST merges with Python's, exactly as two protoST writers merge
(chapter 6): the merge is defined by the format's operation log, not by either language.

## What makes it possible, and what it costs

- The type name is language-neutral, and behaviour lives in each language's class.
- Keys compare by the format's order key (chapter 4), so both languages agree on every key.
- Every value a program stores must have an exact kind in the format, which is why chapter 12 is
  a list of refusals.
- Names are `proto_db`'s, including the ones that surprise Smalltalk programmers (chapter 2).

What was checked, against `proto_db` at `v2.0.0rc2` (README, "Status"): the conformance vectors,
round trips in both directions with identical dumps, tree shapes node by node, 27
concurrent-commit scenarios with both languages in both roles, crash states, and the ERP demo
([examples/erp/](../../examples/erp/README.md)). Nothing outside those scenarios is claimed, and no
other `proto_db` release.

Python's `proto_db` can do things this prototype cannot, on the same directory: maintain and query
indexes, write `RepeatedKeysDictionary`, run a cluster. A directory that uses them is still read by
protoST, which refuses only the changes it cannot make exactly. Index maintenance and queries come
with 0.3.0 (in progress); the next section shows the interplay.

## Indexes, from both sides

> **In progress for protoBaseST 0.3.0** (the
> [indexed-queries spec](../superpowers/specs/2026-11-18-indexed-queries-design.md), chapter 17).
> The code comes from [11_indexed_interop.sh](../../examples/tutorial/11_indexed_interop.sh),
> which runs [11_indexed_python_side.py](../../examples/tutorial/11_indexed_python_side.py)
> and [_indexed_change.st](../../examples/tutorial/_indexed_change.st) on one directory; it runs
> as a test against the pinned `proto_db` (and is skipped, exit 77, without the interop venv).

Python writes forty people and indexes them:

```python
        for i in range(40):
            people = people.set_at(i, tr.new_object(name=f"person{i}", city=CITIES[i % 4], age=18 + i))
        people = people.add_index(EqualityIndex("by_city", "city")).add_index(RangeIndex("by_age", "age"))
        tr.set_root_object("people", people)
```

protoST queries those indexes, changes the collection through its mutators, and merges a blind
write onto it:

```smalltalk
people := db newTransaction getRootObject: 'people'.
lesson check: 'Python''s indexes are read' is: people indexNames equals: #('by_age' 'by_city').
lesson check: 'and queried here' is: (inOslo value: people) equals: 10.
db run: [:tr | | ps |
    ps := tr getRootObject: 'people'.
    ps := ps setAt: 0 value: ((ps getAt: 0) with: 'city' value: 'Oslo').
    ps := ps removeAt: 1.
    ps := ps setAt: 40 value: (tr newObject: { 'name' -> 'person40'. 'city' -> 'Oslo'. 'age' -> 58 }).
    tr setRootObject: 'people' value: ps].
```

```smalltalk
mine := db newTransaction.
mine setRootObject: 'people' value: (mine newDictionary
    setAt: 41 value: (mine newObject: { 'name' -> 'person41'. 'city' -> 'Oslo'. 'age' -> 59 })).
mine commit.
```

Python then checks every index against a scan, plans the same query with the same index, and runs
`proto_db`'s verifier on the directory:

```python
    people.validate()
    assert people.index_names() == ["by_age", "by_city"], people.index_names()
    oslo = from_collection(people).where(F.city == "Oslo")
    assert oslo.explain()["plan"] == "IndexLookup", oslo.explain()
    assert oslo.count() == 12, oslo.count()
```

For this to hold, protoBaseST must write the index trees `proto_db` would have written for the same
changes, node for node: the same keys, the same tree shapes, the same order of index updates in
every mutator (spec 5.4). That is checked by the interop tests of spec 6.1, which run the same
seeded operations in both languages and compare the dumps, and by this lesson's last step:
`proto_db` validates every index protoST changed and its verifier accepts the directory.

## Running it

The lesson needs the pinned `proto_db` in a venv; without it, it is skipped (exit 77):

```sh
PYTHON=python3.14 tests/interop/setup_venv.sh
PROTOST=../protoST/build_release/protost examples/tutorial/11_python_interop.sh
```

## What to take away

- One directory, two languages, the same versions, merges across languages.
- The price is a format discipline on every value, and `proto_db`'s names.

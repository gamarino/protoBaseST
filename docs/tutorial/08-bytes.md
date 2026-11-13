# 8. Bytes and the cost of a version

<!-- example: examples/tutorial/08_bytes.st -->
Program: [examples/tutorial/08_bytes.st](../../examples/tutorial/08_bytes.st).
Previous: [7. Mutable objects and history](07-mutables-and-history.md). Next: [9. Actors](09-actors.md).

## A `ByteArray` is a value

```smalltalk
photo := ByteArray randomBytes: 1048576.
db newTransactionDo: [:t |
    t setRootObject: 'cover' value: photo.
    t setRootObject: 'views' value: 0].
```

A `ByteArray` is stored as the format's bytes kind, read back byte for byte, and read by Python
as `bytes`. protoST's `ByteArray` is immutable, so it fits the model without a copy.

There is no separate BLOB or stream API. The format has BLOB records, and `proto_db`'s storage
layer can write them; protoBaseST does not write them, and refuses one where it expects a record.
A large value is an ordinary value: inside a collection, a byte string of 256 bytes or more is
stored in a box of its own (a value box, as in `proto_db`), so the tree node that holds it stays
small.

## What a new version costs

```smalltalk
grew := scan value.
1 to: 10 do: [:i | db run: [:t | t setRootObject: 'views' value: (t getRootObject: 'views') + 1]].
grew := scan value - grew.
lesson say: 'ten small commits wrote ' , grew printString , ' bytes'.
lesson check: 'they did not copy the cover' isTrue: grew < 20000.
```

Ten commits that do not touch the 1 MiB cover wrote about 9 KB in all (the figure the program
printed on the machine where it was written; it varies a little). A new version is written as the
records that changed plus the path to them; everything else is referred to where it already is.

A value that changes is written again whole:

```smalltalk
db newTransactionDo: [:t |
    t setRootObject: 'cover' value: ((photo copyFrom: 1 to: 1048575) , #[0])].
grew := scan value - grew.
lesson check: 'a changed value is written whole' isTrue: grew > 1048576.
```

So large data that changes in parts is better split into parts. A `PBList` of chunks is one way:

```smalltalk
db newTransactionDo: [:t |
    | list |
    list := t getRootObject: 'chunked'.
    t setRootObject: 'chunked' value: (list setAt: 5 value: (ByteArray new: 65536))].
grew := scan value - grew.
lesson say: 'changing one 64 KiB chunk wrote ' , grew printString , ' bytes'.
lesson check: 'one chunk, not the MiB' isTrue: grew < 100000.
```

Every older version still holds its chunks, so history costs what changed, and nothing more.

## Limits

A segment file rolls over before it exceeds 256 MiB, as `proto_db`'s does; a record payload is
limited by the format's 32-bit length. Nothing near those sizes has been run, and nothing about
memory or long runs is claimed ([not-done.md](../not-done.md)). Since nothing is ever deleted, a
database that rewrites large values often grows by their size each time.

## What to take away

- Bytes are values; there is no BLOB API.
- A version writes what changed; split large, changing data into parts.

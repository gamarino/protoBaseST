"""Lesson 11, Python's step: read what protoST wrote, then commit to the same directory.

Usage: python 11_python_side.py <directory>
Run by 11_python_interop.sh with the pinned proto_db (tests/interop/setup_venv.sh).

The record type is declared under the same language-neutral name as in protoST
(``tutorial.interop.Book``); that name is what the file holds. Every read is asserted, so a
wrong value stops the script with an AssertionError and a non-zero exit.
"""
import sys
from datetime import date
from decimal import Decimal

from proto_db import DBObject, FileStorage, ObjectSpace


class Book(DBObject):
    """A book, the Python class of tutorial.interop.Book."""

    __type_name__ = "tutorial.interop.Book"
    __type_aliases__ = ()


space = ObjectSpace(FileStorage(sys.argv[1]))
try:
    db = space.open_database("library")
    tx = db.new_transaction()
    books = tx.get_root_object("books")
    first = books.get_at(1)
    assert isinstance(first, Book), type(first)
    assert first.title == "Smalltalk-80: The Language", first.title
    assert first.price == Decimal("54.90") and str(first.price) == "54.90", first.price
    assert first.published == date(1989, 1, 1), first.published
    assert first.cover == b"\x89PNG", first.cover
    assert first.author.get(tx) == "Adele Goldberg"
    assert books.get_at(2).author.name == "author:goldberg"
    tx.abort()
    print("python read: %s, %s, %s" % (first.title, first.price, first.author.name))

    # A new book, the author renamed, and a blind tag, in one Python commit.
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

    db.run(work)
    print("python committed version %d" % db.history()[0].version)
finally:
    space.close()

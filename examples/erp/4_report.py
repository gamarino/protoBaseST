"""Step 4, Python: the as-of report. 4_report.st prints the same text.

Usage: python 4_report.py <directory>

Three moments, each the committedAt of a commit made by an earlier step (version 1: created,
2: paid, 3: renamed), never a clock reading. as_of finds the newest version committed at or
before a moment (design spec 6.5), and the report reads that version only. Two commits with
the same timestamp would resolve to the newer one, so the script refuses to run unless the
three moments are strictly increasing, and it checks that as_of found the version it meant.
"""
import sys

from erp_model import Invoice  # noqa: F401  (registers the ERP types)
from proto_db import FileStorage, ObjectSpace

MOMENTS = [(1, "invoices created"), (2, "payments recorded"), (3, "ACME renamed")]


def as_of(db, moment):
    """The snapshot of the newest version committed at or before `moment`."""
    entry = next((e for e in db.history() if e.committed_at <= moment), None)
    if entry is None:
        raise ValueError("the database did not exist yet")
    return db.snapshot_at(entry)


def money(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def report(snapshot, title):
    invoices = list(snapshot.get_root_object("invoices").values())
    print(f"== {title} (version {snapshot.version}) ==")
    for cell in snapshot.mutable_names:
        mine = [i for i in invoices if i.customer.name == cell]
        billed = sum(int(i.total * 100) for i in mine)
        paid = sum(int(i.total * 100) for i in mine if i.is_paid())
        print(f"{cell} | {snapshot.get_mutable(cell).name} | {len(mine)} invoices"
              f" | billed {money(billed)} | paid {money(paid)}")
    paid_numbers = " ".join(str(i.number) for i in invoices if i.is_paid())
    print(f"paid invoices: {paid_numbers or 'none'}")


def main(directory):
    space = ObjectSpace(FileStorage(directory))
    try:
        db = space.open_database("erp")
        committed_at = {entry.version: entry.committed_at for entry in db.history()}
        moments = [committed_at[version] for version, _ in MOMENTS]
        if not moments[0] < moments[1] < moments[2]:
            raise SystemExit("two demo commits share a timestamp: the moments cannot be told apart")
        for version, title in MOMENTS:
            snapshot = as_of(db, committed_at[version])
            if snapshot.version != version:
                raise SystemExit(f"as_of found version {snapshot.version}, not {version}")
            report(snapshot, f"moment {version}: {title}")
        tags = db.snapshot_at(db.history()[0]).get_root_object("tags")
        print("tags now: " + " ".join(f"{number}={tag}" for number, tag in tags.items()))
    finally:
        space.close()


if __name__ == "__main__":
    main(sys.argv[1])

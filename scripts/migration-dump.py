"""Dump a Captain's Log store as stable text: rows keyed by ZID, relationships as ZID pairs.

Primary keys and join-table names get renumbered by a migration, so neither appears in the output.
Usage: python3 -I scripts/migration-dump.py <store> [--skip TABLE.COLUMN ...]
"""
import sqlite3
import sys

path = sys.argv[1]
skip = set(sys.argv[sys.argv.index("--skip") + 1:]) if "--skip" in sys.argv else set()
db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)

ents = {n: name for n, name in db.execute("select Z_ENT, Z_NAME from Z_PRIMARYKEY where Z_ENT < 16000")}
table_of = {name: "Z" + name.upper() for name in ents.values()}
ids = {}
for name, table in table_of.items():
    ids[name] = dict(db.execute(f"select Z_PK, ZID from {table}"))

# To-one foreign keys: column -> target entity. Add new to-one relationships here.
fks = {
    "ZCALENDAREVENT": "CalendarEvent", "ZMEETING": "Meeting", "ZCOMPLETEDINMEETING": "Meeting",
    "ZINTERVIEW": "Interview", "ZPROJECT": "Project", "ZPERSON": "Person", "ZAUTHOR": "Person",
    "ZCOINTERVIEWER": "Person", "ZPULLREQUEST": "PullRequest",
}

def fmt(v):
    if isinstance(v, bytes):
        return "blob:" + v.hex()
    return repr(v)

out = []
for name, table in sorted(table_of.items()):
    cols = [r[1] for r in db.execute(f"pragma table_info({table})")]
    keep = [c for c in cols if c not in ("Z_PK", "Z_ENT", "Z_OPT") and f"{table}.{c}" not in skip]
    rows = db.execute(f"select {', '.join(keep)} from {table}").fetchall()
    out.append(f"## {name} rows={len(rows)}")
    lines = []
    for row in rows:
        d = dict(zip(keep, row))
        parts = []
        for c in sorted(keep):
            v = d[c]
            if c in fks and v is not None:
                v = "->" + ids[fks[c]][v].hex() if isinstance(ids[fks[c]][v], bytes) else ids[fks[c]][v]
            parts.append(f"{c}={fmt(v)}")
        lines.append(" ".join(parts))
    out.extend(sorted(lines))

# Many-to-many join tables: columns are Z_<ent><NAME>; resolve both sides to entity + ZID.
joins = [r[0] for r in db.execute("select name from sqlite_master where type='table' and name like 'Z\\_%' escape '\\'")
         if r[0] not in ("Z_METADATA", "Z_MODELCACHE", "Z_PRIMARYKEY")]
pairs = []
for t in joins:
    cols = [r[1] for r in db.execute(f"pragma table_info({t})")]
    sides = []
    for c in cols:
        rest = c[2:]
        digits = rest[:len(rest) - len(rest.lstrip("0123456789"))]
        sides.append((ents[int(digits)], c[2 + len(digits):].rstrip("0123456789")))
    for a, b in db.execute(f"select {cols[0]}, {cols[1]} from {t}"):
        ida, idb = ids[sides[0][0]][a], ids[sides[1][0]][b]
        ida, idb = (x.hex() if isinstance(x, bytes) else x for x in (ida, idb))
        # Name the pair by both relationship names so it is the same whichever side owns the table.
        key = sorted([(sides[0][0], sides[0][1], ida), (sides[1][0], sides[1][1], idb)])
        pairs.append(f"{key[0][0]}.{key[0][1]}={key[0][2]} <-> {key[1][0]}.{key[1][1]}={key[1][2]}")
out.append(f"## joins pairs={len(pairs)}")
out.extend(sorted(pairs))
print("\n".join(out))

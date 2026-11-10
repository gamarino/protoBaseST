# protoBaseST

A perennial object database for protoST, in the tradition GemStone opened.

protoBaseST is a Smalltalk implementation, on protoST, of ProtoBase (the Python package `proto_db`).
It reads and writes the same on-disk format (format 4, frozen at ProtoBase `v2.0.0rc1`), so one
database directory can be shared by Python and Smalltalk programs.

Status: proposal prototype for discussion at the FAST Smalltalk workshop (2026-12-03). Not a product.

Design: [docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md](docs/superpowers/specs/2026-11-10-protobasest-prototype-design.md)

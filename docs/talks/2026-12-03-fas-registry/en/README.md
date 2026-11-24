# protoBaseST and the registry — FAS, 2026-12-03 — English materials

A talk for the Fundación Argentina de Smalltalk: one hour on the state of protoBaseST (a perennial
object database for protoST, in the tradition GemStone opened, which gives the same answers, the
same plans and the same bytes as `proto_db`, on an immutable model), followed by an open discussion
of `proto_db`'s registry of extensible models and how it might be adapted to Smalltalk. The second
part asks rather than announces: nothing has been decided for protoBaseST.

It is separate from the hands-on workshop of the same day,
[`../../2026-12-03-fas-workshop/`](../../2026-12-03-fas-workshop/README.md) (six exercises and the
volunteer project menu), which this talk cites and does not repeat.

The Spanish materials in the parent folder are the reference. This folder holds the English deck;
the script (`../guion.md`) and the hard questions (`../preguntas-dificiles.md`) are in Spanish only.

| File | Contents |
| --- | --- |
| `deck.html` | The 37 slides in English, with speaker notes in `<aside>`; translated from `../deck.html` without adding or removing content |
| `../slides/protoBaseST-FAS-registry-2026-12-03-en.pdf` | This deck as a PDF, produced by `../render_pdf.py` |
| `../demos/orden-de-resolucion.st` | The diamond demo: protoST's lookup order and `super` against C3 (comments and output in English) |
| `../demos/esperado.out` | Its output, run on 2026-11-24 with protoST 0.17.0 |

## Notes on the translation

- Slide 9 shows the real output of workshop exercise 2, which prints in Spanish; it is left as run.
- Decimal commas in the Spanish figures are decimal points here (0,33× becomes 0.33×); no value
  was changed. Dates are written month/day in the tables (11/20 for November 20).

## Sources

The same as the Spanish README: protoBaseST's `CHANGELOG.md`, `docs/not-done.md`,
`docs/deviations.md` and `docs/decisions.md`; protoST 0.17.0's `CHANGELOG.md`, `docs/LANGUAGE.md`
and its explicit-state spec; and, for the registry, the ProtoBase repository
([gamarino/ProtoDB](https://github.com/gamarino/ProtoDB) on GitHub): `docs/decisions.md` D62, the
runtime-registry and semantic-model specs under `docs/superpowers/specs/`, and
`docs/source/design-guide/registry.rst` and `docs/source/tutorials/extensible-models.rst`. The
Python outputs on slides 25 and 26 are copied from `proto_db`'s tutorial, which prints them when
run; they were not re-run for this talk. Performance figures come from one machine, are dated, and
are indicative only.

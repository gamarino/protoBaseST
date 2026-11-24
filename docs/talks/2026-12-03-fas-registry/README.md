# protoBaseST y el registro — FAS, 3/12/2026

Charla para la Fundación Argentina de Smalltalk: una hora sobre el estado de protoBaseST (una base de
objetos perenne para protoST, en la tradición que abrió GemStone, que da las mismas respuestas, los
mismos planes y los mismos bytes que `proto_db`, sobre un modelo inmutable) y una segunda parte
abierta, de discusión, sobre el registro de modelos extensibles de `proto_db` y su posible
adaptación a Smalltalk. La segunda parte pregunta, no anuncia: para protoBaseST no hay nada decidido.

Es distinta del taller práctico del mismo día, [`../2026-12-03-fas-workshop/`](../2026-12-03-fas-workshop/README.md)
(seis ejercicios y el menú de proyectos para voluntarios), que esta charla cita y no repite.

## Archivos

| Archivo | Qué es |
| --- | --- |
| `deck.html` | Las slides en castellano (37): una `<section>` por slide de 1920×1080, notas del orador en `<aside>` |
| `en/deck.html` | Las mismas slides en inglés |
| `slides/protoBaseST-FAS-registro-2026-12-03.pdf` | El deck en castellano, en PDF |
| `slides/protoBaseST-FAS-registry-2026-12-03-en.pdf` | El deck en inglés, en PDF |
| `render_pdf.py` | Regenera los dos PDF con Chrome, Chromium o Edge headless |
| `guion.md` | El guion, con tiempos |
| `preguntas-dificiles.md` | Las preguntas difíciles, con respuestas honestas |
| `demos/orden-de-resolucion.st` | La demo del diamante: el orden de búsqueda y el `super` de protoST frente a C3 |
| `demos/esperado.out` | Su salida, corrida el 24/11/2026 con protoST 0.17.0 |
| `en/README.md` | Este README en inglés |

## Demos

```sh
# El ejercicio 2 del taller (slide 9)
cd docs/talks/2026-12-03-fas-workshop/ejercicios
STPATH=../../../../src protost 02-conflicto-y-reintento.st

# El diamante (slide 26)
cd docs/talks/2026-12-03-fas-registry/demos
protost orden-de-resolucion.st
```

protoBaseST 0.4.1 necesita protoST 0.17.0 y ya no usa `setInstVar:from:to:`, que 0.17.0 depreca: los
ejercicios corren sin aviso (slide 18). La demo del diamante no usa protoBaseST.

## Fuentes

- protoBaseST: `README.md`, `CHANGELOG.md` (0.1.0 a 0.4.0), `docs/not-done.md`,
  `docs/deviations.md` (Performance), `docs/decisions.md`, `docs/tutorial/`.
- protoST 0.17.0: `CHANGELOG.md`, `docs/LANGUAGE.md` §4.6, §4.10-4.13, `docs/STATUS.md` (D21, D63),
  `docs/superpowers/specs/2026-11-23-explicit-state-design.md` (§9, §13.2).
- El registro de `proto_db` (repositorio ProtoBase, en GitHub
  [gamarino/ProtoDB](https://github.com/gamarino/ProtoDB)): `CHANGELOG.md` [2.0.0rc4],
  `docs/decisions.md` D62, `docs/superpowers/specs/2026-11-14-runtime-registry-design.md`,
  `docs/superpowers/specs/2026-11-15-semantic-model-mvp-design.md`,
  `docs/source/design-guide/registry.rst`, `docs/source/tutorials/extensible-models.rst`.

Las cifras de rendimiento son de una máquina, con fecha, y son indicativas. Las salidas de Python
de las slides 25 y 26 están copiadas del tutorial de `proto_db`, que las imprime corriendo; no se
corrieron para esta charla.

## Regenerar los PDF

```sh
python3 render_pdf.py            # o: python3 render_pdf.py /ruta/a/chrome
```

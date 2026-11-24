# protoBaseST — FAST, 3/12/2026

Taller de dos horas y media a tres horas para la Fundación Argentina de Smalltalk, mitad protoST y mitad protoBaseST. Esta carpeta es la mitad de protoBaseST: una base de objetos perenne para protoST, en la tradición que abrió GemStone, que da las mismas respuestas, los mismos planes y los mismos bytes que `proto_db`, sobre un modelo inmutable. No es más rápida que `proto_db` (es varias veces más lenta, y las slides dicen cuánto, con fecha). El objetivo del taller es reclutar: salir con personas que tomen un proyecto del menú.

La mitad de protoST tiene sus propias slides y ejercicios, en el repositorio de protoST: [gamarino/protoST, `docs/talks/2026-12-03-fas-workshop/`](https://github.com/gamarino/protoST/tree/main/docs/talks/2026-12-03-fas-workshop).

## Agenda

| Hora | Bloque | Qué se hace |
| --- | --- | --- |
| 0:00 | Apertura | La apuesta: valores inmutables debajo de un lenguaje con estado |
| 0:05 | protoST | El lenguaje y su núcleo, con su laboratorio (materiales de protoST) |
| 1:10 | Corte | 10 minutos |
| 1:20 | protoBaseST | Modelo, transacciones, cluster, consultas, vectores; la historia del transporte TCP |
| 1:55 | Laboratorio | Ejercicios 1 a 6 de esta carpeta |
| 2:30 | Proyectos | El menú de proyectos para voluntarios: cada uno elige uno |
| 2:50 | Cierre | Preguntas difíciles y preguntas |

## Archivos

| Archivo | Qué es |
| --- | --- |
| `deck.html` | Las slides (fuente): una `<section>` por slide de 1920×1080, notas del orador en `<aside>` |
| `slides/protoBaseST-FAST-2026-12-03.pdf` | Las mismas slides en PDF (28) |
| `render_pdf.py` | Regenera el PDF desde `deck.html` con Chrome, Chromium o Edge headless |
| `ejercicios/` | Seis ejercicios, su salida esperada (`esperado/`) y `verificar.sh` |
| [`proyectos-voluntarios.md`](proyectos-voluntarios.md) | El menú: catorce proyectos en protoST, protoBaseST y protoIO, cada uno con su issue |

## Preparación

Necesitan protoST 0.17.0 o posterior (sobre protoCore 3.6.1 y protoIO 0.7.1): protoBaseST 0.5.0 lo verifica al cargar y, con uno anterior, `Import from: 'protobase'` señala `PBNotSupportedError` nombrando lo que falta. Cómo compilarlo está en el README de protoST; los requisitos, en el [README de protoBaseST](../../../README.md#requirements). Clonen este repositorio: los ejercicios usan su `src/`.

El ejercicio 6 (Python y Smalltalk sobre el mismo directorio) necesita además Python 3.12 o posterior y un clon de [protoBase](https://github.com/gamarino/ProtoDB) para armar el venv de `proto_db`:

```sh
git clone https://github.com/gamarino/ProtoDB ../ProtoBase
PROTOBASE_REPO=../ProtoBase tests/interop/setup_venv.sh
```

Sin el venv, `verificar.sh` saltea ese ejercicio.

## Ejercicios

| Ejercicio | Qué pone a prueba |
| --- | --- |
| `01-primer-commit.st` | Un espacio es un directorio; cada commit es una versión; la historia se lee; `add:` responde un set nuevo |
| `02-conflicto-y-reintento.st` | Instantáneas, conjunto de lectura, `PBConflictError`, `run:` con cuatro actores (el ejercicio 2 de protoST, en una base) |
| `03-indices-y-explain.st` | Índices de igualdad y rango, `explain`, filtros residuales, uniones, bloques opacos |
| `04-busqueda-vectorial.st` | `near:k:`, la condición dentro de la búsqueda, `fsum`, `pow` contra `*`, IVF con una sola lista |
| `05-cluster-dos-nodos.st` | Dos nodos: un commit de resultado desconocido, un timeout, y el valor que queda cuando el nodo vuelve |
| `06-python-y-smalltalk.sh` | protoST escribe, `proto_db` lee por el índice y confirma, su verificador acepta, protoST lee |

Desde `ejercicios/`, cada programa se corre con el `src/` del repositorio en el camino de módulos:

```sh
cd docs/talks/2026-12-03-fas-workshop/ejercicios
STPATH=../../../../src protost 01-primer-commit.st
```

`verificar.sh` corre los seis y compara cada salida con `esperado/NN.out`, salvo las líneas que empiezan con `~` (tiempos, reintentos y caminos, que cambian de corrida en corrida). Cada ejercicio deja su base en un directorio nuevo (por omisión, en el directorio temporal; `TALLER_DIR` lo cambia) y no la borra, para que la miren con `ls`.

```sh
PROTOST=/ruta/a/protost ./verificar.sh
```

Pasa con protoST 0.16.1 (23/11/2026, Linux, tres corridas seguidas, con el venv del ejercicio 6). El ejercicio 4 tarda unos 15 segundos y el 5 unos 6; los demás, uno o dos.

## Las cifras

Toda cifra de las slides sale de una corrida con fecha de [`docs/deviations.md`](../../deviations.md#performance) o del [CHANGELOG](../../../CHANGELOG.md), con sus unidades y su divisor, en una sola máquina: son indicativas.

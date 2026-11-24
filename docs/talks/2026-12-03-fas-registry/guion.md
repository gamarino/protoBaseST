# protoBaseST y el registro — guion de la charla (FAS, 3/12/2026)

Duración: una hora de estado de protoBaseST y una segunda parte abierta, de discusión, de 25 a 35
minutos. Las slides son `deck.html` (37); los números entre corchetes son los de cada slide.

Esta charla no es el laboratorio. Las slides prácticas, los seis ejercicios y el menú de proyectos
están en [`../2026-12-03-fas-workshop/`](../2026-12-03-fas-workshop/README.md); acá se citan, no
se repiten.

Toda cifra sale del repositorio, con su fecha: `CHANGELOG.md`, `docs/not-done.md`,
`docs/deviations.md` (Performance) y, para el registro, el repositorio ProtoBase
(`docs/decisions.md` D62, `docs/superpowers/specs/2026-11-14-runtime-registry-design.md`,
`docs/source/design-guide/registry.rst`, `docs/source/tutorials/extensible-models.rst`). Si una
cifra no está ahí, no se dice.

## Antes de empezar

- protoST 0.17.0 en el `PATH`, con este repositorio clonado.
- Demo 1 (el ejercicio 2 del taller):
  `cd docs/talks/2026-12-03-fas-workshop/ejercicios && STPATH=../../../../src protost 02-conflicto-y-reintento.st`.
- Demo 2 (el diamante): `cd docs/talks/2026-12-03-fas-registry/demos && protost orden-de-resolucion.st`;
  la salida esperada está en `demos/esperado.out` (corrida el 24/11/2026 con protoST 0.17.0).
- Si una demo falla en vivo, mostrar la slide: tiene la salida real.
- Pizarrón o un archivo abierto para anotar casos de uso durante la segunda parte.

---

## Primera parte: el estado (60 minutos)

### 0:00 — La promesa [1-3] (5 min)

- Quién y por qué: un experimento que busca entusiastas, no un producto que busca usuarios.
- La promesa, y la única: las mismas respuestas, los mismos planes y los mismos bytes que
  `proto_db`, sobre un modelo inmutable.
- Decir antes de que lo pregunten: es varias veces más lento, y está medido con fecha.
- Anunciar la forma de la charla: una hora contando, media hora preguntando.

### 0:05 — Qué es y sobre qué está hecho [4-7] (10 min)

- Una biblioteca, no un servidor; en la tradición que abrió GemStone, no su sucesor.
- La apuesta: valores inmutables debajo de un lenguaje con estado. protoST no es un Smalltalk
  mejor: es su código donde Smalltalk no llega (varios núcleos sin locks, una base compartida con
  Python, gemelos digitales).
- Las capas, y el directorio que abren los dos lenguajes.
- Cuatro versiones en diez días, cada una con lo que se verificó. Un implementador, con agentes de
  IA como herramientas, sin revisión externa.

### 0:15 — Transacciones [8-10] (10 min)

- Instantánea, conjunto de lectura, `PBConflictError`, `run:` reintenta. Granularidad honesta:
  raíces y celdas; GemStone es más fino.
- Demo 1 (o la slide 9): 40 de 40; los reintentos cambian, el resultado no.
- El patrón único, del atributo al commit, con la fila nueva de protoST 0.17.0
  (`update:with:`).

### 0:25 — Cluster, consultas, vectores [11-13] (12 min)

- Si el tiempo aprieta, una frase por slide y remitir al deck del taller.
- Cluster: tres finales de un commit; evidencia de un simulador y una máquina, no una prueba.
- Consultas: el mismo plan y el mismo costo en 314 consultas grabadas.
- Vectores: `fsum`, `pow` y no `*`, k-means operación por operación.

### 0:37 — Lo que cuesta y lo que no está probado [14-16] (9 min)

- El titular es la corrección: la tabla de cifras. La tarjeta de 0.17.0 dice solo lo que se
  corrió hoy (los ejercicios 1 a 5), no la suite.
- Los costos, con unidad, divisor y fecha. Ninguno es titular.
- La historia del transporte TCP, corta: el método (reproducir, escribir el test, arreglar donde
  está la causa, escribir lo que queda abierto).

### 0:46 — protoST 0.17.0 y la hoja de ruta [17-20] (12 min)

- Estado explícito: `constantNames:`, `writeOnceNames:`, `atomicNames:`, `update:with:`,
  `compareAndSet:from:to:`. Las clases de valor son 0.18.0, planeadas.
- Lo encontrado preparando la charla: `setInstVar:from:to:` está deprecado y se va en 0.18.0;
  protoBaseST 0.4.0 lo llamaba en 8 lugares de 3 archivos. 0.4.1 lo migró el mismo día y subió el
  piso a 0.17.0 (suite 315/0/3). La migración de fondo sigue siendo 0.5.0.
- 0.5.0 planeada (especificación de estado explícito §13.2); el resto son candidatos sin fecha, y
  el último es el registro.
- Lo que no hace y lo que no está probado.

---

## Segunda parte: el registro, abierta (25 a 35 minutos)

### 1:00 — Cambio de tono [21]

"Hasta acá conté; desde acá pregunto." Pedir que interrumpan.

### 1:01 — El espíritu [22-25] (10 min)

- El problema: un ERP chico multi-lenguaje (usuarios, grupos, personas, oportunidades) y módulos
  que extienden un modelo sin tocarlo, como el `_inherit` de Odoo. Por qué fallan las soluciones
  obvias.
- Los cuatro requisitos: una regla para campos y métodos; nada propio de un lenguaje en la base;
  las instalaciones nunca se pierden; todo error es explícito, pero un miss es `None`.
- El modelo: instancia, objeto de catálogo (una raíz por base), nombre de registro, cadena de
  extensiones, `base`. Lo que se guarda y lo que vive solo en memoria.
- El código Python del tutorial y su salida (copiada del tutorial; decirlo).

### 1:11 — Lo que existe y lo que no [26-29] (8 min)

- Demo 2: el mismo diamante en los dos lenguajes. En `proto_db`, C3 y un `_super()` cooperativo:
  Lead, Mailable, Schedulable, Thread. En protoST, el `super` de siempre: Lead, Mailable, Thread;
  y una jerarquía que C3 rechaza se acepta. No es un bug de protoST; es una decisión que hay que
  tomar.
- Implementado, diseñado, propuesto (slide 27): leerla tal cual; no agregar nada.
- Dónde lo construido se apartó de lo pedido el 8/11, con su razón.
- protoBaseST hoy conoce el formato 5 y lo rechaza; adoptarlo es un plan del tamaño del cluster.
  La spec de `proto_db` pide acordar el formato 5 con protoBaseST antes de congelarlo: hay margen.

### 1:19 — Adaptación y puntos fundamentales [30-35] (12 a 15 min)

- Las dos tablas de correspondencias: pedir correcciones, sobre todo en las columnas de Pharo y
  GemStone.
- Las tres opciones (A objeto, B clase compuesta, C prototipos): propuestas, ninguna prototipada.
  Pedir una cuarta.
- Los seis puntos fundamentales, de a dos por slide. En cada uno, leer la pregunta, decir lo que
  `proto_db` decidió, y quedarse callado esperando "lo que necesitamos de ustedes":
  1. evolución del esquema y migración;
  2. etiqueta de extensión;
  3. nombres y reflexión (`nil` o `doesNotUnderstand:`);
  4. herramientas;
  5. concurrencia (recarga explícita o automática);
  6. compatibilidad con código existente, y la pregunta de la demo: `super` cooperativo o no.

### 1:33 — Cómo participar y cierre [36-37] (2 a 5 min)

- Lo que más sirve: un caso, una historia, un boceto de API en cinco líneas. Un issue en
  protoBaseST titulado «registro: …» (no hay uno todavía: no inventarlo, abrirlo en vivo si sale
  algo).
- El menú del taller: catorce proyectos, cada uno con su issue.

## Lo que no se dice

- Que protoBaseST es sucesor de GemStone, o "un GemStone nuevo".
- Ninguna cifra de velocidad como argumento a favor.
- Que el registro existe en protoBaseST, o que alguna de las tres opciones está decidida.
- Que la suite completa de protoBaseST pasa sobre protoST 0.17.0 (no se corrió).
- Que los tests del registro de `proto_db` pasan "hoy": existen (unos 215 en nueve archivos) y
  forman parte de su release 2.0.0rc4, pero no se corrieron para esta charla.
- "ProtoDB": el producto es `proto_db`; el repositorio, ProtoBase.

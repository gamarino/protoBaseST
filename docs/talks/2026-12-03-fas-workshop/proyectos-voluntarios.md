# Proyectos para voluntarios — FAST, 3/12/2026

El taller tiene un objetivo concreto: que algunos de ustedes salgan con un proyecto elegido. Este es el menú. Cada proyecto sale de un ítem abierto de los documentos del repositorio (`docs/not-done.md` de protoBaseST, `docs/STATUS.md` de protoST, la especificación de estado explícito en revisión) y tiene un issue en GitHub donde se conversa.

**Cómo elegir.** Lean el *por qué*, miren el tamaño y los requisitos, y hagan el *primer paso*: es un archivo para leer y un comando para correr, pensado para que en una tarde sepan si el proyecto les gusta. Después comenten en el issue que lo toman (o que lo están mirando): así no hay dos personas haciendo lo mismo sin saberlo. Los marcados **primer issue** son buenos para empezar: el alcance está acotado y el camino, escrito.

**Tamaños.** **S**: de unas horas a dos días. **M**: de una a tres semanas de tardes. **L**: de uno a tres meses; conviene partirlo, y el issue propone cómo.

**Cómo se trabaja en estos repositorios.** Primero se mide o se reproduce, después se escribe el test que falla, después se arregla. Toda cifra lleva fecha, máquina, unidades y divisor. Una diferencia con `proto_db` se registra en `docs/deviations.md` con su razón y su costo; lo que falta, en `docs/not-done.md`. Los repositorios están en inglés: issues, commits y código.

**Mentores.** En cada proyecto dice "a confirmar": la conversación empieza en el issue, y el mantenedor (Gustavo Marino) responde ahí y asigna quién acompaña. No hay canal privado: todo queda en el issue.

| # | Proyecto | Repo | Tamaño | Primer issue | Issue |
|---|---|---|---|---|---|
| 1 | Un `connect` que no bloquea | protoIO | M | | [protoIO#5](https://github.com/gamarino/protoIO/issues/5) |
| 2 | Una lectura que responde lo que llegó | protoIO | M | | [protoIO#6](https://github.com/gamarino/protoIO/issues/6) |
| 3 | Cerrar un stream de forma atómica | protoST, protoIO | S–M | sí | [protoST#24](https://github.com/gamarino/protoST/issues/24), [protoIO#4](https://github.com/gamarino/protoIO/issues/4) |
| 4 | D59: turnos justos entre actores | protoST | L | | [protoST#26](https://github.com/gamarino/protoST/issues/26) |
| 5 | Estado explícito: los programas de conformidad primero | protoST | M | sí | [protoST#27](https://github.com/gamarino/protoST/issues/27) |
| 6 | Estado explícito: variables `writeOnce` y `constant` | protoST | L | | [protoST#28](https://github.com/gamarino/protoST/issues/28) |
| 7 | Un mundo replicado sobre protoST y protoBaseST | protoST | L | | [protoST#29](https://github.com/gamarino/protoST/issues/29) |
| 8 | Un reentrenamiento de IVF más rápido | protoBaseST | M | | [protoBaseST#4](https://github.com/gamarino/protoBaseST/issues/4) |
| 9 | Un test de pausa con procesos reales | protoBaseST | S–M | | [protoBaseST#5](https://github.com/gamarino/protoBaseST/issues/5) |
| 10 | Los timers del persistidor a un décimo y a diez veces | protoBaseST | S | sí | [protoBaseST#6](https://github.com/gamarino/protoBaseST/issues/6) |
| 11 | Portar `GroupBy` y los agregados de `proto_db` | protoBaseST | M | | [protoBaseST#7](https://github.com/gamarino/protoBaseST/issues/7) |
| 12 | Escrituras en `RepeatedKeysDictionary` | protoBaseST | M | | [protoBaseST#8](https://github.com/gamarino/protoBaseST/issues/8) |
| 13 | El tutorial en castellano, capítulos 1 a 7 | protoBaseST | S–M | sí | [protoBaseST#9](https://github.com/gamarino/protoBaseST/issues/9) |
| 14 | Un ejemplo completo: el padrón de un club | protoBaseST | M | sí | [protoBaseST#10](https://github.com/gamarino/protoBaseST/issues/10) |

Los proyectos 1 a 3 y 8 a 10 cierran cosas que protoBaseST 0.4.0 dejó escritas como pendientes; 4 a 7 son el lenguaje; 11 y 12 son `proto_db` que todavía no está portado; 13 y 14 son para que otros puedan entrar.

---

## 1. Un `connect` que no bloquea

- **Repositorio:** protoIO (después, una primitiva en protoST y su uso en protoBaseST).
- **Por qué.** Desde 0.4.0, cada turno de los actores del transporte TCP de protoBaseST termina: así un actor que espera ya no queda enterrado debajo de una conexión (la historia está en el CHANGELOG, 0.4.0, "Fixed"). Queda una excepción: un `connect` a un par cuyo SYN se descarta (una máquina caída detrás de un firewall) espera hasta `requestTimeout`, 1 s por omisión, y se reintenta después de cada pausa de 0,1 a 0,2 s, así que un actor que espera puede quedar enterrado ese segundo una y otra vez (`docs/not-done.md`, revisión final M3). `protoio::net::tcpConnect` conecta de una sola vez. Hace falta poder empezar un connect y preguntar si terminó, dentro del presupuesto de un turno (`pollInterval`, 50 ms).
- **Tamaño:** M.
- **Requisitos:** C++20, sockets POSIX (y Winsock, o alguien que pruebe en Windows), CMake.
- **Primer paso.** Leer `tcpConnect` en `src/net.cpp` de protoIO (la rama POSIX) y su contrato en `include/protoio/net.h`; compilar y correr los tests de red:
  ```sh
  cmake -S . -B build_release -DCMAKE_BUILD_TYPE=Release && cmake --build build_release -j4
  ctest --test-dir build_release -R net --output-on-failure
  ```
  Después, en protoBaseST, leer cómo conecta el emisor: `src/protobase/cluster/transport.st` (`_PBTcpSender`).
- **Cómo se sabe que está hecho:** un test contra una dirección que descarta SYN, y un turno del emisor que nunca pasa de `pollInterval` esperando un connect.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoIO#5](https://github.com/gamarino/protoIO/issues/5).

## 2. Una lectura que responde lo que llegó

- **Repositorio:** protoIO (después, `IOStream` en protoST y el lector de protoBaseST).
- **Por qué.** `readBytes(fd, n)` espera hasta tener `n` bytes, y su timeout vuelve a empezar con cada byte. Por eso el lector TCP de protoBaseST lee de a 1 KiB (`readChunk`): un par que manda un byte justo antes de cada `pollInterval` le retiene el turno hasta unos 51 s (1024 × 50 ms), y cualquiera que llegue al puerto puede hacerlo, porque el HMAC se verifica con el marco entero (revisión final M5). Y leer de a 1 KiB cuesta: entregar un marco de 1 MiB toma 27 a 32 ms contra 11 a 13 ms con una sola lectura por cuerpo (`bench/run_tcp_frames.sh`, 23/11/2026, protoST 0.16.1, mínimos de tres rondas de cinco marcos; revisión final M4). Una lectura que responda lo que ya llegó (al menos un byte, como mucho `max`) cierra las dos cosas.
- **Tamaño:** M.
- **Requisitos:** C++20, `poll`/`recv` no bloqueantes, CMake; para la segunda mitad, leer Smalltalk.
- **Primer paso.** Leer el contrato de `readBytes` y `readChars` en `include/protoio/stream.h` de protoIO y correr `ctest --test-dir build_release -R stream --output-on-failure`. En protoBaseST, leer `_PBTcpReader` en `src/protobase/cluster/transport.st` y correr `PROTOST=<protost> bench/run_tcp_frames.sh` para tener la cifra de partida.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoIO#6](https://github.com/gamarino/protoIO/issues/6).

## 3. Cerrar un stream de forma atómica

- **Repositorio:** protoST y protoIO (los dos issues ya existen).
- **Por qué.** `IOStream >> close` prueba y pone una variable de instancia común (`closed`), así que dos hilos pueden pasar los dos y liberar dos veces el descriptor, la segunda quizás después de que el número se le dio a otro archivo. protoBaseST lo esquivó con un compare-and-set propio (`_PBTcpReader >> closeSocket`), pero cualquier programa protoST que cierre un stream desde dos hilos está expuesto. En protoIO, el cierre de un descriptor que nunca se leyó ni escribió por un estado tiene la misma carrera.
- **Tamaño:** S–M. **Primer issue:** el arreglo en protoST es un CAS (`setInstVar:from:to:`) y un test con dos actores.
- **Requisitos:** Smalltalk; para protoIO, C++.
- **Primer paso.** Leer `IOStream >> close` en `lib/kernel/io.st` de protoST y el issue; escribir el test que lo reproduce con dos actores y correrlo junto a los tests de entrada y salida, `ctest --test-dir build_release -R cli_io --output-on-failure`.
- **Mentor:** a confirmar; se conversa en los issues.
- **Issues:** [protoST#24](https://github.com/gamarino/protoST/issues/24) y [protoIO#4](https://github.com/gamarino/protoIO/issues/4). No se abre uno nuevo.

## 4. D59: turnos justos entre actores

- **Repositorio:** protoST.
- **Por qué.** Un worker que no espera corre, en un turno, todos los mensajes del actor que tomó, incluidos los que el actor se manda a sí mismo durante el turno (D59 en `docs/STATUS.md`). Un actor que se reenvía mensajes retiene su worker, y con `PROTOST_WORKERS=1` nada más corre, ni los timers. La cola de listos es una pila LIFO por banda (D27), así que acotar el turno no alcanza: el actor reencolado vuelve arriba. La justicia entre actores pide una cola FIFO, y esa es una decisión de scheduler que se mide sola. protoBaseST lo sufrió con su transporte TCP; la espera que ayuda ya quedó acotada en 0.16.1 (S48), el caso general no.
- **Tamaño:** L. Se parte en tres: un benchmark que muestre el costo de hoy, el cambio de cola detrás de una opción, la medición.
- **Requisitos:** C++20, concurrencia sin locks, paciencia para medir (`perf stat`).
- **Primer paso.** Leer D59 y S48 en `docs/STATUS.md` y `STRuntime::helpOne` y el drenaje en `src/runtime/STRuntime.cpp`; correr `ctest --test-dir build_release -R helping --output-on-failure` y el programa `tests/conformance/10-actors/helping-wait-under-self-sending-actor.st` con `PROTOST_WORKERS=1`.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoST#26](https://github.com/gamarino/protoST/issues/26).

## 5. Estado explícito: los programas de conformidad primero

- **Repositorio:** protoST.
- **Por qué.** La especificación de estado explícito ([protoST#25](https://github.com/gamarino/protoST/pull/25), en revisión) agrega clases de valor y modificadores de variables de instancia (`constantNames:`, `writeOnceNames:`, `atomicNames:`). Su §14.2 lista 64 programas de conformidad y su §12 los textos de error. Escribir esos programas antes que la implementación es la mejor revisión de la especificación: cada caso que no se puede escribir es una pregunta abierta.
- **Tamaño:** M. **Primer issue:** son programas Smalltalk cortos con su salida esperada, uno por caso; no hace falta tocar C++.
- **Requisitos:** Smalltalk; leer una especificación con cuidado.
- **Primer paso.** Leer los §5, §6 y §14.2 de `docs/superpowers/specs/2026-11-23-explicit-state-design.md` (en la rama del PR #25) y un programa existente como modelo, `tests/conformance/10-actors/helping-wait-under-self-sending-actor.st`; correr `ctest --test-dir build_release -R conformance --output-on-failure` para ver cómo se ejecutan.
- **Cuándo:** después de que el mantenedor apruebe la especificación; mientras tanto, las preguntas que salgan van al PR.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoST#27](https://github.com/gamarino/protoST/issues/27).

## 6. Estado explícito: variables `writeOnce` y `constant`

- **Repositorio:** protoST (y la migración de protoBaseST 0.5.0 después).
- **Por qué.** protoBaseST ya necesita decir qué estado no cambia, y hoy lo dice por convención: un test que busca `:=` en el código contra una lista de 59 excepciones, y cinco métodos `_publish…:` escritos a mano que llenan un campo una vez con `setInstVar: #f from: nil to: x`. La especificación (§6.2, §6.3, §15) los vuelve lenguaje: `writeOnceNames:` (una asignación es un CAS desde nil que responde el valor instalado) y `constantNames:` (asignable solo durante la construcción). Es la primera mitad de protoST 0.17.0.
- **Tamaño:** L. Se parte: el compilador y los dos opcodes (`STORE_ONCE_INSTVAR`, `STORE_CONST_INSTVAR`), los chequeos al instalar un método, la reflexión.
- **Requisitos:** C++20; leer el compilador y la VM de protoST (`docs/VM.md`).
- **Primer paso.** Leer los §6.2 y §6.3 de la especificación y cómo se emite `STORE_INSTVAR` en `src/frontend/Compiler.cpp`; correr `protost --disasm docs/vm-examples/05-fib.st` para ver el bytecode.
- **Cuándo:** después de la aprobación de la especificación ([protoST#25](https://github.com/gamarino/protoST/pull/25)).
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoST#28](https://github.com/gamarino/protoST/issues/28).

## 7. Un mundo replicado sobre protoST y protoBaseST

- **Repositorio:** protoST (un prototipo en `examples/`, y lo que haga falta en protoBaseST para la historia).
- **Por qué.** En la tesis de David Reed (MIT, 1978), un objeto es una sucesión de versiones inmutables en pseudo-tiempo; de ahí desciende TeaTime, el protocolo de replicación de Croquet. Sobre protoCore, las versiones y las instantáneas salen casi gratis, y protoBaseST ya guarda la historia. Lo que falta es trabajo de verdad (§19 de la especificación de estado explícito): ejecución determinista entre réplicas (los Float de `pow` difieren entre plataformas, D58; el scheduler no es determinista, D59), un reflector que estampe y ordene los mensajes externos, y tiempo de mensaje en lugar de reloj de pared. Es una dirección, no una promesa: el proyecto es averiguar cuánto falta con un prototipo chico.
- **Tamaño:** L, exploratorio. Primer hito: dos réplicas de un contador en un proceso, un actor reflector que ordena los mensajes, y la comparación de las dos historias versión por versión.
- **Requisitos:** Smalltalk, actores; haber leído sobre Croquet ayuda.
- **Primer paso.** Leer el §19 de la especificación y el capítulo 9 del tutorial de protoBaseST (`docs/tutorial/09-actors.md`); correr `STPATH=<protoBaseST>/src protost examples/tutorial/09_actors.st` desde el repositorio de protoBaseST.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoST#29](https://github.com/gamarino/protoST/issues/29).

## 8. Un reentrenamiento de IVF más rápido

- **Repositorio:** protoBaseST.
- **Por qué.** Un índice `ivf_flat` se reentrena dentro del commit que cruza su umbral. En un cluster eso pasa bajo el permiso de escritura (667 ms con el lease de 2000 ms por omisión), y un reentrenamiento más largo nunca confirma: hoy un índice IVF en un cluster pide un lease de más de cuatro veces su reentrenamiento, unos 4 ms por miembro a dimensión 8 con protoST 0.16.0 (`docs/not-done.md`). Más o menos la mitad del reentrenamiento es k-means; el resto, sobre todo, el recorrido y la reconstrucción del árbol del índice (indicativo). Lo primero es medir ese recorrido (el recálculo de las claves de orden). El k-means tiene que seguir dando los mismos bytes que `proto_db`: eso no se negocia.
- **Tamaño:** M.
- **Requisitos:** Smalltalk; medir con cuidado.
- **Primer paso.** Leer el reentrenamiento en `src/protobase/vectors.st` (`PBVectorIvfFlat`) y `src/protobase/indexes.st`; correr `QUERY_VB3_SIZES=600 RUNS=1 PROTOST=<protost> bench/run_query.sh VB3` (necesita el venv de `tests/interop/setup_venv.sh`) para tener el punto de partida, y `tests/run_tests.sh tests/unit/vec_ivf.st`.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoBaseST#4](https://github.com/gamarino/protoBaseST/issues/4).

## 9. Un test de pausa con procesos reales

- **Repositorio:** protoBaseST.
- **Por qué.** Los tests de `tests/cluster` matan miembros con `kill -9`, pero nunca pausan uno (`kill -STOP` y después `kill -CONT`). Ese es el chequeo con reloj real y TCP real de un dueño o un portador de permiso viejo, la propiedad sobre la que descansa "la seguridad nunca depende del tiempo". Hoy solo lo cubren el simulador (un reloj detenido) y un test en un proceso (revisión final M8, `docs/not-done.md`).
- **Tamaño:** S–M. La receta está escrita: detener al portador cuando construyó su raíz, esperar a que venza su lease, reanudarlo, y verificar que los contadores son exactos y que su commit termina sin efecto o desconocido, nunca aplicado dos veces.
- **Requisitos:** bash, procesos y señales; leer Smalltalk.
- **Primer paso.** Leer `tests/cluster/_cluster.sh` y `tests/cluster/real_kill_holder.sh`, el modelo más cercano; correr `PROTOST=<protost> tests/run_tests.sh tests/cluster/real_kill_holder.sh`.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoBaseST#5](https://github.com/gamarino/protoBaseST/issues/5).

## 10. Los timers del persistidor a un décimo y a diez veces

- **Repositorio:** protoBaseST.
- **Por qué.** La auditoría de timers del cluster escala `persistInterval` y `persistLag`, pero el simulador no lee ninguno de los dos, así que esas corridas no ejercitan los timers del persistidor: su vivacidad a esos valores no está auditada (revisión final M7, `docs/not-done.md`). Lo que lo cierra está escrito: sacar esas partes de la cuenta de la auditoría y agregar a `tests/unit/cluster_persister.st` un caso a un décimo y otro a diez veces los valores por omisión, que verifique que `sync:` vuelve y que un miembro que no confirmó la raíz la persiste pasado `persistLag`.
- **Tamaño:** S. **Primer issue:** un caso de test en un archivo que ya tiene el andamiaje.
- **Requisitos:** Smalltalk.
- **Primer paso.** Leer `tests/unit/cluster_persister.st` y correr `PROTOST=<protost> tests/run_tests.sh tests/unit/cluster_persister.st`.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoBaseST#6](https://github.com/gamarino/protoBaseST/issues/6).

## 11. Portar `GroupBy` y los agregados de `proto_db`

- **Repositorio:** protoBaseST.
- **Por qué.** `proto_db` tiene `GroupBy` / `Agg`, `Join`, `Unnest` y `ValuesScan`; protoBaseST no (diferidos por la decisión IQ3, `docs/not-done.md`). Son operadores de ejecución, no optimizaciones: ningún índice interviene y el planificador nunca los elige, así que se pueden portar uno por uno contra los tests de `proto_db`. Hoy un programa agrupa a mano.
- **Tamaño:** M para `GroupBy` y `Agg`; los otros, cada uno un proyecto S–M después.
- **Requisitos:** Smalltalk; leer Python.
- **Primer paso.** Leer `GroupBy` en `proto_db/query/plans.py` y `proto_db/query/linq.py` del repositorio de protoBase (tag `v2.0.0rc4`) y los planes de protoBaseST en `src/protobase/plans.st`; correr `PROTOST=<protost> tests/run_tests.sh tests/unit/qry_terms.st` y ver cómo `tests/unit/queries_checklist.tsv` registra cada test de `proto_db` como portado o justificado.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoBaseST#7](https://github.com/gamarino/protoBaseST/issues/7).

## 12. Escrituras en `RepeatedKeysDictionary`

- **Repositorio:** protoBaseST.
- **Por qué.** protoBaseST lee un `RepeatedKeysDictionary` escrito por `proto_db`, pero no lo escribe: fue un no-objetivo del prototipo (`docs/not-done.md`). Un programa Smalltalk que comparte la base con uno Python no puede tocar esas colecciones. El trabajo es el de siempre: los mutadores, nodo por nodo iguales a los de `proto_db`, sus índices, y la combinación de escrituras ciegas.
- **Tamaño:** M.
- **Requisitos:** Smalltalk; leer Python; árboles AVL.
- **Primer paso.** Leer `RepeatedKeysDictionary` en `proto_db/collections/dictionaries.py` (protoBase, `v2.0.0rc4`) y `PBRepeatedKeysDictionary` en `src/protobase/collections.st`; correr `PROTOST=<protost> tests/run_tests.sh tests/interop/index_ops_identical.sh` para ver cómo se compara un árbol nodo por nodo con `proto_db`.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoBaseST#8](https://github.com/gamarino/protoBaseST/issues/8).

## 13. El tutorial en castellano, capítulos 1 a 7

- **Repositorio:** protoBaseST.
- **Por qué.** El tutorial (`docs/tutorial/`) está en inglés, y la comunidad que más puede aportar habla castellano. Los capítulos 1 a 7 son un proceso solo: primer commit, valores y versiones, registros, colecciones, transacciones, escrituras ciegas, mutables e historia. Cada capítulo cita un programa que corre como test, así que la traducción no puede desviarse del código sin que se note.
- **Tamaño:** S–M (un capítulo es una tarde). **Primer issue.**
- **Requisitos:** castellano claro; leer Smalltalk.
- **Primer paso.** Leer `docs/tutorial/01-first-commit.md` y correr su programa: `cd examples/tutorial && STPATH=../../src protost 01_first_commit.st`. Proponer en el issue dónde viven las traducciones (por ejemplo `docs/tutorial/es/`) y cómo `tests/docs/` verifica que citan bien los programas.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoBaseST#9](https://github.com/gamarino/protoBaseST/issues/9).

## 14. Un ejemplo completo: el padrón de un club

- **Repositorio:** protoBaseST.
- **Por qué.** Hay un ERP chico (`docs/tutorial/erp.md`), pero ningún ejemplo de mediana escala que use todo junto: registros con clase propia, índices y consultas, historia ("¿quién era socio el 1/3?"), un cluster de tres nodos y un script Python que lee la misma base. Un ejemplo así es lo que un recién llegado copia, y lo que muestra en una charla.
- **Tamaño:** M. **Primer issue:** no requiere tocar la biblioteca, y si algo falta o sorprende, eso mismo es un hallazgo para un issue.
- **Requisitos:** Smalltalk; algo de Python para la parte compartida.
- **Primer paso.** Leer el ejercicio 6 de este taller (`ejercicios/06-python-y-smalltalk.sh`) y `docs/tutorial/erp.md`; correr `ejercicios/verificar.sh`.
- **Mentor:** a confirmar; se conversa en el issue.
- **Issue:** [protoBaseST#10](https://github.com/gamarino/protoBaseST/issues/10).

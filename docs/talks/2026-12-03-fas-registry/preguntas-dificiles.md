# Preguntas difíciles — respuestas honestas

Cada respuesta dice qué está verificado y dónde. Si la respuesta es "no sabemos" o "no está
hecho", se dice así.

## Sobre protoBaseST

**¿Es el sucesor de GemStone?**
No. Está en la tradición que abrió GemStone: objetos que persisten como objetos, alcanzables desde
raíces. GemStone es más fino en conflictos (objetos, no raíces), más rico en índices y en
migración de clases, guarda y ejecuta código en el repositorio, y opera a otra escala
(`docs/tutorial/gemstone.md`).

**¿Qué tan lento es?**
Varias veces: 0,33× los commits por segundo de `proto_db` en commits de una clave, 0,12× en lotes
de 100 claves, de 3,5× a 35× el tiempo en consultas, de 8,5× a 12,3× en commits con índice
vectorial. Una máquina, fechas del 20 y 22/11/2026 (`docs/deviations.md`, Performance). No se
promete que vaya a ser rápido.

**¿Por qué, si Python también interpreta?**
La entrada y salida es la misma en los dos. Es CPU: en la medición del 13/11 (protoST 0.10.0, ya
vieja) un commit chico costaba 53 millones de instrucciones de usuario contra 3,6 millones de
`proto_db`. Intérprete, construcción de nodos, codificación: trabajo de la VM más que de la
biblioteca. No hay una medición más nueva de instrucciones; no inventarla.

**¿Entonces para qué sirve?**
Para mostrar que un modelo inmutable alcanza para ser exacto frente a otra implementación (las
mismas respuestas, planes y bytes), y para poner a prueba protoST con una aplicación de verdad.
No es un producto.

**¿Corre sobre protoST 0.17.0?**
Sí, y lo exige desde 0.4.1 (24/11/2026). 0.4.0 imprimía sobre 0.17.0 el aviso de que
`setInstVar:from:to:` está deprecado y se quita en 0.18.0; lo llamaba en 8 lugares de 3 archivos.
0.4.1 los pasa a `compareAndSet:from:to:` y sube el piso a 0.17.0. La suite completa sobre 0.17.0:
315 pasan, 0 fallan, 3 salteados; los 6 ejercicios del taller dan lo esperado.

**¿Cuándo sale 0.5.0?**
No hay fecha. Está planeada (especificación de estado explícito de protoST, §13.2) y no empezó.
Lo que sí es seguro es el orden: después de cada release de protoST que trae lo que migra.

**¿Quién revisó esto?**
Nadie de afuera. Un implementador, con agentes de IA como herramientas, revisado tarea por tarea
(`docs/not-done.md`). Para eso son estos talleres.

**¿Por qué `add:` responde un set nuevo, contra lo que hace Pharo?**
Porque son los nombres de `proto_db`, a propósito, para que un documento explique los dos
lenguajes; y porque los valores son inmutables. Es lo primero para discutir del README;
las alternativas (`copyWith:`, …) están en `docs/decisions.md`.

## Sobre el registro

**¿protoBaseST tiene el registro?**
No. Conoce el formato 5 de `proto_db` 2.0.0rc4 y lo rechaza con `PBNotSupportedError`: una base que
usa el registro se rechaza al abrir, nunca se lee mal (`docs/decisions.md`, "Known, not adopted").
Adoptarlo es un plan propio, del tamaño del plan del cluster, que no está escrito.

**¿Y en `proto_db`, está hecho o es un diseño?**
Está implementado y publicado en 2.0.0rc4 (15/11/2026, decisión D62): padres, resolución C3,
módulos, `_super()`, `install_module`, catálogo, `base`, orden de carga determinista. Tiene unos
215 tests en nueve archivos; no los corrí para esta charla. El modelo semántico que viene después
(formato 6) está diseñado y aprobado, no construido.

**¿Por qué un atributo que no existe devuelve `None` y no `doesNotUnderstand:`?**
Es una decisión del mantenedor (R150): un modelo tiene que poder ganar atributos con el tiempo sin
romper objetos ni código viejos. En Smalltalk la expectativa es la contraria. Es uno de los seis
puntos abiertos: no está decidido para protoBaseST.

**¿Por qué C3, si Smalltalk tiene herencia simple?**
Porque los objetos de `proto_db` tienen varios padres y un nombre de registro puede llegarse por dos
caminos; un recorrido en profundidad visita un ancestro compartido antes que quien lo redefine. C3
ordena cada nodo después de todos sus hijos y rechaza la jerarquía que no tiene ese orden. protoST
ya tiene varios padres (`uses:`, `addBehavior:`), pero su `super` no es cooperativo: la demo lo
muestra.

**¿Eso es un bug de protoST?**
No. LANGUAGE.md §4.11 documenta el orden de protoST y que `super` sigue desde la clase que define el
método, como en cualquier Smalltalk. Lo que la demo muestra es que, si el registro se montara sobre
las clases de protoST tal como están, la misma base daría comportamientos distintos en Python y en
Smalltalk. Qué hacer es una pregunta abierta.

**¿Por qué no guardar el código en la base, como GemStone?**
Porque ataría los datos a un lenguaje: una base que leen Python y Smalltalk no puede guardar
métodos de uno de los dos (anti-objetivo A1 de la spec). Cada lenguaje tiene su versión de cada
módulo, y la base guarda solo sus nombres. El costo: no hay ejecución del lado de la base ni código
compartido en ella.

**¿Y la migración de instancias?**
No hay. Un cambio del objeto de catálogo llega solo a los objetos creados después (R189, R190); un
atributo nuevo es `None` en los viejos; "migrar" es escribir versiones nuevas con un programa. Es
la misma semántica que `addBehavior:` en protoST (D21), por la misma razón de fondo. GemStone lo
resolvió con historia de clases y migración explícita. Es el primer punto fundamental: necesitamos
su experiencia.

**¿Y `become:`?**
protoST no tiene `become:` (LANGUAGE.md). En `proto_db` una versión nueva es otro objeto; la
identidad estable es una celda mutable que apunta a la versión vigente.

**¿Por qué los símbolos no son lo que pedía el requisito del 8/11?**
Porque se midió antes de construir: sobre 13 964 objetos de un ERP, la compresión ya quitaba los
nombres repetidos, y las referencias a símbolos no ahorraron el 10 % que pedía el criterio. Quedó
diferido (R153, R213). Un símbolo, si llega, es solo otra forma de escribir el mismo string.

**¿Cuánto cuesta una búsqueda por el registro?**
No se midió. El diseño argumenta que el costo no depende de la profundidad de la historia, y lo
marca como algo a verificar (`design-guide/registry.rst`, "Its cost, stated honestly").

**¿Por qué no decidieron ya cómo es en Smalltalk?**
Porque es exactamente lo que se beneficia de quien tiene la experiencia: migración (GemStone),
extensiones entre paquetes (Pharo), herramientas. Decidirlo sin esa experiencia sería repetir el
error que la charla intenta evitar.

**¿Permisos, seguridad, borrado por GDPR?**
Fuera de la base, por diseño: no hay modelo de permisos (NG3), ni borrado ni reescritura de la
historia (NG4); un pedido legal de borrado se atiende afuera, por ejemplo destruyendo claves.
Está dicho como límite, no como solución.

"Ejercicio 2 — El incremento que protoST perdía, ahora en una base.

 En el ejercicio 2 de protoST, ocho actores sobre un objeto común perdían incrementos:
 n := n + 1 es leer y publicar, y gana la última escritura. Acá el contador vive en una base.
 Antes de correrlo, anoten:
   a) dos transacciones leen el mismo saldo y escriben saldo + 10. ¿Qué pasa con la segunda?
   b) una transacción solo LEE la tasa y escribe el interés; otra cambia la tasa. ¿Conflicto?
   c) cuatro actores hacen diez run: cada uno sobre el mismo contador. ¿Cuánto da?
   d) ¿cuántas veces corren los bloques en total? ¿Siempre lo mismo?

 STPATH=../../../../src protost 02-conflicto-y-reintento.st"

Import from: 'protobase'.
Import from: '_taller'.

Object subclass: #Cajero instanceVariableNames: 'corridas'.

"Hace n commits que incrementan el contador; responde cuántas veces corrió el bloque."
Cajero >> sumar: n en: aDatabase
  corridas := 0.
  1 to: n do: [:i |
    aDatabase run: [:tr |
        corridas := corridas + 1.
        tr setRootObject: 'contador' value: (tr getRootObject: 'contador') + 1]
      retries: 100].
  ^ corridas.

| dir space db a b tr interes cajeros fs corridas |
dir := Taller directorio: '02'.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'banco'.
db newTransactionDo: [:t |
    t setRootObject: 'saldo' value: 100.
    t setRootObject: 'tasa' value: 5.
    t setRootObject: 'interes' value: 0.
    t setRootObject: 'contador' value: 0].

"a) Dos transacciones leen el mismo saldo. Cada una lee su instantánea."
a := db newTransaction.
b := db newTransaction.
a setRootObject: 'saldo' value: (a getRootObject: 'saldo') + 10.
b setRootObject: 'saldo' value: (b getRootObject: 'saldo') + 10.
a commit.
Taller di: 'a confirmó: saldo ' , (db newTransaction getRootObject: 'saldo') printString.
[b commit. Taller di: 'b confirmó (¡se perdió un incremento!)']
    on: PBConflictError do: [:e | Taller di: 'b: PBConflictError — ' , e messageText].
Taller di: 'saldo final: ' , (db newTransaction getRootObject: 'saldo') printString.

"b) Leer alcanza para quedar protegido: el conjunto de lectura se verifica al confirmar."
tr := db newTransaction.
interes := (tr getRootObject: 'saldo') * (tr getRootObject: 'tasa') // 100.
db newTransactionDo: [:t | t setRootObject: 'tasa' value: 7].
tr setRootObject: 'interes' value: interes.
[tr commit. Taller di: 'el interés se calculó con una tasa vieja']
    on: PBConflictError do: [:e | Taller di: 'interés: PBConflictError — ' , e messageText].

"c) run: es el bucle leer-calcular-publicar: ante un conflicto corre el bloque otra vez,
 con una transacción nueva. Por eso el bloque no debe tener efectos fuera de ella."
cajeros := (1 to: 4) collect: [:i | Cajero new asActor].
fs := cajeros collect: [:c | c sumar: 10 en: db].
corridas := fs inject: 0 into: [:sum :f | sum + f wait].
Taller di: 'contador: ' , (db newTransaction getRootObject: 'contador') printString , ' de 40'.
Taller di: '~ los bloques corrieron ' , corridas printString , ' veces (' , (corridas - 40) printString , ' reintentos)'.
Taller di: 'versiones: ' , db history size printString , ' (1 vacía + 1 inicial + 1 de a + 1 de la tasa + 40)'.
space close.
Taller di: '~ el directorio queda en ' , dir pathString.

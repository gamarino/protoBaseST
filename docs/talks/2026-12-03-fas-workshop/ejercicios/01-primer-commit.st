"Ejercicio 1 — Una base es un directorio; un commit es una versión.

 Córranlo desde esta carpeta, con el src/ del repositorio en el camino de módulos:
   STPATH=../../../../src protost 01-primer-commit.st
 Antes de correrlo, anoten:
   a) después de 'tags add: urgente' sin asignar, ¿cuántos elementos tiene tags?
   b) ¿cuántas versiones tiene la base después de dos commits?
   c) ¿se puede leer el título que había antes del segundo commit?
   d) un objeto nuevo abierto sobre el mismo directorio, ¿ve lo que se guardó?"

Import from: 'protobase'.
Import from: '_taller'.

| dir space db tags tr old again |
dir := Taller directorio: '01'.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'biblioteca'.
Taller di: 'bases: ' , space listDatabases printString.
Taller di: 'versiones al crearla: ' , db history size printString.

"Cada mensaje de una colección responde una colección NUEVA y deja igual al receptor."
tags := PBSet new.
tags add: 'urgente'.
Taller di: 'tags después de add: sin asignar: ' , tags count printString.
tags := tags add: 'urgente'.
Taller di: 'tags después de asignar la respuesta: ' , tags count printString.

"Primer commit: dos raíces. newTransactionDo: confirma al final del bloque."
db newTransactionDo: [:t |
    t setRootObject: 'titulo' value: 'Mi biblioteca'.
    t setRootObject: 'libros' value: ((t newDictionary
        setAt: 'isbn:0201113716' value: 'Smalltalk-80: The Language')
        setAt: 'isbn:0201136880' value: 'Smalltalk-80: Bits of History, Words of Advice')].

"Segundo commit: cambia el título."
db newTransactionDo: [:t | t setRootObject: 'titulo' value: 'La biblioteca de FAST'].
Taller di: 'versiones: ' , (db history collect: [:e | e version]) asArray printString.

"La historia es perenne: cada versión confirmada se sigue pudiendo leer."
tr := db newTransaction.
Taller di: 'título actual: ' , (tr getRootObject: 'titulo').
tr abort.
old := db snapshotAt: (db history at: 2).
Taller di: 'título en la versión ' , old version printString , ': ' , (old getRootObject: 'titulo').
Taller di: 'raíces en la versión 0: ' , (db snapshotAt: db history last) rootNames printString.
space close.

"Todo lo confirmado está en el directorio: otro espacio lo lee."
again := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := again openDatabase: 'biblioteca'.
tr := db newTransaction.
Taller di: 'reabierta: ' , (tr getRootObject: 'libros') count printString , ' libros, título ' , (tr getRootObject: 'titulo') printString.
tr abort.
again close.

"Qué hay en el directorio: el formato de proto_db, sin nada propio de Smalltalk."
Taller di: 'archivos: ' , ((dir files collect: [:f |
    f extension = 'seg' ifTrue: ['<uuid>.seg'] ifFalse: [f basename]]) asSortedCollection: [:a :b | a <= b]) asArray printString.
Taller di: '~ el directorio queda en ' , dir pathString.

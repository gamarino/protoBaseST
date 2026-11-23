"_06-leer.st: el último paso del ejercicio 6 (lo corre 06-python-y-smalltalk.sh).

 Uso: protost _06-leer.st <directorio>
 Lee lo que confirmó Python, consulta por el índice que Python mantuvo y agrega una etiqueta
 propia, que se combina con la de Python (una escritura ciega)."
Import from: 'protobase'.

PBObject subclass: #Socio.

Socio class >> typeName
  ^ 'taller.Socio'.

PBObjectSpace registerAtomClass: Socio.

| space db tr socios nuevo cordoba |
space := PBObjectSpace storage: (PBFileStorage path: Smalltalk arguments first).
db := space openDatabase: 'socios'.
tr := db newTransaction.
socios := tr getRootObject: 'socios'.
nuevo := socios getAt: 41.
Transcript showCr: 'protoST leyó el socio de Python: ' , nuevo class name , ' ' , (nuevo at: 'nombre')
    , ', cuota ' , (nuevo at: 'cuota') printString.
cordoba := (PBQuery from: socios) where: ((PBField path: 'ciudad') eq: 'Córdoba').
Transcript showCr: 'Córdoba: ' , (cordoba explain at: 'plan') , ' (' , cordoba count printString , ' socios)'.
Transcript showCr: 'versiones: ' , (db history collect: [:e | e version]) asArray printString.
tr abort.
db newTransactionDo: [:t | t setRootObject: 'etiquetas' value: (t newDictionary setAt: 'y' value: 'protoST')].
Transcript showCr: 'etiquetas: ' , (db newTransaction getRootObject: 'etiquetas') keys printString.
space close.

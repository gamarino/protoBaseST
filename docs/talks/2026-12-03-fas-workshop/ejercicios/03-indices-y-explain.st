"Ejercicio 3 — Índices, consultas y el plan que corre.

 600 personas en cuatro ciudades, con un índice de igualdad por ciudad y uno de rango por edad.
 Los índices son parte de la versión de la colección: cada mutador los mantiene.
 Antes de correrlo, anoten para cada consulta qué plan esperan (un índice o un recorrido):
   a) city = 'Oslo';
   b) city = 'Oslo' AND age > 70: ¿qué índice elige, y qué queda como filtro?
   c) la misma consulta sin índices: ¿da las mismas filas?
   d) city = 'Oslo' OR city = 'Rome'; y Oslo OR un nombre que contiene '7';
   e) un bloque [:p | ...] como condición: ¿puede usar un índice?
 Los planes y los costos del modelo son los de proto_db, nodo por nodo.

 STPATH=../../../../src protost 03-indices-y-explain.st"

Import from: 'protobase'.
Import from: '_taller'.

| dir space db cities people planOf q city age oslo plan both scan sinIndices nombres |
dir := Taller directorio: '03'.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'personas'.
cities := #('Lima' 'Oslo' 'Paris' 'Rome').
db newTransactionDo: [:t |
    | ps |
    ps := t newDictionary.
    0 to: 599 do: [:i |
        ps := ps setAt: i value: (t newObject: {
            'name' -> ('person' , i printString).
            'city' -> (cities at: i \\ 4 + 1).
            'age' -> (18 + (i \\ 60)) })].
    t setRootObject: 'people' value: ((ps
        addIndex: (PBEqualityIndex name: 'by_city' path: 'city'))
        addIndex: (PBRangeIndex name: 'by_age' path: 'age'))].
people := db newTransaction getRootObject: 'people'.
Taller di: 'índices: ' , people indexNames asArray printString.

"Los nombres de los nodos de un plan, desde la raíz por el primer hijo."
planOf := [:query | | names node |
    names := OrderedCollection new.
    node := query explain.
    [node isNil] whileFalse: [
        names add: (node at: 'plan').
        node := (node at: 'children') isEmpty ifTrue: [nil] ifFalse: [(node at: 'children') at: 1]].
    names inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ' <- ' , each]]].

q := PBQuery from: people.
city := PBField path: 'city'.
age := PBField path: 'age'.

"Una trampa antes de empezar: un campo comparado con = responde un Boolean, no una condición."
Taller di: 'city = ''Oslo'' es ' , (city = 'Oslo') printString , '; la condición es city eq: ''Oslo'''.

"a) Una igualdad."
oslo := q where: (city eq: 'Oslo').
plan := oslo explain.
Taller di: 'a) ' , (planOf value: oslo) , ' sobre ' , ((plan at: 'index') at: 'index')
    , ', estimadas ' , ((plan at: 'estimate') at: 'rows') printString , ' filas, encontradas ' , oslo count printString.

"b) Dos condiciones: un camino de acceso y un filtro residual."
both := q where: ((city eq: 'Oslo') & (age > 70)).
Taller di: 'b) ' , (planOf value: both) , '; el filtro prueba ' , ((both explain at: 'predicate') at: 'path')
    , '; estimadas ' , ((both explain at: 'estimate') at: 'rows') printString , ', encontradas ' , both count printString.

"c) Sin índices: un recorrido. Un índice nunca cambia una respuesta."
sinIndices := (people removeIndex: 'by_city') removeIndex: 'by_age'.
scan := (PBQuery from: sinIndices) where: ((city eq: 'Oslo') & (age > 70)).
nombres := [:query | (query asArray collect: [:p | p at: 'name']) asSortedCollection asArray].
Taller di: 'c) ' , (planOf value: scan) , '; las mismas filas: ' , ((nombres value: scan) = (nombres value: both)) printString.
Taller di: '   people sigue teniendo ' , people indexNames size printString , ' índices: removeIndex: respondió otra colección'.

"d) Un OR usa una unión solo si cada rama tiene índice."
Taller di: 'd) ' , (planOf value: (q where: ((city eq: 'Oslo') | (city eq: 'Rome')))).
Taller di: '   ' , (planOf value: (q where: ((city eq: 'Oslo') | ((PBField path: 'name') contains: '7')))).

"e) Un bloque es opaco: corre elemento por elemento y nunca usa un índice."
Taller di: 'e) ' , (planOf value: (q where: [:p | (p at: 'age') \\ 7 = 0])).
Taller di: '   ' , (planOf value: ((q where: (city eq: 'Oslo')) where: [:p | (p at: 'age') \\ 7 = 0]))
    , ', ' , ((q where: (city eq: 'Oslo')) where: [:p | (p at: 'age') \\ 7 = 0]) count printString , ' filas'.

"Orden y página: los tres mayores de Oslo. ¿Por qué no lee el índice de edad en orden?"
Taller di: 'orden: ' , (planOf value: ((oslo orderBy: 'age' descending: true) take: 3))
    , ' → ' , (((oslo orderBy: 'age' descending: true) take: 3) asArray collect: [:p | p at: 'age']) printString.
space close.
Taller di: '~ el directorio queda en ' , dir pathString.

"Ejercicio 4 — Búsqueda vectorial: los mismos vecinos, en el mismo orden, que proto_db.

 600 documentos con un vector de 8 dimensiones cada uno (de un generador con semilla, así cada
 corrida arma los mismos datos; una aplicación los saca de un modelo de embeddings).
 Antes de correrlo, anoten:
   a) los 5 más cercanos según el índice, ¿son los mismos que puntuar todo y ordenar?
   b) 'los 3 más cercanos que son de música' contra 'los 3 más cercanos, después filtrar música':
      ¿responden lo mismo? ¿cuántos da cada uno?
   c) el producto interno de (1, 1, 1) con (1e16, 1, -1e16), sumado con un bucle de +: ¿cuánto da?
   d) un IVF con 16 listas que mira 1 sola lista: ¿encuentra los 10 vecinos verdaderos?

 STPATH=../../../../src protost 04-busqueda-vectorial.st"

Import from: 'protobase'.
Import from: '_taller'.

| dir space db topics seed next data docs all dot norm cosine target ranked planOf nearest
  despues music musica ipDocs ipAll ipQuery naive byIndex x ivf hits truthOf |
dir := Taller directorio: '04'.
space := PBObjectSpace storage: (PBFileStorage path: dir pathString).
db := space newDatabase: 'docs'.
topics := #('deportes' 'musica' 'ciencia').
seed := 7.
next := [seed := seed * 16807 \\ 2147483647. seed / 2147483647.0 * 2.0 - 1.0].
data := (0 to: 599) collect: [:i | { i. topics at: i \\ 3 + 1. (1 to: 8) collect: [:j | next value] }].
db newTransactionDo: [:t |
    | coll |
    coll := t newList addIndex: (PBVectorIndex name: 'by_vec' path: 'vec' dim: 8 metric: 'cosine').
    data do: [:d |
        coll := coll appendLast: (t newObject: { 'i' -> (d at: 1). 'topic' -> (d at: 2). 'vec' -> (d at: 3) })].
    t setRootObject: 'docs' value: coll].
docs := db newTransaction getRootObject: 'docs'.
all := OrderedCollection new.
docs do: [:d | all add: d].
Taller di: 'documentos: ' , docs size printString , ', índices: ' , docs indexNames asArray printString.

"La manera obvia: puntuar todo y ordenar (con sumas de + comunes)."
dot := [:a :b | | s | s := 0.0. 1 to: a size do: [:j | s := s + ((a at: j) * (b at: j))]. s].
norm := [:a | (dot value: a value: a) sqrt].
cosine := [:a :b | (dot value: a value: b) / ((norm value: a) * (norm value: b))].
target := ((all detect: [:d | (d at: 'i') = 42]) at: 'vec') asArray.
ranked := (all asSortedCollection: [:a :b |
    (cosine value: target value: (a at: 'vec')) >= (cosine value: target value: (b at: 'vec'))]) asArray.
planOf := [:query | | names node |
    names := OrderedCollection new.
    node := query explain.
    [node isNil] whileFalse: [
        names add: (node at: 'plan').
        node := (node at: 'children') isEmpty ifTrue: [nil] ifFalse: [(node at: 'children') at: 1]].
    names inject: '' into: [:acc :each | acc isEmpty ifTrue: [each] ifFalse: [acc , ' <- ' , each]]].

"a) La misma pregunta al índice."
nearest := (PBQuery from: docs) where: ((PBField path: 'vec') near: target k: 5).
Taller di: 'a) plan: ' , (planOf value: nearest).
Taller di: '   índice: ' , (nearest asArray collect: [:d | d at: 'i']) printString.
Taller di: '   a mano: ' , ((ranked first: 5) collect: [:d | d at: 'i']) printString.

"b) La condición adentro de la búsqueda, o después."
despues := (nearest asArray first: 3) select: [:d | (d at: 'topic') = 'musica'].
music := (PBQuery from: docs) where: (((PBField path: 'vec') near: target k: 3) & ((PBField path: 'topic') eq: 'musica')).
musica := music asArray.
Taller di: 'b) primero los 3, después filtrar: ' , (despues collect: [:d | d at: 'i']) asArray printString.
Taller di: '   la condición adentro: ' , (musica collect: [:d | d at: 'i']) printString , ' (' , (planOf value: music) , ')'.

"c) Por qué los puntajes son sumas correctamente redondeadas (math.fsum de CPython, portado)."
ipQuery := #(1.0 1.0 1.0).
db newTransactionDo: [:t |
    t setRootObject: 'ip' value: (((t newList
        addIndex: (PBVectorIndex name: 'by_vec' path: 'vec' dim: 3 metric: 'ip'))
        appendLast: (t newObject: { 'name' -> 'grande'. 'vec' -> #(1.0e16 1.0 -1.0e16) }))
        appendLast: (t newObject: { 'name' -> 'chico'. 'vec' -> #(0.5 0.25 0.0) }))].
ipDocs := db newTransaction getRootObject: 'ip'.
ipAll := OrderedCollection new.
ipDocs do: [:d | ipAll add: d].
naive := (ipAll asSortedCollection: [:a :b | (dot value: ipQuery value: (a at: 'vec')) >= (dot value: ipQuery value: (b at: 'vec'))]) asArray.
byIndex := ((PBQuery from: ipDocs) where: ((PBField path: 'vec') near: ipQuery k: 2)) asArray.
Taller di: 'c) bucle de +: grande puntúa ' , (dot value: ipQuery value: #(1.0e16 1.0 -1.0e16)) printString
    , ', orden ' , (naive collect: [:d | d at: 'name']) printString.
Taller di: '   el índice: ' , (byIndex collect: [:d | d at: 'name']) printString.

"Y por qué x ** 2 no es x * x: 130492547 al cuadrado necesita 54 bits, un caso a mitad de camino.
 El ** de Python es pow de libm; raisedTo: 2 de protoST también. El k-means de IVF eleva así."
x := 130492547 asFloat.
Taller di: '   (x raisedTo: 2) = (x * x): ' , ((x raisedTo: 2) = (x * x)) printString
    , '; raisedTo: 2 da ' , (x raisedTo: 2) printString.

"d) IVF-Flat: 16 listas, mira 1. Recall@10 sobre 10 consultas, contra la verdad exacta."
db newTransactionDo: [:t |
    | coll |
    coll := t newList addIndex: (PBVectorIndex name: 'ivf' keySpec: (PBKeySpec path: 'vec') dim: 8 metric: 'cosine'
        backend: 'ivf_flat' params: (Dictionary new at: 'nlist' put: 16; at: 'nprobe' put: 1; yourself)).
    docs do: [:d | coll := coll appendLast: d].
    t setRootObject: 'ivf' value: coll].
ivf := db newTransaction getRootObject: 'ivf'.
truthOf := [:vec | (((all asSortedCollection: [:a :b |
        (cosine value: vec value: (a at: 'vec')) >= (cosine value: vec value: (b at: 'vec'))]) asArray first: 10)
    collect: [:d | d at: 'i']) asSet].
hits := 0.
0 to: 9 do: [:q | | vec truth found |
    vec := (all detect: [:d | (d at: 'i') = (q * 59)]) at: 'vec'.
    truth := truthOf value: vec.
    found := (((PBQuery from: ivf) where: ((PBField path: 'vec') near: vec k: 10)) asArray collect: [:d | d at: 'i']) asSet.
    hits := hits + (truth select: [:i | found includes: i]) size].
Taller di: 'd) ' , (planOf value: ((PBQuery from: ivf) where: ((PBField path: 'vec') near: target k: 10)))
    , ', nprobe 1: ' , hits printString , ' de 100 vecinos verdaderos'.
space close.
Taller di: '~ el directorio queda en ' , dir pathString.

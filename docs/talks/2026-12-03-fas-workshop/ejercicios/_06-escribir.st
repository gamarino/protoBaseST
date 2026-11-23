"_06-escribir.st: el primer paso del ejercicio 6 (lo corre 06-python-y-smalltalk.sh).

 Uso: protost _06-escribir.st <directorio>
 Crea la base 'socios' con 40 socios (registros del tipo taller.Socio), un índice de igualdad
 por ciudad y un diccionario de etiquetas vacío."
Import from: 'protobase'.

PBObject subclass: #Socio.

"El nombre del tipo es neutral al lenguaje: es lo que guarda el archivo, y Python declara el mismo."
Socio class >> typeName
  ^ 'taller.Socio'.

PBObjectSpace registerAtomClass: Socio.

| space db ciudades |
ciudades := #('Buenos Aires' 'Córdoba' 'Rosario' 'Mendoza').
space := PBObjectSpace storage: (PBFileStorage path: Smalltalk arguments first).
db := space newDatabase: 'socios'.
db newTransactionDo: [:tr |
    | socios |
    socios := tr newDictionary.
    1 to: 40 do: [:i |
        socios := socios setAt: i value: (Socio withAll: {
            'nombre' -> ('socio' , i printString).
            'ciudad' -> (ciudades at: i \\ 4 + 1).
            'cuota' -> (Decimal fromString: '1500.50').
            'alta' -> (CalendarDate year: 2026 month: 12 day: 3) })].
    tr setRootObject: 'socios' value: (socios addIndex: (PBEqualityIndex name: 'por_ciudad' path: 'ciudad')).
    tr setRootObject: 'etiquetas' value: tr newDictionary].
space close.
Transcript showCr: 'protoST escribió 40 socios con el índice por_ciudad'.

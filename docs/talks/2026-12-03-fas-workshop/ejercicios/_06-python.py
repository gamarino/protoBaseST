"""Ejercicio 6, el paso de Python: leer lo que escribió protoST y confirmar en el mismo directorio.

Uso: python _06-python.py <directorio>   (lo corre 06-python-y-smalltalk.sh con proto_db fijado)

Cada lectura se verifica con assert: un valor distinto corta el programa con un error.
"""
import sys
from datetime import date
from decimal import Decimal

from proto_db import DBObject, F, FileStorage, ObjectSpace, from_collection


class Socio(DBObject):
    """El mismo tipo que taller.Socio en protoST."""

    __type_name__ = "taller.Socio"
    __type_aliases__ = ()


space = ObjectSpace(FileStorage(sys.argv[1]))
try:
    db = space.open_database("socios")
    tr = db.new_transaction()
    socios = tr.get_root_object("socios")
    uno = socios.get_at(1)
    assert isinstance(uno, Socio), type(uno)
    assert uno.cuota == Decimal("1500.50") and str(uno.cuota) == "1500.50", uno.cuota
    assert uno.alta == date(2026, 12, 3), uno.alta
    socios.validate()
    cordoba = from_collection(socios).where(F.ciudad == "Córdoba")
    plan = cordoba.explain()
    print("python leyó %s de %s, cuota %s; Córdoba: %s (%d socios)"
          % (uno.nombre, uno.ciudad, uno.cuota, plan["plan"], cordoba.count()))
    tr.abort()

    def trabajo(tr):
        socios = tr.get_root_object("socios")
        tr.set_root_object("socios", socios.set_at(41, Socio(
            nombre="socio41", ciudad="Córdoba", cuota=Decimal("999.99"), alta=date(2026, 12, 3))))
        tr.set_root_object("etiquetas", tr.new_dictionary().set_at("desde", "python"))

    db.run(trabajo)
    print("python confirmó la versión %d" % db.history()[0].version)
finally:
    space.close()

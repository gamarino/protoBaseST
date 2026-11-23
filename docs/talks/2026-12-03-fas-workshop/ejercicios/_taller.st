"_taller.st: ayuda común de los ejercicios (verificar.sh no corre los archivos que empiezan con _).

 Taller directorio: 'nombre' responde un directorio nuevo para la base de un ejercicio, dentro
 de $TALLER_DIR si está definida y si no en el directorio temporal del sistema. El nombre lleva
 el pid y el reloj, así que cada corrida usa uno nuevo. Los ejercicios no lo borran: queda para
 que lo miren con ls (son unos pocos KB)."

Object subclass: #Taller.

Taller class >> directorio: aString
  | base dir |
  base := Smalltalk getenv: 'TALLER_DIR'.
  base := base isNil ifTrue: [FileSystem temp] ifFalse: [FileReference path: base].
  dir := base / ('taller-' , aString , '-' , Smalltalk pid printString , '-' , Time millisecondClockValue printString).
  ^ dir.

"Imprime una línea. Las que empiezan con ~ son mediciones: verificar.sh no las compara."
Taller class >> di: aString
  Transcript showCr: aString.

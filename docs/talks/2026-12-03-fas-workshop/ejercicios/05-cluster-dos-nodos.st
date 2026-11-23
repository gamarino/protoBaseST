"Ejercicio 5 — Un cluster de dos nodos, y por qué conviene tener tres.

 Dos coordinadores comparten un directorio y hablan por una red en proceso
 (PBInProcessNetwork: los mismos mensajes que por TCP, sin sockets). Cada commit pide un permiso
 de escritura al dueño del término, construye la raíz y espera las aceptaciones sincronizadas de
 una mayoría. El protocolo es el de proto_db 2.0.0rc4 (protocolo 14), regla por regla.
 Antes de correrlo, anoten:
   a) ¿cuál es la mayoría de dos votantes?
   b) los dos nodos incrementan el mismo contador diez veces cada uno: ¿cuánto da?
   c) se cae n1. ¿Puede n0 seguir confirmando solo?
   d) n1 vuelve: ¿cuánto vale el contador? ¿Hay un solo valor posible?
   e) entonces, ¿un cluster de dos nodos es más o menos disponible que un proceso solo?

 STPATH=../../../../src protost 05-cluster-dos-nodos.st"

Import from: 'protobase'.
Import from: '_taller'.

| dir ids peers network nodes spaces until dbs tr outcome t0 |
dir := Taller directorio: '05'.
until := [:aBlock | | deadline |
  deadline := Time millisecondClockValue + 60000.
  [aBlock value or: [Time millisecondClockValue > deadline]] whileFalse: [(Future after: 10) wait].
  aBlock value].
ids := #('n0' 'n1').
peers := ids collect: [:id | PBPeer nodeId: id host: '127.0.0.1' port: 7400].
network := PBInProcessNetwork new.
"acquireTimeout corto, para que el nodo que quede solo se entere pronto. Solo afecta la vivacidad,
 nunca la seguridad."
nodes := ids collect: [:id | PBClusterCoordinator nodeId: id peers: peers options: (Dictionary new
  at: #leaseDuration put: 600;
  at: #requestTimeout put: 100;
  at: #acquireTimeout put: 2000;
  at: #transport put: network endpoint;
  yourself)].
nodes do: [:node | node start].
spaces := nodes collect: [:node |
  PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: node].
until value: [nodes allSatisfy: [:node | (node stats at: 'rejoining') not]].
Taller di: 'a) votantes: ' , (nodes first voters) asArray printString , ', mayoría: ' , nodes first majority printString.

"b) Cada nodo confirma diez incrementos; run: reintenta los conflictos, como en un proceso solo."
((spaces at: 1) newDatabase: 'taller') run: [:t | t setRootObject: 'contador' value: 0].
"newDatabase: es un commit más; en n1 sirve también de barrera: después ve la base que hizo n0."
(spaces at: 2) newDatabase: 'barrera-n1'.
dbs := spaces collect: [:space | space openDatabase: 'taller'].
1 to: 10 do: [:i |
  dbs do: [:db | db run: [:t | t setRootObject: 'contador' value: (t getRootObject: 'contador') + 1] retries: 100]].
"Una lectura local puede no ver todavía lo que confirmó el otro nodo: un commit que escribe es una barrera."
(dbs at: 2) run: [:t | t setRootObject: '_read_barrier' value: true].
tr := (dbs at: 2) newTransaction.
Taller di: 'b) contador leído en n1: ' , (tr getRootObject: 'contador') printString , ' de 20'.
tr abort.

"c) n1 se cae: su extremo de la red deja de mandar y de recibir. El disco queda."
(nodes at: 2) stop waitWithin: 60000.
1 to: 2 do: [:intento |
  t0 := Time millisecondClockValue.
  outcome := [(dbs at: 1) run: [:t | t setRootObject: 'contador' value: (t getRootObject: 'contador') + 1] retries: 0.
      'confirmó']
    on: PBTimeoutError, PBOutcomeUnknownError do: [:e |
      Taller di: '~ intento ' , intento printString , ': ' , e class name , ' — ' , e messageText.
      e return: 'no confirma'].
  Taller di: 'c) intento ' , intento printString , ' de n0 solo: ' , outcome.
  Taller di: '~ tardó ' , (Time millisecondClockValue - t0) printString , ' ms en rendirse'].

"d) n1 vuelve sobre su disco intacto: un coordinador nuevo, un espacio nuevo, el mismo directorio.
 Un PBOutcomeUnknownError quiere decir eso: el commit pudo haber quedado o no. Nunca a medias,
 nunca dos veces."
(spaces at: 2) close.
nodes at: 2 put: (PBClusterCoordinator nodeId: 'n1' peers: peers options: (Dictionary new
  at: #leaseDuration put: 600;
  at: #requestTimeout put: 100;
  at: #acquireTimeout put: 2000;
  at: #transport put: network endpoint;
  yourself)).
(nodes at: 2) start.
spaces at: 2 put: (PBObjectSpace storage: (PBFileStorage clusterPath: dir pathString) coordinator: (nodes at: 2)).
until value: [((nodes at: 2) stats at: 'rejoining') not].
outcome := nil.
until value: [
  outcome := [((spaces at: 1) openDatabase: 'taller') run: [:t | t setRootObject: '_read_barrier' value: true] retries: 0. true]
    on: PBTimeoutError, PBOutcomeUnknownError do: [:e | e return: false]].
tr := ((spaces at: 1) openDatabase: 'taller') newTransaction.
Taller di: 'd) n1 volvió; n0 confirma otra vez: ' , outcome printString.
Taller di: '   contador: 20 o 21 (nunca otro valor): ' , (#(20 21) includes: (tr getRootObject: 'contador')) printString.
Taller di: '~ contador: ' , (tr getRootObject: 'contador') printString.
tr abort.

spaces do: [:space | space close].
nodes do: [:node | node stop waitWithin: 60000].
Taller di: '~ el directorio queda en ' , dir pathString.

"-- floor.st: the protoST floor of protoBaseST, checked when the package loads --

protoBaseST 0.4.1 needs protoST 0.17.0 (with protoIO 0.7.1; README, Requirements). On an older
protoST it does not fail at once: the TCP sender's write timeout asks ConnectionTimedOut for
bytesWritten, which protoST 0.16.0 does not answer, and a frame is then dropped without a word
naming the cause; below 0.15.0 the first vector score signals MessageNotUnderstood; below 0.17.0
the write-once publishers' compareAndSet:from:to: is not understood. So the floor
is checked once, when this module loads: Import from: 'protobase' imports it right after the
errors, before any other module, and the modules that need the floor (cluster/transport,
vectors) import it too. A protoST below the floor makes the import signal PBNotSupportedError
naming the floor and every missing capability, so nothing of protoBaseST runs on it.

The check probes capabilities, not version strings: each probe asks whether the protoST running
answers a message protoBaseST sends, and names the release that brought it. A protoST that
reports any version but lacks one of them is refused; one that has them all passes.

The class keeps no state."

Import from: 'protobase/errors'.

Object subclass: #PBFloor.
PBFloor comment: 'The protoST floor of protoBaseST (0.17.0, with protoIO 0.7.1), checked when the package loads (check). Class side only; no state.'.

"The requirement the refusal states, word for word."
PBFloor class >> requirement
  ^ 'protoBaseST 0.4.1 requires protoST 0.17.0 or later (protoIO 0.7.1)'.

"The capabilities the floor guarantees, as an Array of { description. block answering whether
 this protoST has it }. A global missing altogether (an older protoST) is a missing capability,
 never an error of the probe."
PBFloor class >> probes
  | float timedOut |
  float := Smalltalk at: #Float ifAbsent: [nil].
  timedOut := Smalltalk at: #ConnectionTimedOut ifAbsent: [nil].
  ^ {
    { 'Object >> compareAndSet:from:to: (protoST 0.17.0)'.
      [Object canUnderstand: #compareAndSet:from:to:] }.
    { 'ConnectionTimedOut >> bytesWritten (protoST 0.16.1, protoIO 0.7.1)'.
      [timedOut notNil and: [timedOut canUnderstand: #bytesWritten]] }.
    { 'Float class >> fsum: (protoST 0.15.0)'.
      [float notNil and: [float respondsTo: #fsum:]] }.
    { 'Float class >> fsumOfProducts:with: (protoST 0.15.0)'.
      [float notNil and: [float respondsTo: #fsumOfProducts:with:]] }.
    { 'Float class >> fsumOfSquaredDifferences:with: (protoST 0.15.0)'.
      [float notNil and: [float respondsTo: #fsumOfSquaredDifferences:with:]] }.
    { 'Float class >> fsumOfPowSquaredDifferences:with: (protoST 0.16.0)'.
      [float notNil and: [float respondsTo: #fsumOfPowSquaredDifferences:with:]] } }.

"The descriptions of the probes this protoST fails, in the order of probes; empty on the floor
 or above it."
PBFloor class >> missing
  ^ (self probes reject: [:each | (each at: 2) value == true]) collect: [:each | each at: 1].

"The text of the refusal for anArray of missing capabilities (descriptions)."
PBFloor class >> refusalFor: anArray
  | stream |
  stream := WriteStream on: String new.
  stream nextPutAll: self requirement; nextPutAll: '; this protoST lacks '.
  anArray doWithIndex: [:each :i |
    i > 1 ifTrue: [stream nextPutAll: ', '].
    stream nextPutAll: each].
  stream nextPutAll: '. Build protoST 0.17.0 or later against protoIO 0.7.1 (README, Requirements).'.
  ^ stream contents.

"Answers true on the floor or above it; else signals PBNotSupportedError with refusalFor: of what
 is missing. Runs when the module loads."
PBFloor class >> check
  | missing |
  missing := self missing.
  missing isEmpty ifFalse: [^ PBNotSupportedError signal: (self refusalFor: missing)].
  ^ true.

PBFloor check.

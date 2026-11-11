"_keyvectors.st: shared pieces of the key runners (order.st, hashes.st, tokens.st; a helper).

  KeyVectors idOf: aDescription    the id of a manifest value in the expected-differences
                                   table: its kind, a space, then its body ('uuid ff00...',
                                   'int 1'); these sections have no ids of their own
  KeyVectors atomWithOid: aHexText an atom of the vectors' application type whose oid is
                                   known (rank 14 needs no record: ProtoBase's order key is
                                   the oid)"
Import from: 'protobase'.
Import from: '_vectors'.

Object subclass: #KeyVectors.

KeyVectors class >> idOf: aDescription
  | kind body |
  kind := aDescription associations first key.
  body := aDescription at: kind.
  ^ kind , ' ' , ((body isString and: [body isSymbol not]) ifTrue: [body] ifFalse: [body printString]).

KeyVectors class >> atomWithOid: aHexText
  ^ ConformanceInvoice basicNew _setOid: (PBNotation _bytesFromHex: aHexText) pointer: nil storage: nil.

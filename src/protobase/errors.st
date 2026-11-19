"-- errors.st: the protoBaseST error hierarchy --

Mirrors proto_db/errors.py at ProtoBase v2.0.0rc1 (plan call C14), with PB in place of Proto,
so that on: PBLockingError do: means the same in Smalltalk and in Python. ProtoBase classes
that are outside this prototype (pager tokens, misfiled entries, authorization,
backlog and refused writes) have no counterpart here, and the errors carry no code or message API yet:
they are added, additively, when a task needs them."

Error subclass: #PBDBError.
PBDBError comment: 'Root of every error protoBaseST signals. Counterpart of ProtoBase ProtoDBError.'.

PBDBError subclass: #PBValidationError.
PBValidationError comment: 'An invalid argument, schema or data shape. Counterpart of ProtoBase ProtoValidationError.'.

PBValidationError subclass: #PBReferenceError.
PBReferenceError comment: 'A reference to a database version that is malformed, names no version, or names a version of another database (a client error). Counterpart of ProtoBase ProtoReferenceError.'.

PBValidationError subclass: #PBClosedError.
PBClosedError comment: 'An operation on a closed database or storage, or a read of an object whose state was not loaded before the close. Counterpart of ProtoBase ProtoClosedError.'.

PBDBError subclass: #PBUserError.
PBUserError comment: 'An error caused by incorrect use of the API. Counterpart of ProtoBase ProtoUserError.'.

PBDBError subclass: #PBCorruptionError.
PBCorruptionError comment: 'Stored data failed an integrity check. Counterpart of ProtoBase ProtoCorruptionError.'.

PBCorruptionError subclass: #PBClusterProtocolError.
PBClusterProtocolError comment: 'Bytes received on a cluster connection that are not a valid message of protocol 14: not one msgpack map, a key that is not a string, a missing v, type or from, another version, an unknown type, a missing or ill-typed field, an ill-typed optional field, a root of a format version this node does not read (5 or above). The receiver drops the connection. Counterpart of proto_db ClusterProtocolError (proto_db/cluster/protocol.py).'.

PBDBError subclass: #PBNotSupportedError.
PBNotSupportedError comment: 'The requested value, type, version or operation is not supported. protoBaseST refuses explicitly instead of diverging from ProtoBase. Counterpart of ProtoBase ProtoNotSupportedError.'.

PBDBError subclass: #PBUnexpectedError.
PBUnexpectedError comment: 'An internal error that should not happen. Counterpart of ProtoBase ProtoUnexpectedError.'.

PBUnexpectedError subclass: #PBOutcomeUnknownError.
PBOutcomeUnknownError comment: 'The outcome of a write (typically a root publish) is unknown: it may or may not have been applied. Never a PBConflictError, so a retry loop must not retry it. Counterpart of ProtoBase ProtoOutcomeUnknownError.'.

PBDBError subclass: #PBLockingError.
PBLockingError comment: 'A failure to take a lock or to commit because of concurrent writers. Counterpart of ProtoBase ProtoLockingError.'.

PBLockingError subclass: #PBConflictError instanceVariableNames: 'permitHeld cause'.
PBConflictError comment: 'A commit conflicts with a commit made after the transaction started. Retrying the whole transaction may succeed. Counterpart of ProtoBase ProtoConflictError.'.

"A PBConflictError with aText whose round keeps its write permission for the retry (proto_db
 ProtoConflictError.permit_held, D-LIVE-2): the caller's retry should start at once, from the
 root that permission committed."
PBConflictError class >> held: aText
  ^ self new _setPermitHeld: true text: aText cause: nil.

"A PBConflictError with aText that anError caused (proto_db raise ProtoConflictError(...) from
 error: the error is the conflict's __cause__), not held."
PBConflictError class >> text: aText cause: anError
  ^ self new _setPermitHeld: false text: aText cause: anError.

PBConflictError >> _setPermitHeld: aBoolean text: aText cause: anError
  "Runs once, on a fresh instance."
  permitHeld isNil ifFalse: [^ PBUserError signal: 'PBConflictError: permitHeld is set once'].
  permitHeld := aBoolean.
  cause := anError.
  self messageText: aText.
  ^ self.

"The error that caused this conflict (proto_db __cause__), nil unless made by text:cause:."
PBConflictError >> cause
  ^ cause.

"Whether the round that answered this conflict keeps its permission for the retry (D-LIVE-2);
 false unless made by held:."
PBConflictError >> permitHeld
  ^ permitHeld == true.

PBLockingError subclass: #PBTimeoutError.
PBTimeoutError comment: 'A lock was not obtained within its timeout (milliseconds). It is not protoST TimeoutError, which signals a passed deadline of a Future. Counterpart of ProtoBase ProtoTimeoutError.'.

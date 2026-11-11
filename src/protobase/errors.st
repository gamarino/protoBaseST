"-- errors.st: the protoBaseST error hierarchy --

Mirrors proto_db/errors.py at ProtoBase v2.0.0rc1 (plan call C14), with PB in place of Proto,
so that on: PBLockingError do: means the same in Smalltalk and in Python. ProtoBase classes
that are outside this prototype (references, pager tokens, misfiled entries, authorization,
backlog and refused writes) have no counterpart here."

Error subclass: #PBDBError.
PBDBError comment: 'Root of every error protoBaseST signals. Counterpart of ProtoBase ProtoDBError.'.

PBDBError subclass: #PBValidationError.
PBValidationError comment: 'An invalid argument, schema or data shape. Counterpart of ProtoBase ProtoValidationError.'.

PBValidationError subclass: #PBClosedError.
PBClosedError comment: 'An operation on a closed database or storage, or a read of an object whose state was not loaded before the close. Counterpart of ProtoBase ProtoClosedError.'.

PBDBError subclass: #PBUserError.
PBUserError comment: 'An error caused by incorrect use of the API. Counterpart of ProtoBase ProtoUserError.'.

PBDBError subclass: #PBCorruptionError.
PBCorruptionError comment: 'Stored data failed an integrity check. Counterpart of ProtoBase ProtoCorruptionError.'.

PBDBError subclass: #PBNotSupportedError.
PBNotSupportedError comment: 'The requested value, type, version or operation is not supported. protoBaseST refuses explicitly instead of diverging from ProtoBase. Counterpart of ProtoBase ProtoNotSupportedError.'.

PBDBError subclass: #PBUnexpectedError.
PBUnexpectedError comment: 'An internal error that should not happen. Counterpart of ProtoBase ProtoUnexpectedError.'.

PBUnexpectedError subclass: #PBOutcomeUnknownError.
PBOutcomeUnknownError comment: 'The outcome of a write (typically a root publish) is unknown: it may or may not have been applied. Never a PBConflictError, so a retry loop must not retry it. Counterpart of ProtoBase ProtoOutcomeUnknownError.'.

PBDBError subclass: #PBLockingError.
PBLockingError comment: 'A failure to take a lock or to commit because of concurrent writers. Counterpart of ProtoBase ProtoLockingError.'.

PBLockingError subclass: #PBConflictError.
PBConflictError comment: 'A commit conflicts with a commit made after the transaction started. Retrying the whole transaction may succeed. Counterpart of ProtoBase ProtoConflictError.'.

PBLockingError subclass: #PBTimeoutError.
PBTimeoutError comment: 'A lock was not obtained within its timeout (milliseconds). It is not protoST TimeoutError, which signals a passed deadline of a Future. Counterpart of ProtoBase ProtoTimeoutError.'.

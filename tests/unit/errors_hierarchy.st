"EXPECT: true true true true true true"
"The error hierarchy mirrors proto_db/errors.py (plan call C14); PBClusterProtocolError mirrors
 ClusterProtocolError of proto_db/cluster/protocol.py, a ProtoCorruptionError, and PBMisfiledError
 mirrors ProtoMisfiledError, a ProtoCorruptionError too (indexed queries, plan Task 2)."
Import from: 'protobase'.
((PBConflictError inheritsFrom: PBLockingError) printString, ' ',
 (PBClosedError inheritsFrom: PBValidationError) printString, ' ',
 (PBOutcomeUnknownError inheritsFrom: PBUnexpectedError) printString, ' ',
 (((PBTimeoutError inheritsFrom: TimeoutError)) not) printString, ' ',
 (PBClusterProtocolError inheritsFrom: PBCorruptionError) printString, ' ',
 (PBMisfiledError inheritsFrom: PBCorruptionError) printString) displayNl

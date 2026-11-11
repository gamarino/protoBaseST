"EXPECT: true true true true"
"The error hierarchy mirrors proto_db/errors.py (plan call C14)."
Import from: 'protobase'.
((PBConflictError inheritsFrom: PBLockingError) printString, ' ',
 (PBClosedError inheritsFrom: PBValidationError) printString, ' ',
 (PBOutcomeUnknownError inheritsFrom: PBUnexpectedError) printString, ' ',
 (((PBTimeoutError inheritsFrom: TimeoutError)) not) printString) displayNl

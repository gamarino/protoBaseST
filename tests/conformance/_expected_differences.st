"_expected_differences.st: where protoBaseST differs from the manifest on purpose (a helper).

Tracked data, never only in a workspace: the table of Task 8 in the plan
(docs/superpowers/plans/2026-11-10-protobasest-prototype.md) with the stages
each difference shows in. Every entry is:

  section  id  stages  reason  removedBy

stages is an Array of { stage. error class name }: the class name is nil when the stage
fails by a mismatch (no error), else the PBDBError class it signals; both must match.

section is the manifest section ('values', 'values_decode_only',
'values_read_not_rewritten', 'invalid'). stages are the checks of the vector
that fail, exactly (a vector that fails a stage or an error class not listed, or passes a listed
one, is a FAIL of the runner, so the list cannot go stale):

  decode     the decoded value does not describe as the manifest's value
  encode     the manifest's value does not encode to the vector's bytes
  reencode   the decoded value does not re-encode to the canonical file
  refuse     the decoded value is re-encoded instead of refused (PBValidationError)
  accepted   an invalid vector is accepted instead of refused
  refusal    (never listed) an invalid vector is refused with the wrong class

removedBy is a plan task, or 'permanent, design 4.3' (the design spec, section
4.3: no time-zone database)."

Object subclass: #ExpectedDifferences.

ExpectedDifferences class >> all
  ^ {
    { 'values'. 'uuid'. #(#('decode' 'PBNotSupportedError') #('encode' 'PBNotSupportedError')).
      'decode: PBNotSupportedError; the value cannot even be built: lib/uuid.st is not in protoST 0.9.0'.
      'Task 5, Step 6' }.
    { 'values_decode_only'. 'ref-format2'. #(#('reencode' nil)).
      're-encodes with the type name, not the alias: the name to alias table is PBTypeRegistry''s'.
      'Task 9' }.
    { 'values_decode_only'. 'ref-name-of-builtin'. #(#('reencode' nil)).
      're-encodes with the type name, not the alias: the name to alias table is PBTypeRegistry''s'.
      'Task 9' }.
    { 'values_decode_only'. 'ref-alias'. #(#('decode' nil) #('reencode' nil)).
      'keeps the alias name conformance.LegacyInvoice, it does not map it to the declared name: application aliases are PBTypeRegistry''s'.
      'Task 9' }.
    { 'values_decode_only'. 'datetime-zone-format3'. #(#('decode' nil) #('reencode' 'PBValidationError')).
      'decodes to a PBLegacyZoneDateTime (wall clock), not the instant; re-encoding it is PBValidationError: the instant needs a tz database'.
      'permanent, design 4.3' }.
    { 'values_read_not_rewritten'. 'map-zone-key-format3'. #(#('decode' nil)).
      're-encoding is refused, as listed; the decoded keys are the format-3 wall clocks, not instants'.
      'permanent, design 4.3' }.
    { 'values_read_not_rewritten'. 'map-nan-keys-format3'. #(#('refuse' nil)).
      're-encodes instead of PBValidationError: the NaN-token conflict of a writer is PBKeys checkMapKeys:'.
      'Task 10' }.
    { 'values_read_not_rewritten'. 'map-decimal-nan-keys-format3'. #(#('refuse' nil)).
      're-encodes instead of PBValidationError: the NaN-token conflict of a writer is PBKeys checkMapKeys:'.
      'Task 10' }.
    { 'invalid'. 'value-instant-wall-out-of-range'. #(#('accepted' nil)).
      'accepted and presented in UTC: the wall-clock range needs the zone''s rules; the format spec (Known gaps) lets a reader without a database present the instant in UTC'.
      'permanent, design 4.3' }.
    { 'invalid'. 'map-key-bool-and-int'. #(#('accepted' nil)).
      'accepted: the cross-kind conflict rule needs order keys'.
      'Task 10' }.
    { 'invalid'. 'map-key-equal-numbers'. #(#('accepted' nil)).
      'accepted: the cross-kind conflict rule needs order keys'.
      'Task 10' } }.

"The entries of one section, as an OrderedCollection."
ExpectedDifferences class >> forSection: aSection
  ^ (self all select: [:each | (each at: 1) = aSection]) asOrderedCollection.

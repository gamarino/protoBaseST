"_expected_differences.st: where protoBaseST differs from the manifest on purpose (a helper).

Tracked data, never only in a workspace: the table of Task 8 in the plan
(docs/superpowers/plans/2026-11-10-protobasest-prototype.md) with the stages
each difference shows in. Every entry is:

  section  id  stages  reason  removedBy

stages is an Array of { stage. error class name }: the class name is nil when the stage
fails by a mismatch (no error), else the PBDBError class it signals; both must match.

section is the manifest section ('values', 'values_decode_only',
'values_read_not_rewritten', 'invalid', 'order', 'hashes', 'exact_tokens',
'database', whose ids are record offsets; 'database_contents', whose ids are the
items of database_contents.st; the
key runners name a value 'kind body', as _keyvectors.st does). stages are the checks of the vector
that fail, exactly (a vector that fails a stage or an error class not listed, or passes a listed
one, is a FAIL of the runner, so the list cannot go stale):

  decode     the decoded value does not describe as the manifest's value
  encode     the manifest's value does not encode to the vector's bytes
  reencode   the decoded value does not re-encode to the canonical file
  refuse     the decoded value is re-encoded instead of refused (PBValidationError)
  accepted   an invalid vector is accepted instead of refused
  refusal    an invalid vector is refused with the wrong class (listed only while
             the class that refuses it correctly does not exist yet)
  order      (order.st) the value does not order after every earlier one
  hash       (hashes.st) the value's hash key is not the listed one
  token      (tokens.st) the value's exact token is not the listed one
  describe   (database_contents.st) the description of a part of the database is not
             the manifest's contents
  open       (format5_refused.st, section 'format5', whose ids are the manifest's
             parents_database, registry_database and cluster.roots_log_v5) the space or
             the acceptor log is not opened and read as the manifest lists it

removedBy is a plan task, or 'permanent, design 4.3' (the design spec, section
4.3: no time-zone database), or 'the runtime-registry plan (D62)' (format 5, not read
by protoBaseST: docs/deviations.md, 'Reading')."

Object subclass: #ExpectedDifferences.

ExpectedDifferences class >> all
  ^ {
    { 'values_decode_only'. 'datetime-zone-format3'. #(#('decode' nil) #('reencode' 'PBValidationError')).
      'decodes to a PBLegacyZoneDateTime (wall clock), not the instant; re-encoding it is PBValidationError: the instant needs a tz database'.
      'permanent, design 4.3' }.
    { 'values_read_not_rewritten'. 'map-zone-key-format3'. #(#('decode' nil)).
      're-encoding is refused, as listed; the decoded keys are the format-3 wall clocks, not instants'.
      'permanent, design 4.3' }.
    { 'invalid'. 'value-instant-wall-out-of-range'. #(#('accepted' nil)).
      'accepted and presented in UTC: the wall-clock range needs the zone''s rules; the format spec (Known gaps) lets a reader without a database present the instant in UTC'.
      'permanent, design 4.3' }.
    { 'format5'. 'parents_database'. #(#('open' 'PBNotSupportedError')).
      'a format-5 space (feature parents): its root record is version 5, refused at open; protoBaseST reads formats 2 to 4'.
      'the runtime-registry plan (D62)' }.
    { 'format5'. 'registry_database'. #(#('open' 'PBNotSupportedError')).
      'a format-5 space (feature registry): its root record is version 5, refused at open; protoBaseST reads formats 2 to 4'.
      'the runtime-registry plan (D62)' }.
    { 'format5'. 'roots_log_v5'. #(#('open' 'PBNotSupportedError')).
      'an acceptor log of log format 3 (kind-7 entries of format-5 roots), refused at its header; protoBaseST reads log format 2'.
      'the runtime-registry plan (D62)' } }.

"The entries of one section, as an OrderedCollection."
ExpectedDifferences class >> forSection: aSection
  ^ (self all select: [:each | (each at: 1) = aSection]) asOrderedCollection.

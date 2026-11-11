# Changelog

## 0.1.0 (unreleased)

- Repository skeleton: error hierarchy mirroring ProtoBase, test runner, vendored
  conformance vectors (ProtoBase `v2.0.0rc1`), Python interop venv and week-0 checks.
- Values and the canonical codec: `PBFrozenList`, `PBTuple`, `PBFrozenDict`, `PBMissing`,
  `PBMutableObject` (the handle), `PBAtomPointer`, `PBUnresolvedRef` and `PBLegacyZoneDateTime`;
  `PBCodec` with `canonical:`, `toWire:atomRef:`, `fromWire:resolver:`, `encode:` and `decode:`.
  The bytes are those of ProtoBase `v2.0.0rc1`; every refusal of the format spec is explicit
  (`PBValidationError` when writing, `PBCorruptionError` when reading, `PBNotSupportedError`
  for what needs a time-zone database or `lib/uuid.st`).
- Time-zone keys are checked against `PBZoneKeys`, a committed list of the IANA tzdata 2026e
  keys (`tools/gen_zone_keys.py`), never against the host's zoneinfo. Instant-form datetimes are
  read and presented in UTC. Format-3 zone-datetime map keys whose conflicts need offsets are
  refused (`PBNotSupportedError`). Lone surrogates and values nested deeper than 511 msgpack
  containers are refused with `PBValidationError`. Duplicate map keys are found in linear time.

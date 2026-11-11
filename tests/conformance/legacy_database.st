"EXPECT: legacy contents ok, 3 expected refusals"
"The legacy_database section read as a database (README, 'Using the vectors', 7, the
 format-3 space), on a copy of vectors/legacy: every root, the mutables, the indexes
 (format-3 indexes read, with member_tokens false) and the origin (absent: nil) must
 be the manifest's contents. Three roots hold format-3 ['zone', key] datetimes,
 which decode to PBLegacyZoneDateTime (design 4.3): describing them as ProtoBase does
 (the UTC instant) needs the zone's rules, so PBNotation describeObject: refuses them
 with PBNotSupportedError naming the zone. They are the expected refusals listed
 below by root name; a listed root that is described, or another root that is
 refused, is a FAIL, and so is describeDatabase: answering instead of refusing. The
 index rebuild after a change and the detection of the misfiled roots need the
 writer and validate(), which the prototype does not have: they print SKIP-ITEM lines."
Import from: 'protobase'.
Import from: '_vectors'.
| manifest section contents dir space db snap failures refusals expectedRefusals check |
manifest := Vectors manifest.
section := manifest at: 'legacy_database'.
contents := section at: 'contents'.
"The roots whose records hold a format-3 zone datetime (manifest records 1805, 8670 and
 9188, canonical false), with the zone each refusal names."
expectedRefusals := Dictionary new.
expectedRefusals at: 'invoice' put: 'America/New_York'; at: 'maps' put: 'America/New_York';
  at: 'numbers' put: 'America/New_York'.
failures := 0.
refusals := 0.
check := [:what :actual :expected |
  actual = expected ifFalse: [
    failures := failures + 1.
    ('FAIL ' , what , ': ' , (Vectors json stringify: actual) , ', the manifest says '
      , (Vectors json stringify: expected)) displayNl]].
dir := Vectors copySpace: 'legacy_database'.
space := PBObjectSpace storage: (PBFileStorage path: dir).
check value: 'listDatabases' value: space listDatabases asArray value: #('db').
db := space openDatabase: 'db'.
snap := db snapshotAt: db history first.
check value: 'rootNames' value: snap rootNames asArray value: ((contents at: 'roots') collect: [:pair | pair at: 1]).
(contents at: 'roots') do: [:pair |
  | name zone outcome |
  name := pair at: 1.
  zone := expectedRefusals at: name ifAbsent: [nil].
  outcome := [PBNotation describeObject: (snap getRootObject: name)] on: PBNotSupportedError do: [:e |
    e return: { #refused. e messageText }].
  ((outcome isKindOf: Array) and: [outcome size = 2 and: [(outcome at: 1) == #refused]])
    ifTrue: [
      (zone notNil and: [(outcome at: 2) includesSubstring: zone])
        ifTrue: [
          refusals := refusals + 1.
          ('EXPECTED REFUSAL root ' , name , ': ' , (outcome at: 2)) displayNl]
        ifFalse: [
          failures := failures + 1.
          ('FAIL root ' , name , ': refused: ' , (outcome at: 2)) displayNl]]
    ifFalse: [
      zone isNil
        ifTrue: [check value: 'root ' , name value: outcome value: (pair at: 2)]
        ifFalse: [
          failures := failures + 1.
          ('FAIL root ' , name , ': listed as an expected refusal, but it was described') displayNl]]].
check value: 'the mutables' value: (PBNotation describeMutables: snap) value: (contents at: 'mutables').
check value: 'the indexes' value: (PBNotation describeIndexes: snap) value: (contents at: 'indexes').
check value: 'the origin' value: (PBNotation describeOrigin: snap) value: (contents at: 'origin').
([PBNotation describeDatabase: snap. false] on: PBNotSupportedError do: [:e | e return: true]) ifFalse: [
  failures := failures + 1.
  'FAIL describeDatabase: described a database that holds format-3 zone datetimes' displayNl].
('SKIP-ITEM: index rebuild: after a change of ' , ((contents at: 'indexes') keys asArray sorted) printString
  , ' each format-3 index is rebuilt with format-4 tokens (needs the writer, plan Tasks 15-16)') displayNl.
('SKIP-ITEM: misfiled detection: ' , ((section at: 'misfiled') at: 'roots') printString
  , ' (needs validate(), outside the prototype)') displayNl.
space close.
dir deleteAll.
failures > 0
  ifTrue: [('FAILED ' , failures printString , ' check(s)') displayNl]
  ifFalse: [('legacy contents ok, ' , refusals printString , ' expected refusals') displayNl]

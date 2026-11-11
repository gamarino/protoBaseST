"EXPECT: 73 59"
"Week-0 check (Spec 9): lib/json.st parses the vendored conformance manifest."
| m manifest |
m := Import from: 'json'.
manifest := m JSON parse: ('../conformance/manifest.json' asFileReference contents).
((manifest at: 'values') size printString, ' ', (manifest at: 'invalid') size printString) displayNl

"EXPECT: 73 66"
"Week-0 check (Spec 9): lib/json.st parses the vendored conformance manifest (ProtoBase v2.0.0rc2: 73 values, 66 invalid vectors, seven of them value-depth-over-*)."
| m manifest |
m := Import from: 'json'.
manifest := m JSON parse: ('../conformance/manifest.json' asFileReference contents).
((manifest at: 'values') size printString, ' ', (manifest at: 'invalid') size printString) displayNl

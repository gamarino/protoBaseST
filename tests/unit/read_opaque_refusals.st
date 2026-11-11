"EXPECT: ok 17"
"Opaque atoms (D59, plan Task 12): a record of a type with no class here reads as a
 PBOpaqueAtom with its fields; anything that needs the type's behaviour (a change, a
 collection message, any other message, a field it does not hold, its use where a
 built-in type is expected) signals PBNotSupportedError naming the type. The space is
 built here, in a temporary directory named after the process id."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_spaces'.

| c base b thing indexSet list holder st loadedHolder opaque loadedList |
c := Check new.
base := FileSystem temp / ('pbst-read-opaque-' , Smalltalk pid printString).
base deleteAll.
b := SpaceBuilder segment: (ByteArray fromHex: '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a').
thing := b add: 'acme.sales.Thing' oid: 1 state: { 'x' -> 1. 'name' -> 't' }.
indexSet := b add: 3 oid: 2 state: { 'root' -> nil }.
"A List whose tree is the opaque atom: a collection used where a tree is expected."
list := b add: 5 oid: 3 state: { 'root' -> thing. 'count' -> 1. 'indexes' -> indexSet }.
holder := b add: 19 oid: 4 state: { 'thing' -> thing. 'list' -> list }.
b writeTo: base root: holder.
st := PBFileStorage path: base.
loadedHolder := PBTypeRegistry unloadedAtomFor: 19 at: holder pointer storage: st.
opaque := loadedHolder at: 'thing'.

c that: 'an unknown type reads as an opaque atom' is: opaque class equals: PBOpaqueAtom.
c that: 'its tag is the name it was referenced by' is: opaque tag equals: 'acme.sales.Thing'.
c that: 'its typeName is that name (design spec 8.1)' is: opaque typeName equals: 'acme.sales.Thing'.
c that: 'its fields read' is: (opaque at: 'x') equals: 1.
c that: 'its attribute names' is: opaque attributeNames equals: #('name' 'x').
c that: 'a field it does not hold' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  opaque at: 'missing'].
c that: 'setAt:value:' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  opaque setAt: 1 value: 2].
c that: 'with:value:' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  opaque with: 'a' value: 1].
c that: 'do:' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  opaque do: [:each | each]].
c that: 'getAt:' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  opaque getAt: 1].
c that: 'hasDefinedAttr:' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  opaque hasDefinedAttr: 'x'].
c that: 'any other message (doesNotUnderstand:)' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  opaque frobnicate: 3].
c that: 'a class never reaches its instance-side doesNotUnderstand: (protoST D52)' signals: MessageNotUnderstood during: [
  PBOpaqueAtom frobnicate: 3].
loadedList := loadedHolder at: 'list'.
c that: 'a list reads its count' is: loadedList count equals: 1.
c that: 'an opaque atom where a tree node is expected' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  loadedList do: [:each | each]].
c that: 'getAt: through that list' signals: PBNotSupportedError containing: 'acme.sales.Thing' during: [
  loadedList getAt: 0].
c that: 'the opaque atom keeps its oid' is: opaque oid equals: (ByteArray withAll: ((1 to: 16) asArray collect: [:i | 1])).
st close.
base deleteAll.
c report displayNl.

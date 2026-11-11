"EXPECT: unchanged unchanged"
"The Pharo clash of design spec 5.3, documented: ProtoBase's names answer a new version and
 never change the receiver, where Pharo's OrderedCollection >> addLast: and Set >> add:
 change it in place. A statement that discards the result of appendLast: or add: changes
 nothing, and nothing fails: the program must use the answer."
Import from: 'protobase'.

| l s lSize sSize |
l := (PBList new appendLast: 1) appendLast: 2.
s := (PBSet new add: 1) add: 2.
lSize := l size.
sSize := s size.
l appendLast: 3.
s add: 3.
((l size = lSize ifTrue: ['unchanged'] ifFalse: ['changed']) , ' '
  , (s size = sSize ifTrue: ['unchanged'] ifFalse: ['changed'])) displayNl.

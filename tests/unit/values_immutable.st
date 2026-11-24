"EXPECT: ok"
"Spec 12.6 (decision 3, immutability by convention): in src/protobase/*.st and src/protobase/cluster/*.st an
 instance or class variable is assigned only by the initialisers listed in
 _ivar_allowlist.txt (Class>>selector, or Class class>>selector), which the
 class-side constructors call once, or which publish a runtime-only field once
 by compare-and-swap (compareAndSet:from:to:, plan Task 16b). The candidates are
 grep -n over the sources for ':= ' and 'compareAndSet:'; a scan of each file
 keeps those in code (not in comments or strings) and checks that grep missed
 none. An assignment is to a field when its target is an instance variable of
 the method's class, or a capitalized name (a class variable); every
 compareAndSet: in code writes a field. A stale allowlist entry fails too. The values
 themselves answer no mutator and keep no reference to their arguments."
Import from: 'protobase'.
| failures grep allow used scans methodOf list dict frozen map handle |
failures := OrderedCollection new.

"The (line -> target) assignments in the code of aText, skipping comments, strings and
 character literals; a compareAndSet: send is (line -> 'compareAndSet:'); a symbol literal
 (#compareAndSet:from:to:, as the floor probe) is not a send."
scans := [:aText |
  | out line state i n |
  out := OrderedCollection new. line := 1. state := #code. i := 1. n := aText size.
  [i <= n] whileTrue: [
    | ch |
    ch := aText at: i.
    ch = Character lf ifTrue: [line := line + 1].
    state = #code
      ifTrue: [
        ch = $" ifTrue: [state := #comment].
        ch = $' ifTrue: [state := #string].
        ch = $$ ifTrue: [i := i + 1. (i <= n and: [(aText at: i) = Character lf]) ifTrue: [line := line + 1]].
        (ch = $c and: [(i + 13) <= n and: [(i = 1 or: [(aText at: i - 1) ~= $#]) and: [(aText copyFrom: i to: i + 13) = 'compareAndSet:']]]) ifTrue: [
          out add: line -> 'compareAndSet:'].
        (ch = $: and: [i < n and: [(aText at: i + 1) = $=]]) ifTrue: [
          | j k |
          j := i - 1.
          [j >= 1 and: [(aText at: j) = $ ]] whileTrue: [j := j - 1].
          k := j.
          [k >= 1 and: [(aText at: k) isLetter or: [(aText at: k) isDigit or: [(aText at: k) = $_]]]] whileTrue: [k := k - 1].
          out add: line -> (aText copyFrom: k + 1 to: j)]]
      ifFalse: [
        (state = #comment and: [ch = $"]) ifTrue: [state := #code].
        (state = #string and: [ch = $']) ifTrue: [
          (i < n and: [(aText at: i + 1) = $'])
            ifTrue: [i := i + 1]
            ifFalse: [state := #code]]].
    i := i + 1].
  out].

"The 'Class>>selector' or 'Class class>>selector' of the method holding line n, or '<module>'."
methodOf := [:lines :n |
  | found k |
  found := '<module>'.
  k := n.
  [k >= 1 and: [found = '<module>']] whileTrue: [
    | l words |
    l := lines at: k.
    words := l subStrings: ' '.
    ((l notEmpty and: [(l at: 1) isLetter or: [(l at: 1) = $_]])
        and: [words size >= 3 and: [(words at: 2) = '>>' or: [(words at: 2) = 'class' and: [(words at: 3) = '>>']]]])
      ifTrue: [
        | cls rest sel |
        cls := (words at: 2) = 'class' ifTrue: [(words at: 1) , ' class'] ifFalse: [words at: 1].
        rest := (words at: 2) = 'class'
          ifTrue: [words copyFrom: 4 to: words size]
          ifFalse: [words copyFrom: 3 to: words size].
        sel := (rest first last = $:)
          ifTrue: [
            | s idx |
            s := ''. idx := 1.
            [idx <= rest size and: [(rest at: idx) last = $:]] whileTrue: [s := s , (rest at: idx). idx := idx + 2].
            s]
          ifFalse: [rest first].
        found := cls , '>>' , sel].
    k := k - 1].
  found].

allow := ((FileReference path: '_ivar_allowlist.txt') lines
  reject: [:l | l isEmpty or: [l first = $#]]) asArray.
used := Set new.
grep := OSProcess shell: 'grep -n -e '':= '' -e ''compareAndSet:'' ../../src/protobase/*.st ../../src/protobase/cluster/*.st'.
grep exitCode = 0 ifFalse: [failures add: 'grep failed: ' , grep errorOutput].
"file -> the grep line numbers"
dict := Dictionary new.
(grep output subStrings: (String with: Character lf)) do: [:hit |
  | parts |
  parts := hit subStrings: ':'.
  (dict at: (parts at: 1) ifAbsentPut: [OrderedCollection new]) add: (parts at: 2) asNumber].
dict keysAndValuesDo: [:file :grepLines |
  | text lines |
  text := (FileReference path: file) contents.
  lines := (FileReference path: file) lines asArray.
  (scans value: text) do: [:assoc |
    | where cls ivars target isField |
    (grepLines includes: assoc key) ifFalse: [
      failures add: file , ':' , assoc key printString , ' an assignment grep does not see (write '':= '' or ''compareAndSet:'')'].
    where := methodOf value: lines value: assoc key.
    target := assoc value.
    cls := where = '<module>' ifTrue: [nil] ifFalse: [Smalltalk at: ((where subStrings: '>') first subStrings: ' ') first asSymbol ifAbsent: [nil]].
    ivars := (cls isNil or: [where includesSubstring: ' class>>']) ifTrue: [#()] ifFalse: [cls allInstVarNames].
    isField := (target = 'compareAndSet:' or: [ivars includes: target]) or: [target notEmpty and: [target first isUppercase]].
    isField ifTrue: [
      (allow includes: where)
        ifTrue: [used add: where]
        ifFalse: [failures add: file , ':' , assoc key printString , ' ' , where , ' assigns ' , target]]]].
allow do: [:entry | (used includes: entry) ifFalse: [failures add: 'stale allowlist entry: ' , entry]].

"The values answer no mutator, and copy what they are built from."
list := #(1 2) copy.
frozen := PBFrozenList withAll: list.
list at: 1 put: 99.
(frozen at: 1) = 1 ifFalse: [failures add: 'PBFrozenList shares its argument'].
frozen asArray at: 1 put: 7.
(frozen at: 1) = 1 ifFalse: [failures add: 'asArray exposes the items'].
#( #at:put: #add: #addLast: #removeFirst #removeKey: #at:ifAbsentPut: ) do: [:sel |
  { PBFrozenList withAll: #(1). PBTuple withAll: #(1). PBFrozenDict withAssociations: { 1 -> 2 } } do: [:v |
    (v respondsTo: sel) ifTrue: [failures add: v class name , ' answers ' , sel]]].
map := PBFrozenDict withAssociations: { 'k' -> 1 }.
map associations first value: 5.
(map at: 'k') = 1 ifFalse: [failures add: 'PBFrozenDict associations expose the entries'].
handle := PBMutableObject name: 'a'.
[handle _setCellName: 'b'] on: PBUserError do: [:e | nil].
handle name = 'a' ifFalse: [failures add: 'PBMutableObject initialiser runs twice'].

failures do: [:f | ('FAIL ' , f) displayNl].
(failures isEmpty ifTrue: ['ok'] ifFalse: ['failed']) displayNl.

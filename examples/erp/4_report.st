"Step 4, protoST: the as-of report. 4_report.py prints the same text.

  protost 4_report.st <directory>

Three moments, each the committedAt of a commit made by an earlier step (version 1: created,
2: paid, 3: renamed), never a clock reading. asOf finds the newest version committed at or
before a moment (design spec 6.5), and the report reads that version only. Two commits with
the same timestamp would resolve to the newer one, so the script refuses to run unless the
three moments are strictly increasing, and it checks that asOf found the version it meant.

A script has no class to hold helpers, so they are blocks bound to temporaries."
Import from: 'protobase'.
Import from: 'erp_model'.

| space db moments committedAt asOf centsOf money report |
space := PBObjectSpace storage: (PBFileStorage path: (Smalltalk arguments at: 1)).
db := space openDatabase: 'erp'.
moments := { 1 -> 'invoices created'. 2 -> 'payments recorded'. 3 -> 'ACME renamed' }.

"The snapshot of the newest version committed at or before aMoment."
asOf := [:aMoment |
    | entry |
    entry := db history detect: [:each | each committedAt <= aMoment]
        ifNone: [PBUserError signal: 'the database did not exist yet'].
    db snapshotAt: entry].

"An invoice total in whole cents (the Decimal is exact)."
centsOf := [:anInvoice | (anInvoice total asExactFraction * 100) truncated].

"Cents as 'units.cc', with two digits for the cents: 54060 prints as 540.60."
money := [:cents |
    (cents // 100) printString , '.' , ((cents \\ 100) printPaddedWith: $0 to: 2)].

report := [:snapshot :title |
    | invoices paid |
    invoices := (snapshot getRootObject: 'invoices') values.
    paid := invoices select: [:each | each isPaid].
    ('== ' , title , ' (version ' , snapshot version printString , ') ==') displayNl.
    snapshot mutableNames do: [:cell |
        | mine |
        mine := invoices select: [:each | each customer name = cell].
        (cell , ' | ' , (snapshot getMutable: cell) name , ' | ' , mine size printString , ' invoices | billed '
            , (money value: ((mine collect: centsOf) inject: 0 into: [:a :b | a + b]))
            , ' | paid '
            , (money value: (((mine select: [:each | each isPaid]) collect: centsOf) inject: 0 into: [:a :b | a + b])))
            displayNl].
    ('paid invoices: ' , (paid isEmpty ifTrue: ['none']
        ifFalse: [' ' join: (paid collect: [:each | each number printString])])) displayNl].

committedAt := Dictionary new.
db history do: [:entry | committedAt at: entry version put: entry committedAt].
((committedAt at: 1) < (committedAt at: 2) and: [(committedAt at: 2) < (committedAt at: 3)])
    ifFalse: [^ Error signal: 'two demo commits share a timestamp: the moments cannot be told apart'].

moments do: [:each | | snapshot |
    snapshot := asOf value: (committedAt at: each key).
    snapshot version = each key
        ifFalse: [^ Error signal: 'asOf found version ' , snapshot version printString , ', not ' , each key printString].
    report value: snapshot value: 'moment ' , each key printString , ': ' , each value].

('tags now: ' , (' ' join: (((db snapshotAt: db history first) getRootObject: 'tags') items
    collect: [:each | each key printString , '=' , each value]))) displayNl.
space close.

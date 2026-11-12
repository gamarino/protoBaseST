"Step 4, protoST: the as-of report. 4_report.py prints the same text.

  protost 4_report.st <directory>

Three moments, each the committedAt of a commit made by an earlier step (version 1: created,
2: paid, 3: renamed), never a clock reading. asOf finds the newest version committed at or
before a moment (design spec 6.5), and the report reads that version only."
Import from: 'protobase'.
Import from: 'erp_model'.

| space db moments asOf money report committedAt |
space := PBObjectSpace storage: (PBFileStorage path: (Smalltalk arguments at: 1)).
db := space openDatabase: 'erp'.
moments := { 1 -> 'invoices created'. 2 -> 'payments recorded'. 3 -> 'ACME renamed' }.

asOf := [:moment |
    | entry |
    entry := db history detect: [:each | each committedAt <= moment]
        ifNone: [PBUserError signal: 'the database did not exist yet'].
    db snapshotAt: entry].

money := [:cents |
    (cents // 100) printString , '.' , (cents \\ 100 < 10 ifTrue: ['0'] ifFalse: ['']) , (cents \\ 100) printString].

report := [:snapshot :title |
    | invoices paidNumbers |
    invoices := (snapshot getRootObject: 'invoices') values.
    ('== ' , title , ' (version ' , snapshot version printString , ') ==') displayNl.
    snapshot mutableNames do: [:cell |
        | mine billed paid |
        mine := invoices select: [:each | each customer name = cell].
        billed := mine inject: 0 into: [:sum :each | sum + (each total asExactFraction * 100) truncated].
        paid := (mine select: [:each | each isPaid])
            inject: 0 into: [:sum :each | sum + (each total asExactFraction * 100) truncated].
        (cell , ' | ' , (snapshot getMutable: cell) name , ' | ' , mine size printString , ' invoices | billed '
            , (money value: billed) , ' | paid ' , (money value: paid)) displayNl].
    paidNumbers := (invoices select: [:each | each isPaid]) collect: [:each | each number printString].
    ('paid invoices: ' , (paidNumbers isEmpty ifTrue: ['none'] ifFalse: [paidNumbers inject: '' into: [:acc :each |
        acc isEmpty ifTrue: [each] ifFalse: [acc , ' ' , each]]])) displayNl].

committedAt := Dictionary new.
db history do: [:entry | committedAt at: entry version put: entry committedAt].
moments do: [:each |
    report value: (asOf value: (committedAt at: each key))
        value: 'moment ' , each key printString , ': ' , each value].

(((db snapshotAt: db history first) getRootObject: 'tags') items inject: 'tags now:' into: [:acc :each |
    acc , ' ' , each key printString , '=' , each value]) displayNl.
space close.

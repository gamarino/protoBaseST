"EXPECT: ok 4"
"Reads in cluster mode without a majority (cluster plan Task 24 and its fix round 1; space.st
 _confirm, _permitTimeout; proto_db transactions.py at v2.0.0rc4 _read_storage_root, _run_round's
 permit bound, and coordinator.py current_root, recover_root). Real coordinators over one
 PBInProcessNetwork, each node a space over its own cluster-mode storage of one shared directory
 (_cluster_commit.st, _cluster_reads.st). Every wait is a condition with a deadline of 20 s, or a
 Future settled within 40 s; no duration is asserted; at most two attempts of a commit retried.
 (1) A space opened while no majority has a space gets no permission: its confirmation fails,
 logged, and the read starts from the committed root it knows; once a majority opens, every
 member commits
 (transactions::test_a_space_opened_while_no_majority_has_a_space_gets_no_permission_until_one_does).
 (2) Fix round 1, review I2: the permission wait of a cluster commit, the confirmation among them,
 is the space's lockTimeout when one was given (storage:coordinator:lockTimeout:), else the
 coordinator's acquireTimeout (storage:coordinator:), and the timeout's text names that bound.
 (3) A confirmation in progress succeeds once a majority opens its spaces, with no warning
 (transactions::test_a_confirmation_in_progress_succeeds_once_a_majority_opens_its_spaces).
 (4) A first newDatabase: whose recovery query goes unanswered conflicts, nothing created, and
 its retry creates the database once
 (transactions::test_a_setup_new_database_whose_recovery_query_goes_unanswered_conflicts_and_is_retried)."
Import from: 'protobase'.
Import from: '_check'.
Import from: '_cluster_commit'.
Import from: '_cluster_reads'.

| c base kit out notes lonely dbL f r bounded default explicit |
c := Check new.
base := FileSystem temp / ('pbst-cluster-reads-majority-' , Smalltalk pid printString).
base deleteAll.
base ensureCreateDirectory.
SeamRound setUp.
SeamSpace setUp.

"{ #timeout. its text } for the PBTimeoutError of a commit of aDatabase (no retries), else
 #committed."
bounded := [:aDatabase | [aDatabase run: Reads incr retries: 0. #committed] on: PBTimeoutError do: [:e |
  e return: { #timeout. e messageText }]].

Reads step: '(1)'.
"(1) and (2): a cluster that ran before, restarted with only n0's space open: first with
 storage:coordinator: (acquireTimeout 3000 ms), then reopened with lockTimeout 1000 ms (a reopened
 space confirms again)."
kit := Reads kit: CommitKit dir: base / 'majority' acquire: 3000.
kit openAll.
((kit space: 'n0') newDatabase: 'db') run: [:t | t setRootObject: 'counter' value: 0].
kit shutdown.
kit start.
notes := SeamSpace notes size.
lonely := kit open: 'n0'.
dbL := lonely openDatabase: 'db'.
default := { Reads notesAfter: notes prefix: 'n0 warn'. bounded value: dbL }.
out := { default first collect: [:x |
    { x includesSubstring: 'Confirming the committed root'. x includesSubstring: 'could not obtain a write permission' }].
  kit ids allSatisfy: [:id | ((kit node: id) stats at: 'grants_given') = 0].
  #('n1' 'n2') allSatisfy: [:id | ((kit node: id) stats at: 'grants_refused_no_storage') >= 1].
  default last first }.
lonely close.
notes := SeamSpace notes size.
lonely := kit open: 'n0' lockTimeout: 1000.
dbL := lonely openDatabase: 'db'.
explicit := { Reads notesAfter: notes prefix: 'n0 warn'. bounded value: dbL }.
c that: 'I2: a cluster commit and the confirmation wait for a permission up to the space''s lockTimeout when one was given, else acquireTimeout'
  is: { default first collect: [:x | x includesSubstring: 'within 3000 ms'].
    default last first = #timeout and: [default last last includesSubstring: 'within 3000 ms'].
    explicit first collect: [:x | x includesSubstring: 'within 1000 ms'].
    explicit last first = #timeout and: [explicit last last includesSubstring: 'within 1000 ms'] }
  equals: { #(true). true. #(true). true }.
notes := SeamSpace notes size.
kit open: 'n1'.
out := out , { Reads run: (kit db: 'db' on: 'n1') retries: 2. Reads run: dbL retries: 2.
  (Reads notesAfter: notes prefix: 'n0 warn') , (Reads notesAfter: notes prefix: 'n1 warn'). Reads counter: dbL }.
c that: 'a space opened while no majority has a space gets no permission until one does'
  is: out equals: { #(#(true true)). true. true. #timeout. #ok. #ok. #(). 2 }.
kit shutdown.

Reads step: '(3)'.
"(3) The same restart: n0's confirmation waits for a permission until n1 opens its space."
kit := Reads kit: CommitKit dir: base / 'majority' acquire: 30000.
notes := SeamSpace notes size.
lonely := kit open: 'n0'.
f := ReadWorker new asActor counterIn: lonely.
r := Atom on: false.
f thenDo: [:x | r swap: [:o | true]]; catch: [:e | r swap: [:o | true]].
out := { kit waitUntil: [#('n1' 'n2') allSatisfy: [:id | ((kit node: id) stats at: 'grants_refused_no_storage') >= 1]].
  r value not }.
kit open: 'n1'.
out := { out. { kit settle: f. Reads run: (kit db: 'db' on: 'n1') retries: 2. Reads run: (lonely openDatabase: 'db') retries: 2.
  (Reads notesAfter: notes prefix: 'n0 warn') , (Reads notesAfter: notes prefix: 'n1 warn'). Reads counterIn: lonely } }.
c that: 'a confirmation in progress succeeds once a majority opens its spaces'
  is: out equals: { #(true true). { 2. #ok. #ok. #(). 4 } }.
kit shutdown.

Reads step: '(4)'.
"(4)"
kit := Reads kit: DropKit dir: base / 'drop' acquire: 8000.
kit openAll.
DropEndpoint arm.
r := [(kit space: 'n0') newDatabase: 'db'. #created] on: PBConflictError do: [:e |
  e return: (e messageText includesSubstring: 'witnesses needed answered the recovery query')].
out := { r. kit waitUntil: [DropEndpoint dropped size = 2]. DropEndpoint dropped asSortedCollection asArray.
  (kit space: 'n0') listDatabases }.
r := nil.
1 to: 5 do: [:i | r isNil ifTrue: [
  r := [(kit space: 'n0') newDatabase: 'db'. #created] on: PBConflictError do: [:e | e return: nil]]].
((kit space: 'n0') openDatabase: 'db') run: [:t | t setRootObject: 'counter' value: 0].
out := out , { r. Reads run: ((kit space: 'n0') openDatabase: 'db') retries: 2. (kit space: 'n0') listDatabases.
  Reads counterIn: (kit space: 'n0') }.
c that: 'a setup newDatabase: whose recovery query goes unanswered conflicts, creates nothing, and its retry creates the database once'
  is: out equals: { true. true. #('n1' 'n2'). #(). #created. #ok. #('db'). 1 }.
kit shutdown.

base deleteAll.
c report.

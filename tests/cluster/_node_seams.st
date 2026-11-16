"_node_seams.st: the seams of the commit round that _node.st arms to kill a permission holder
 mid-round (plan Task 28; a helper, never run as a test).

  NodeSeamSpace      a PBObjectSpace whose cluster round is a NodeSeamRound
                     (PBObjectSpace >> _newClusterRound:proxy:, the space's seam)
  NodeSeamRound      a PBClusterRound that reaches three points of a round of the worker's own
                     commit (an entry that is not a confirmation, built under the round's
                     permission) and, at each, asks NodeSeams whether it is armed for it:
                       'built'      the root built and saved in the storage, before anything
                                    of it leaves the node (_build:)
                       'replicate'  its replicate handed to the coordinator, which sends it
                                    (_replicate:under:)
                       'done'       the done of the permission sent with #committed, every
                                    commit built under it settled (applyReportDone:)
  NodeSeams          the arming, shared by the process's main thread (the worker's commit loop)
                     and the round's runner:
    NodeSeams arm: aKind stage: s out: aDirectory log: aLog
                     the next round that reaches aKind tries once to create <out>/mark<s>
                     exclusively (#create #exclusive: one process wins); the winner writes
                     '<log> <kind> <token>...' there, synced, and then holds the runner: the
                     round never goes on, the driver kills the process with kill -9 while it
                     holds. A round that loses the mark goes on.
    NodeSeams disarm, NodeSeams armedStage (nil when not armed)
    NodeSeams current: aToken
                     the token of the commit the main thread starts (one committing thread)
    NodeSeams acknowledged: aToken
                     called by the main thread when run: returned, before it records the
                     acknowledgement: armed for 'done', it waits (60 s at most) until the round
                     has handled the done of the permission that committed aToken (the core
                     settles the commits of a round, then reports its done in the same step,
                     so the done may come before or after run: returns). When that done took
                     the mark, which then names aToken last, the thread holds too; else (the
                     mark lost to another process) it goes on. So a kill at 'done' always finds
                     aToken acknowledged by the cluster and not recorded by the worker: its
                     outcome unknown, the token present on every node.

 What the mark names, the token in flight at the kill (the killed worker's one unresolved token):
  'built'      that token, never sent: absent on every node;
  'replicate'  that token, sent: present on every node or on none;
  'done'       every token built under the permission, the one in flight last: committed,
               present on every node.
 Only the round of a commit of the worker reaches a point: a round that re-commits a base, or a
 confirmation, builds no entry of the worker and is never held."
Import from: 'protobase'.

Object subclass: #NodeSeams instanceVariableNames: '' classVariableNames: 'Armed Current DoneArmed DoneOf Fired'.

"Armed: the arming a round claims (nil once claimed or disarmed). DoneArmed: armed for 'done',
 kept while the round claims (only the main thread clears it). DoneOf: the last token of the
 latest permission whose done the round handled. Fired: a round took a mark."
NodeSeams class >> setUp
  Armed := Atom on: nil.
  Current := Atom on: nil.
  DoneArmed := Atom on: false.
  DoneOf := Atom on: nil.
  Fired := Atom on: false.

NodeSeams class >> arm: aKind stage: s out: aDirectory log: aLog
  DoneArmed swap: [:old | aKind = 'done'].
  Armed swap: [:old | { aKind. s. aDirectory. aLog }].

NodeSeams class >> disarm
  Armed swap: [:old | nil].
  DoneArmed swap: [:old | false].

NodeSeams class >> armedStage
  | a |
  a := Armed value.
  ^ a isNil ifTrue: [nil] ifFalse: [a at: 2].

NodeSeams class >> current: aToken
  Current swap: [:old | aToken].

NodeSeams class >> current
  ^ Current value.

"The round handled the done of a permission whose last commit carried aToken."
NodeSeams class >> doneOf: aToken
  DoneOf swap: [:old | aToken].

NodeSeams class >> acknowledged: aToken
  | deadline |
  DoneArmed value ifFalse: [^ self].
  deadline := Time millisecondClockValue + 60000.
  [Fired value or: [DoneOf value = aToken or: [Time millisecondClockValue > deadline]]]
    whileFalse: [(Future after: 5) wait].
  Fired value ifTrue: [
    "The mark is taken: the runner holds until the kill; so does this thread."
    [true] whileTrue: [(Future after: 1000) wait]].
  DoneOf value = aToken ifFalse: [
    Stdio stderr nextPutAll: 'seam: no done of ' , aToken , ' within 60 s; disarmed'; lf; flush.
    self disarm].

"Called by a round at aKind with the tokens its commit carries (the one in flight last): the
 armed round takes the mark, or loses it and goes on. The winner holds the runner: answers only
 after 300 s without a kill (the driver failed), and then the round goes on."
NodeSeams class >> reach: aKind tokens: anArray
  | a f out |
  a := Armed value.
  (a notNil and: [a first = aKind]) ifFalse: [^ self].
  (Armed value: nil ifCurrent: a) ifFalse: [^ self].
  out := a at: 3.
  f := [BinaryFile open: (out / ('mark' , (a at: 2) printString)) options: #(#write #create #exclusive)]
    on: FileAlreadyExists do: [:e | e return: nil].
  f isNil ifTrue: [^ self].
  f append: ((anArray inject: (a at: 4) , ' ' , aKind into: [:acc :t | acc , ' ' , t])
    , (String with: Character lf)) utf8Encoded.
  f sync.
  f close.
  Fired swap: [:old | true].
  Stdio stderr nextPutAll: (a at: 4) , ': took mark' , (a at: 2) printString , ' at ' , aKind
    , ' with ' , anArray last , ' in flight; holding the round'; lf; flush.
  1 to: 3000 do: [:i | (Future after: 100) wait].
  Stdio stderr nextPutAll: (a at: 4) , ': mark held 300 s without a kill; the round goes on'; lf; flush.

NodeSeams setUp.

PBClusterRound subclass: #NodeSeamRound instanceVariableNames: 'built'.

"The worker's tokens built under the current permission (since the last done), in build order.
 The round runs on its runner, one message at a time: a plain variable."
NodeSeamRound >> builtTokens
  built isNil ifTrue: [built := #()].
  ^ built.

NodeSeamRound >> _build: aBuild
  | root |
  root := super _build: aBuild.
  (root notNil and: [aBuild entry notNil and: [NodeSeams current notNil]]) ifTrue: [
    built := self builtTokens copyWith: NodeSeams current.
    NodeSeams reach: 'built' tokens: { NodeSeams current }].
  ^ root.

NodeSeamRound >> _replicate: aRoot under: aPermission
  | f |
  f := super _replicate: aRoot under: aPermission.
  self builtTokens isEmpty ifFalse: [NodeSeams reach: 'replicate' tokens: { self builtTokens last }].
  ^ f.

NodeSeamRound >> applyReportDone: anEffect
  | tokens |
  tokens := self builtTokens.
  built := #().
  super applyReportDone: anEffect.
  (anEffect outcome = #committed and: [tokens notEmpty and: [NodeSeams current = tokens last]]) ifTrue: [
    NodeSeams reach: 'done' tokens: tokens].
  tokens isEmpty ifFalse: [NodeSeams doneOf: tokens last].

PBObjectSpace subclass: #NodeSeamSpace instanceVariableNames: ''.

NodeSeamSpace >> _newClusterRound: aPublisher proxy: aCell
  ^ NodeSeamRound space: self publisher: aPublisher proxy: aCell.

# The cluster examples

Programs for the cluster chapters of the tutorial,
[docs/tutorial/13-16](../../docs/tutorial/README.md#cluster-mode-020-unreleased-in-progress). Each
one checks what it shows, like the lessons of [examples/tutorial/](../tutorial/README.md) (whose
`_lesson.st` they import): a line per check, and a last line `<lesson> ok (N checks)`; a failed
check exits with status 1.

| File | Shows | Chapter |
|---|---|---|
| [13_terms_and_majorities.st](13_terms_and_majorities.st) | voters, majorities, ballots, the lease margin, refused options; pure values | [13](../../docs/tutorial/13-cluster-concepts.md) |
| [14_three_nodes.st](14_three_nodes.st) | three coordinators over `PBInProcessNetwork`, the shared directory, a cluster forming, a permission | [14](../../docs/tutorial/14-a-three-node-cluster.md) |
| [14_three_nodes_tcp.st](14_three_nodes_tcp.st) | the same over TCP on localhost | [14](../../docs/tutorial/14-a-three-node-cluster.md) |
| [15_losing_members.st](15_losing_members.st) | a voter dies, then the owner: the member left alone times out; a restart on an intact disk and its startup grace | [15](../../docs/tutorial/15-failures-and-recovery.md) |
| [15_wiped_disk.st](15_wiped_disk.st) | a lost acceptor log and a rejoin by ballot; a double start refused | [15](../../docs/tutorial/15-failures-and-recovery.md) |
| [16_configuration.st](16_configuration.st) | defaults, the rules among options, the timer table, `stats`, the startup grace over a used log | [16](../../docs/tutorial/16-operating-a-cluster.md) |

[pending/](pending/README.md) holds the programs that need commits and reads in cluster mode:
`14_cluster_commits.st.pending` needs Tasks 23 to 25 of the cluster plan,
`15_majority_loss.st.pending` Tasks 23 and 24. They have never run; their `.st.pending` extension keeps
them out of the test runner.

## Run them

```sh
export PROTOST=../protoST/build_release/protost        # protoST 0.12.0 or newer
tests/run_tests.sh examples/cluster                     # from the repository root
cd examples/cluster && STPATH=$PWD/../../src $PROTOST 14_three_nodes.st
```

Each program works in its own directory under `FileSystem temp` (`pbst-cluster-NN-<pid>`) and
deletes it at the end. No program asserts a duration: every wait is a condition polled with a
deadline of 60 s, which only turns a hang into a failure. The durations they configure are short
so that they run in seconds; they decide liveness only.

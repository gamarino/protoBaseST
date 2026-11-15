# Pending cluster examples

These programs are written against the API that the cluster plan
([docs/superpowers/plans/2026-11-13-cluster-mode.md](../../../docs/superpowers/plans/2026-11-13-cluster-mode.md))
specifies for tasks that have not landed yet. They have never run. Their extension,
`.st.pending`, keeps them out of `tests/run_tests.sh`, which runs only `*.st` and `*.sh` files.

| Program | Chapter | Runs once |
|---|---|---|
| `14_cluster_commits.st.pending` | [14](../../../docs/tutorial/14-a-three-node-cluster.md) | Task 23 (cluster commits), Task 24 (reads, `committedEpoch`), Task 25 (the persister, `sync:`) |
| `15_majority_loss.st.pending` | [15](../../../docs/tutorial/15-failures-and-recovery.md) | Task 23 (cluster commits), Task 24 (reads after a rejoin) |

When the tasks a program needs are merged: move it to `examples/cluster/` without the `.pending`
suffix, update the `<!-- example: -->` line of its chapter, run it with
`tests/run_tests.sh examples/cluster/<name>.st`, and correct the program and the chapter together
wherever the built API differs from the plan. `tests/docs/tutorial_chapters_sync.sh` keeps the
chapter's code blocks equal to the program in both places.

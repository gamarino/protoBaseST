# Pending cluster examples

These programs are written against the API that the cluster plan
([docs/superpowers/plans/2026-11-13-cluster-mode.md](../../../docs/superpowers/plans/2026-11-13-cluster-mode.md))
specifies for tasks that have not landed yet. Their extension,
`.st.pending`, keeps them out of `tests/run_tests.sh`, which runs only `*.st` and `*.sh` files.

None is pending today: `15_majority_loss.st` left this directory with Task 24, and
`14_cluster_commits.st` with Task 25. A chapter section that quotes a pending program says so.

When the tasks a program needs are merged: move it to `examples/cluster/` without the `.pending`
suffix, update the `<!-- example: -->` line of its chapter, run it with
`tests/run_tests.sh examples/cluster/<name>.st`, and correct the program and the chapter together
wherever the built API differs from the plan. `tests/docs/tutorial_chapters_sync.sh` keeps the
chapter's code blocks equal to the program in both places.

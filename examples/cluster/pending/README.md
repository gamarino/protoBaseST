# Pending cluster examples

This directory holds cluster programs written ahead of the API they need. Their extension,
`.st.pending`, keeps them out of `tests/run_tests.sh`, which runs only `*.st` and `*.sh` files.

**It is empty today, and kept on purpose.** Every cluster program now runs as a test:
`15_majority_loss.st` left this directory with Task 24, and `14_cluster_commits.st` with
Task 25. The directory stays because the documentation guard supports it:
`tests/docs/tutorial_chapters_sync.sh` checks the code a chapter quotes against a pending program
as well as against a running one, and requires a chapter to name every pending program. The next
plans (the runtime registry and format 5, or tiered storage) can write their chapters' programs
here before their API exists, and the chapters stay checked meanwhile.

When the API a program needs is merged: move it to `examples/cluster/` without the `.pending`
suffix, update the `<!-- example: -->` line of its chapter, run it with
`tests/run_tests.sh examples/cluster/<name>.st`, and correct the program and the chapter together
wherever the built API differs from the plan. A chapter section that quotes a pending program
says so.

Use subagents when you think delegation helps.

Set `model` and `effort` explicitly on every Agent call and every workflow
`agent()` — never omit either. Omission is not neutral: it silently falls back
to a default without a decision being made. Choose both purely on your own
judgment of the task, independently of each other: any effort can pair with any
model family. Matching runs in both directions: the strongest family or highest
effort on a routine task is as much a mismatch as a weak one on a hard task, so
the session's own model and effort are options among all of them — chosen
deliberately when the task warrants it, never kept by inheritance.

If subagent or workflow tasks start failing because the current model family is
rate-limited, switch those agents to another suitable family (e.g. Opus) and
continue, telling me — do not let agents fail repeatedly on a rate-limited
model.

# KCL CREATE HPC

CREATE (ssh host `create`) is reached over SSH behind an MFA window that
lapses. Load the `kcl-create-hpc` skill for the cluster's boundaries, paths
and reference notes; this section owns the workflow.

- Run anything longer than a quick one-off command, such as tests, pipelines,
  environment builds and container pulls, as a self-contained `sbatch` job that
  writes its results and a summary to scratch. A job never depends on the SSH
  session.
- Submit, record the job ID, estimate the finish time, and check once around
  then. Do not poll continuously.
- Use one multiplexed connection only for a burst of small commands (inspecting
  results, staging several files, submit-fix-resubmit, polling a job) or when
  a later check should not need the MFA to still be valid. Pass
  `-o ControlMaster=auto -o ControlPath=~/.ssh/cm-%C -o ControlPersist=4h` on
  every `ssh`/`scp` call to CREATE in that burst: the first call authenticates
  and leaves a master open, the rest ride on it. `ssh -o ControlPath=~/.ssh/cm-%C
  -O check create` shows whether it is alive, `-O exit` closes it. A single
  submit-and-check needs none of this. These options live here, not in
  `~/.ssh/config`.
- "Connection closed" before authentication, or "Exceeded MaxStartups", is the
  login node throttling unauthenticated handshakes: wait, do not loop. A QR code
  with a link to https://portal.arc.kcl.ac.uk/mfa/ means the MFA has lapsed:
  notify the user and ask them to re-validate; never retry in a loop or work
  around it.

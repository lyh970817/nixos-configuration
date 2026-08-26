# Access and Slurm

Official documentation consulted 2026-08-25:

- [Accessing CREATE HPC](https://docs.er.kcl.ac.uk/CREATE/access/)
- [Running jobs](https://docs.er.kcl.ac.uk/CREATE/running_jobs/)
- [Compute nodes and partitions](https://docs.er.kcl.ac.uk/CREATE/compute_nodes/)
- [Scheduler policy](https://docs.er.kcl.ac.uk/CREATE/scheduler_policy/)
- [CREATE training introduction](https://hpc-training.sites.er.kcl.ac.uk/)

## Connect and separate control from compute

Connect through the stable front door:

```bash
ssh <k-number>@hpc.create.kcl.ac.uk
```

The current access page says it redirects among current login nodes; do not hard-code historical `login1` or `login2` examples. Access requires an active account, registered public key, host-key verification, and MFA.

Keep login-node activity brief. Use it to inspect, transfer modest files, prepare scripts, and submit or monitor work. Use a login shell in an interactive allocation so modules initialize:

```bash
srun -p cpu --time=01:00:00 --cpus-per-task=2 --mem=8G --pty /bin/bash -l
```

The documented interactive limit is four hours. Prefer batch jobs for reproducible or long-running work:

```bash
sbatch -p cpu job.sbatch
squeue -u "$USER"
sacct -j <jobid> --format=JobID,JobName,Partition,State,Elapsed,AllocCPUS,ReqMem,MaxRSS,ExitCode,NodeList
scancel <jobid>  # only when cancellation is authorized
```

Use `#!/bin/bash -l` in batch scripts. Request realistic `--time`, `--cpus-per-task`, and `--mem`; identify the live partition rather than copying an old example. Current general-use partition families include `cpu`, `gpu`, `long_cpu`, `long_gpu`, and `interruptible_cpu`. The current normal `cpu`/`gpu` limit is 48 hours; interruptible capacity can be reclaimed. Verify live `sinfo` and policy before relying on limits.

## Evidence and stopping conditions

- Record the job ID returned by `sbatch` and the exact submitted script.
- Monitor to a terminal state; queued or running is not completion.
- For failures, inspect the Slurm state, exit code, stdout/stderr, and `sacct` resource record before retrying.
- Do not repeatedly increase resources without evidence. Stop when the task requires new authorization, an unavailable allocation, protected data, administrative capability, or cleanup outside the explicit scope.

Documentation caveat: the running-jobs page contains an example under `/scratch/k1234567`; the current storage documentation defines personal scratch as `/scratch/users/<k-number>`. Use the latter unless live, authorized context establishes another path. A transfer page also says `squeue` submits a job, but CREATE's job documentation correctly uses `sbatch` to submit and `squeue` to inspect.

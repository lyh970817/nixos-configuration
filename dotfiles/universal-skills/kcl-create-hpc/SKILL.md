---
name: kcl-create-hpc
description: Operate safely on King's College London CREATE HPC, including SSH access, Slurm jobs, CREATE storage and quota checks, software modules, Singularity containers, and data transfer. Use for CREATE-specific execution or diagnosis; do not use as generic Slurm guidance for other clusters.
---

# KCL CREATE HPC

Use CREATE as a scheduler-managed research system. Confirm the SSH identity, data classification, exact readable sources, and exact writable destinations from the request or live system; loading this skill does not authorize a connection, job submission, file transfer, or cleanup.

## Stable boundaries

- Treat login nodes as the control plane: inspect, edit small files, transfer modest data, and submit or monitor jobs. Run computation, builds, package installation, container work, and sustained I/O in Slurm allocations.
- Never use `sudo`, bypass Slurm, change shared permissions, or write into protected datasets.
- Treat `/datasets/bioresource` as a user-supplied, access-controlled, read-only source. Check access live. Never create, overwrite, delete, rename, chmod, or clean anything beneath it.
- Default user-owned locations are `/users/<k-number>` for backed-up code/configuration and `/scratch/users/<k-number>` for active I/O. Scratch is not backed up. Do not infer permission for project/group scratch or for cleanup; use only destinations the user explicitly placed in scope.
- Do not reveal secrets, SSH material, identifiable sample data, or sensitive file contents. Prefer aggregate dimensions, file sizes, checksums, versions, job IDs, and paths when reporting provenance.
- Check `ceph_quota` before staging data, creating environments or images, or launching output-producing jobs. A full or over-quota destination is a blocker, not permission to delete old work or switch to another allocation.
- Source access does not by itself authorize derived data, logs, or caches in personal scratch. Confirm the requested destination is permitted for the data classification, and budget for images, caches, temporary/intermediate data, final output, and headroom.

## Route the task

- For SSH, login-versus-compute behavior, Slurm resources, job monitoring, and scheduler policy, read [references/access-and-slurm.md](references/access-and-slurm.md).
- For home/scratch/project/dataset/RDS distinctions, quotas, cleanup, and transfers, read [references/storage-and-transfer.md](references/storage-and-transfer.md).
- For Environment Modules, Python environments, Singularity, and any FUSE-dependent plan, read [references/software-and-containers.md](references/software-and-containers.md).

## Live preflight

Verify inexpensive, drift-prone facts instead of relying on examples in documentation:

```bash
ssh <k-number>@hpc.create.kcl.ac.uk
ceph_quota
sinfo -s
squeue -u "$USER"
```

On the remote host, resolve source and destination mounts with `findmnt -T`, inspect source files without changing them, and record the intended path boundary. For a Slurm run, capture the submitted job ID immediately and keep monitoring until a terminal state. Use `sacct -j <jobid> --format=JobID,JobName,Partition,State,Elapsed,AllocCPUS,ReqMem,MaxRSS,ExitCode,NodeList` after completion; preserve command, versions, log paths, and scheduler metrics.

If the task depends on an undocumented capability such as FUSE, test it with a non-sensitive synthetic fixture in a small compute allocation before designing around it. Exhaust safe user-space and documented container routes, but do not escalate privileges or alter cluster configuration. Report the exact failed capability and evidence when blocked.

## Completion report

State the SSH target and retrieval/live-check date, exact source identity without sensitive contents, writable paths used, Slurm job IDs and terminal states, requested and observed resources, software/container versions, commands or retained scripts, output identities/sizes/checksums, and limitations such as cache state. Distinguish documentation-derived guidance from facts verified on the live cluster.

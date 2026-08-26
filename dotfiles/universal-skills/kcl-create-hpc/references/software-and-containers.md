# Software, containers, and FUSE

Official documentation consulted 2026-08-25:

- [Running jobs and modules](https://docs.er.kcl.ac.uk/CREATE/running_jobs/)
- [CREATE training: accessing software](https://hpc-training.sites.er.kcl.ac.uk/using_software/)
- [Singularity on CREATE](https://docs.er.kcl.ac.uk/CREATE/software/singularity/)

## Modules and user environments

CREATE uses Spack-managed Environment Modules and does not preload scientific software. Initialize a login shell and discover live versions:

```bash
module avail
module spider <package>
module load <package>/<available-version>
module list
```

Do not embed versions copied from training examples. Install user-space environments only in an authorized home or scratch location and perform builds/package installation in a Slurm allocation. Do not use system package managers or write into system locations.

## Singularity

Singularity is the container runtime documented by CREATE and is available only on compute nodes. Pull, build, inspect, exec, and run images within an allocation. No current official CREATE documentation found on 2026-08-25 establishes an `apptainer` command or alias, so probe rather than assume it.

Keep cache and temporary storage in exact authorized paths:

```bash
export SINGULARITY_CACHEDIR="/scratch/users/<k-number>/singularity/cache"
export SINGULARITY_TMPDIR="/scratch/users/<k-number>/<job-id>/tmp"
mkdir -p "$SINGULARITY_CACHEDIR" "$SINGULARITY_TMPDIR"
singularity exec --bind /exact/authorized/source:/work:ro image.sif command
```

Use narrow binds and immutable image identifiers/checksums. Bind protected inputs read-only and bind a separate exact writable destination when needed. Do not broadly bind all of `/scratch` or protected dataset trees when a precise source suffices. GPU images require `--nv`.

## FUSE-dependent work

CREATE's current public documentation does not document `/dev/fuse`, `fusermount3`, Singularity `--fusemount`, required kernel features, or a supported user-space FUSE workflow. Treat FUSE as an unconfirmed live capability.

Check it on the allocated compute node, not the login node:

```bash
ls -l /dev/fuse
grep -w fuse /proc/filesystems
command -v fusermount3
singularity --version
singularity exec image.sif test -r /dev/fuse
```

A readable device alone is not proof that mounting works. Use a tiny read-only fixture in a short job to test the exact native or containerized mount/unmount lifecycle. Keep the mount and consumer in the same allocation and process namespace; wait for mount readiness and always unmount/terminate the foreground mount before the job exits. Never use `sudo`, request extra privileges, change device permissions, or alter host/container configuration. If the native dependency cannot be installed in user space or the device/runtime blocks the mount, retain logs and report the exact failure as an administrative/platform blocker.

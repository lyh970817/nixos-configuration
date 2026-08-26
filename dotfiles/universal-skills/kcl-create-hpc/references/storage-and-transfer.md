# Storage, quota, cleanup, and transfer

Official documentation consulted 2026-08-25:

- [Storage](https://docs.er.kcl.ac.uk/CREATE/storage/)
- [Dataset Guide](https://docs.er.kcl.ac.uk/CREATE/dataset/)
- [Transferring files to and from CREATE](https://docs.er.kcl.ac.uk/CREATE/rsync_and_scp/)
- [CREATE Terms of Use](https://docs.er.kcl.ac.uk/CREATE/terms/)
- [Requesting access](https://docs.er.kcl.ac.uk/CREATE/requesting_access/)

## Choose a destination by contract

| Location | Contract |
|---|---|
| `/users/<k-number>` | Backed-up personal home for code, configuration, environments, and small material; default documented allocation 50 GiB. Filling it can prevent login. |
| `/scratch/users/<k-number>` | Personal active-job and high-I/O space; not backed up; default documented allocation 200 GiB. |
| `/scratch/prj/<project>` | Shared active project space with a separate allocation; use only when the user has authorized that exact project scope. |
| `/scratch/groups/<group>` | Group/legacy shared space; verify live authorization and purpose. |
| `/scratch/datasets/<dataset-id>` | Current administrator-provisioned dataset-share convention, normally read-only to consumers. |
| `/datasets/...` | Older/shared dataset namespace documented by the Dataset Guide; treat each path as access-controlled and verify it live. |
| `/rds/prj/<project>` | Durable RDS project storage; not mounted on compute nodes. |

The Dataset Guide lists Bioresource as a requested-access dataset. For this user's known `/datasets/bioresource` location, preserve the literal path as a site fact while treating the entire subtree as read-only. Do not substitute `/scratch/datasets/bioresource` or assume either namespace without live verification.

## Quota and cleanup

Run before writes and again after large output:

```bash
ceph_quota
rds_quota  # when RDS is involved
```

If quota is tight, inventory read-only first (`du`, `find`, ownership/mtime, `squeue`, and relevant process/job working directories). Large size alone is not a cleanup decision. Delete only exact, verified, user-authorized generated paths; recheck active references and post-delete quota. Never clean protected datasets, unrelated workflow state, or an entire broad directory through a glob.

Scratch is not durable. Preserve needed final outputs and provenance in an authorized backed-up destination before cleanup. CREATE's terms require completed-project data to be moved, archived, or deleted under the responsible project process, not ad hoc by an agent.

## Transfer

For ordinary encrypted transfer, use `scp`, `sftp`, or `rsync -avHS` through the documented CREATE endpoints. The transfer guide describes ordinary transfers up to roughly 500 GB and recommends a suitable allocation/workflow or the data mover for larger operations. Use `tmux` or `screen` for long transfer sessions.

The dedicated mover is:

```bash
ssh <k-number>@erc-hpc-dm1.create.kcl.ac.uk
```

RDS is not available inside `sbatch` or `srun` allocations. Move RDS data through the documented data mover, not from compute-job scripts. After very large writes on Ceph, avoid immediately chaining rename/move operations merely to reorganize data; the documentation warns replication may still be completing.

For restricted datasets, do not copy data beyond the authorized research/storage boundary. Record source identity and checksums without exposing sample contents.
